from fastapi import APIRouter, HTTPException, status
import httpx

from app.core.config import settings

router = APIRouter(prefix="/meal-plans", tags=["meal-plan-reads"])


def _headers() -> dict[str, str]:
    return {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
    }


async def _get(client: httpx.AsyncClient, path: str, params: dict):
    response = await client.get(
        f"{settings.supabase_url.rstrip('/')}/rest/v1/{path}",
        params=params,
        headers=_headers(),
    )
    if response.status_code != 200:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Supabase read failed ({response.status_code}): {response.text}",
        )
    return response.json()


@router.get("/{user_id}")
async def get_user_meal_plan(user_id: str):
    """Return the active meal plan and its meals for a user."""
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise HTTPException(status_code=503, detail="Supabase backend configuration is missing.")

    try:
        async with httpx.AsyncClient(timeout=20) as client:
            plans = await _get(
                client,
                "meal_plans",
                {
                    "select": "id,user_id,start_date,end_date,status,created_at",
                    "user_id": f"eq.{user_id}",
                    "status": "eq.active",
                    "order": "created_at.desc",
                    "limit": "1",
                },
            )
            if not plans:
                raise HTTPException(status_code=404, detail="No active meal plan found for this user.")

            plan = plans[0]
            meals = await _get(
                client,
                "meals",
                {
                    "select": "id,meal_plan_id,meal_date,meal_type,name,description,created_at",
                    "meal_plan_id": f"eq.{plan['id']}",
                    "order": "meal_date.asc,meal_type.asc",
                },
            )
            return {"meal_plan": plan, "meals": meals}
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=503, detail="Could not reach Supabase.") from exc


@router.get("/{meal_plan_id}/ingredients")
async def get_meal_plan_ingredients(meal_plan_id: str, user_id: str):
    """Return all saved ingredients grouped by meal."""
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise HTTPException(status_code=503, detail="Supabase backend configuration is missing.")

    try:
        async with httpx.AsyncClient(timeout=20) as client:
            plans = await _get(client, "meal_plans", {
                "select": "id",
                "id": f"eq.{meal_plan_id}",
                "user_id": f"eq.{user_id}",
                "limit": "1",
            })
            if not plans:
                raise HTTPException(status_code=404, detail="Meal plan not found for this user.")

            meals = await _get(client, "meals", {
                "select": "id,meal_date,meal_type,name",
                "meal_plan_id": f"eq.{meal_plan_id}",
                "order": "meal_date.asc,meal_type.asc",
            })
            ingredients = await _get(client, "meal_ingredients", {
                "select": "id,meal_id,ingredient_name,quantity,unit,created_at",
                "meal_id": "in.(" + ",".join(str(m["id"]) for m in meals) + ")",
                "order": "created_at.asc",
            }) if meals else []

            grouped = []
            by_meal = {str(m["id"]): [] for m in meals}
            for item in ingredients:
                by_meal.setdefault(str(item["meal_id"]), []).append(item)
            for meal in meals:
                grouped.append({**meal, "ingredients": by_meal.get(str(meal["id"]), [])})
            return {"meal_plan_id": meal_plan_id, "meals": grouped}
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=503, detail="Could not reach Supabase.") from exc


@router.get("/{meal_plan_id}/grocery-list")
async def get_meal_plan_grocery_list(meal_plan_id: str, user_id: str):
    """Return the saved grocery list and its items."""
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise HTTPException(status_code=503, detail="Supabase backend configuration is missing.")

    try:
        async with httpx.AsyncClient(timeout=20) as client:
            plans = await _get(client, "meal_plans", {
                "select": "id",
                "id": f"eq.{meal_plan_id}",
                "user_id": f"eq.{user_id}",
                "limit": "1",
            })
            if not plans:
                raise HTTPException(status_code=404, detail="Meal plan not found for this user.")

            lists = await _get(client, "grocery_lists", {
                "select": "id,user_id,meal_plan_id,status,created_at,updated_at",
                "meal_plan_id": f"eq.{meal_plan_id}",
                "user_id": f"eq.{user_id}",
                "order": "created_at.desc",
                "limit": "1",
            })
            if not lists:
                raise HTTPException(status_code=404, detail="No grocery list found for this meal plan.")

            grocery_list = lists[0]
            items = await _get(client, "grocery_items", {
                "select": "id,grocery_list_id,ingredient_name,required_quantity,purchase_quantity,unit,category,is_purchased,is_urgent,created_at,updated_at",
                "grocery_list_id": f"eq.{grocery_list['id']}",
                "order": "ingredient_name.asc",
            })
            return {"grocery_list": grocery_list, "items": items}
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=503, detail="Could not reach Supabase.") from exc
