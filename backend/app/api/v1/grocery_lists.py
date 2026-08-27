from fastapi import APIRouter, HTTPException, status
import httpx

from app.core.config import settings
from app.services.grocery_list_service import GroceryListError, aggregate_ingredients

router = APIRouter(prefix="/meal-plans", tags=["grocery-lists"])


@router.post("/{meal_id}/grocery-list")
async def generate_grocery_list(meal_id: str, user_id: str):
    """Aggregate saved meal ingredients in Python and save one grocery list."""
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Supabase backend configuration is missing.")

    base_url = settings.supabase_url.rstrip("/")
    headers = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }

    try:
        async with httpx.AsyncClient(timeout=20) as client:

            ingredients_response = await client.get(
                f"{base_url}/rest/v1/meal_ingredients",
                params={
                    "select": "meal_id,food_code_org,food_name,amount,unit",
                    "meal_id": f"eq.{meal_id}"
                },
                headers=headers,
            )
            if ingredients_response.status_code != 200:
                raise HTTPException(status_code=502, detail="Could not load meal ingredients from Supabase.")

            grocery_items = aggregate_ingredients(ingredients_response.json())
            if not grocery_items:
                raise HTTPException(status_code=422, detail="No meal ingredients found for this meal plan.")

            existing_response = await client.get(
                f"{base_url}/rest/v1/grocery_lists",
                params={"select": "id", "meal_id": f"eq.{meal_id}", "limit": "1"},
                headers=headers,
            )
            if existing_response.status_code != 200:
                raise HTTPException(status_code=502, detail="Could not check existing grocery list.")

            existing = existing_response.json()
            if existing:
                grocery_list_id = existing[0]["id"]
                delete_response = await client.delete(
                    f"{base_url}/rest/v1/grocery_items",
                    params={"grocery_list_id": f"eq.{grocery_list_id}"},
                    headers=headers,
                )
                if delete_response.status_code not in (200, 204):
                    raise HTTPException(status_code=502, detail=f"Could not clear existing grocery items: {delete_response.text}")

            create_list = await client.post(
                f"{base_url}/rest/v1/grocery_lists",
                json={"user_id": user_id, "meal_id": meal_id, "status": "active"},
                headers=headers,
            )
            if create_list.status_code not in (200, 201):
                raise HTTPException(status_code=502, detail=f"Could not create grocery list: {create_list.text}")
            grocery_list_id = create_list.json()[0]["id"]

            rows = [dict(item, grocery_list_id=grocery_list_id) for item in grocery_items]
            save_items = await client.post(
                f"{base_url}/rest/v1/grocery_items",
                json=rows,
                headers=headers,
            )
            if save_items.status_code not in (200, 201, 204):
                raise HTTPException(status_code=502, detail=f"Could not save grocery items: {save_items.text}")

            return {
                "grocery_list_id": grocery_list_id,
                "meal_id": meal_id,
                "item_count": len(grocery_items),
                "items": grocery_items,
            }
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=503, detail="Could not reach Supabase.") from exc
    except GroceryListError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
