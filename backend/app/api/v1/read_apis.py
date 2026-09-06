from fastapi import APIRouter, HTTPException, status
import httpx

from app.core.config import settings
from app.schemas.grocery import GroceryListResponse
from app.schemas.ingredients import GeneratedIngredients

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
    """Return the active meal plan stored in the current meal/meal_plan schema."""
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise HTTPException(status_code=503, detail="Supabase backend configuration is missing.")

    try:
        async with httpx.AsyncClient(timeout=20) as client:
            plans = await _get(
                client,
                "meal",
                {
                    "select": "id,user_id,start_date,end_date,status,generation_source,created_at,updated_at",
                    "user_id": f"eq.{user_id}",
                    "status": "eq.active",
                    "order": "created_at.desc",
                    "limit": "1",
                },
            )
            if not plans:
                raise HTTPException(status_code=404, detail="No active meal plan found for this user.")

            plan = plans[0]
            rows = await _get(
                client,
                "meal_plan",
                {
                    "select": "id,meal_id,meal_date,meal_type,source_recipe_code,name,description,status,prep_time_minutes,nutrition,created_at,updated_at",
                    "meal_id": f"eq.{plan['id']}",
                    "order": "meal_date.asc,meal_type.asc",
                },
            )
            meals = [
                {
                    "id": row["id"],
                    "meal_plan_id": row["meal_id"],
                    "meal_date": row["meal_date"],
                    "meal_type": row["meal_type"],
                    "source_recipe_code": row.get("source_recipe_code"),
                    "name": row["name"],
                    "description": row.get("description"),
                    "status": row.get("status", "planned"),
                    "prep_time_minutes": row.get("prep_time_minutes"),
                    "nutrition": row.get("nutrition") or {},
                    "created_at": row.get("created_at"),
                    "updated_at": row.get("updated_at"),
                }
                for row in rows
            ]
            return {"meal_plan": plan, "meals": meals}
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=503, detail="Could not reach Supabase.") from exc


@router.get("/{meal_plan_id}/ingredients", response_model=GeneratedIngredients)
async def get_meal_plan_ingredients(meal_plan_id: str, user_id: str):
    """Return ingredient rows from the same authoritative RPC used by generation."""
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise HTTPException(status_code=503, detail="Supabase backend configuration is missing.")

    try:
        async with httpx.AsyncClient(timeout=20) as client:
            plans = await _get(client, "meal", {
                "select": "id",
                "id": f"eq.{meal_plan_id}",
                "user_id": f"eq.{user_id}",
                "limit": "1",
            })
            if not plans:
                raise HTTPException(status_code=404, detail="Meal plan not found for this user.")

            response = await client.post(
                f"{settings.supabase_url.rstrip('/')}/rest/v1/rpc/get_meal_plan_ingredients",
                json={"p_meal_plan_id": meal_plan_id},
                headers={**_headers(), "Content-Type": "application/json", "Accept": "application/json"},
            )
            if response.status_code != 200:
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail=f"Supabase ingredient RPC failed ({response.status_code}): {response.text}",
                )

            ingredients = response.json()
            if not isinstance(ingredients, list) or not ingredients:
                raise HTTPException(status_code=404, detail="No ingredients found for this meal plan.")

            return {
                "meal_plan_id": meal_plan_id,
                "item_count": len(ingredients),
                "ingredients": ingredients,
            }
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=503, detail="Could not reach Supabase.") from exc


@router.get("/{meal_plan_id}/grocery-list", response_model=GroceryListResponse)
async def get_meal_plan_grocery_list(meal_plan_id: str, user_id: str):
    """Return the saved grocery list and its items for a meal plan."""
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise HTTPException(status_code=503, detail="Supabase backend configuration is missing.")

    try:
        async with httpx.AsyncClient(timeout=20) as client:
            plans = await _get(client, "meal", {
                "select": "id",
                "id": f"eq.{meal_plan_id}",
                "user_id": f"eq.{user_id}",
                "limit": "1",
            })
            if not plans:
                raise HTTPException(status_code=404, detail="Meal plan not found for this user.")

            lists = await _get(client, "grocery_lists", {
                "select": "id,user_id,meal_id,status,created_at,updated_at",
                "meal_id": f"eq.{meal_plan_id}",
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
            return {
                "grocery_list_id": grocery_list["id"],
                "meal_id": meal_plan_id,
                "item_count": len(items),
                "items": items,
            }
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=503, detail="Could not reach Supabase.") from exc
