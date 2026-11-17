from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
import httpx

from app.core.auth import require_matching_user
from app.core.config import settings
from app.schemas.grocery import GroceryListResponse
from pydantic import BaseModel

from app.services.grocery_list_service import GroceryListError, aggregate_ingredients, carry_over_purchased

router = APIRouter(prefix="/meal-plans", tags=["grocery-lists"])


@router.post("/{meal_id}/grocery-list", response_model=GroceryListResponse)
async def generate_grocery_list(meal_id: str, user_id: str, _: str = Depends(require_matching_user)):
    """Aggregate saved meal ingredients and replace one grocery list for the meal plan."""
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Supabase backend configuration is missing.",
        )

    base_url = settings.supabase_url.rstrip("/")
    headers = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Prefer": "return=representation",
    }

    try:
        async with httpx.AsyncClient(timeout=20) as client:
            plan_response = await client.get(
                f"{base_url}/rest/v1/meal",
                params={
                    "select": "id",
                    "id": f"eq.{meal_id}",
                    "user_id": f"eq.{user_id}",
                    "limit": "1",
                },
                headers=headers,
            )
            if plan_response.status_code != 200:
                raise HTTPException(status_code=502, detail="Could not load meal plan from Supabase.")
            if not plan_response.json():
                raise HTTPException(status_code=404, detail="Meal plan not found for this user.")

            ingredients_response = await client.get(
                f"{base_url}/rest/v1/meal_ingredients",
                params={
                    "select": "meal_id,food_code_org,food_name,amount,unit",
                    "meal_id": f"eq.{meal_id}",
                },
                headers=headers,
            )
            if ingredients_response.status_code != 200:
                raise HTTPException(status_code=502, detail="Could not load meal ingredients from Supabase.")

            # Quantities are per serving in the recipe data; scale to the household.
            profile_response = await client.get(
                f"{base_url}/rest/v1/onboarding_profiles",
                params={"select": "family_size", "user_id": f"eq.{user_id}", "limit": "1"},
                headers=headers,
            )
            profiles = profile_response.json() if profile_response.status_code == 200 else []
            household_size = (profiles[0].get("family_size") if profiles else None) or 1

            grocery_items = aggregate_ingredients(ingredients_response.json(), household_size=household_size)
            if not grocery_items:
                raise HTTPException(status_code=422, detail="No meal ingredients found for this meal plan.")

            existing_response = await client.get(
                f"{base_url}/rest/v1/grocery_lists",
                params={
                    "select": "id",
                    "meal_id": f"eq.{meal_id}",
                    "user_id": f"eq.{user_id}",
                    "order": "created_at.desc",
                    "limit": "1",
                },
                headers=headers,
            )
            if existing_response.status_code != 200:
                raise HTTPException(status_code=502, detail="Could not check existing grocery list.")

            existing = existing_response.json()
            if existing:
                grocery_list_id = existing[0]["id"]

                # Rebuilding keeps what the user already ticked off.
                previous = await client.get(
                    f"{base_url}/rest/v1/grocery_items",
                    params={"select": "ingredient_name", "grocery_list_id": f"eq.{grocery_list_id}", "is_purchased": "eq.true"},
                    headers=headers,
                )
                if previous.status_code == 200:
                    carry_over_purchased(
                        grocery_items,
                        {str(row.get("ingredient_name", "")).casefold() for row in previous.json()},
                    )

                delete_response = await client.delete(
                    f"{base_url}/rest/v1/grocery_items",
                    params={"grocery_list_id": f"eq.{grocery_list_id}"},
                    headers=headers,
                )
                if delete_response.status_code not in (200, 204):
                    raise HTTPException(
                        status_code=502,
                        detail=f"Could not clear existing grocery items: {delete_response.text}",
                    )

                update_list = await client.patch(
                    f"{base_url}/rest/v1/grocery_lists",
                    params={"id": f"eq.{grocery_list_id}"},
                    json={"status": "active"},
                    headers=headers,
                )
                if update_list.status_code not in (200, 204):
                    raise HTTPException(
                        status_code=502,
                        detail=f"Could not reactivate grocery list: {update_list.text}",
                    )
            else:
                create_list = await client.post(
                    f"{base_url}/rest/v1/grocery_lists",
                    json={"user_id": user_id, "meal_id": meal_id, "status": "active"},
                    headers=headers,
                )
                if create_list.status_code not in (200, 201):
                    raise HTTPException(status_code=502, detail=f"Could not create grocery list: {create_list.text}")
                created = create_list.json()
                if not created:
                    raise HTTPException(status_code=502, detail="Supabase did not return the created grocery list.")
                grocery_list_id = created[0]["id"]

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


class GroceryItemUpdate(BaseModel):
    is_purchased: bool


@router.patch("/{meal_id}/grocery-list/items/{item_id}")
async def update_grocery_item(
    meal_id: str,
    item_id: str,
    update: GroceryItemUpdate,
    user_id: str,
    _: str = Depends(require_matching_user),
):
    """Tick an item off (or back on). Also used for 'have it' on pantry items."""
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise HTTPException(status_code=503, detail="Supabase backend configuration is missing.")

    base_url = settings.supabase_url.rstrip("/")
    headers = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            item_response = await client.get(
                f"{base_url}/rest/v1/grocery_items",
                params={"select": "id,grocery_list_id", "id": f"eq.{item_id}", "limit": "1"},
                headers=headers,
            )
            items = item_response.json() if item_response.status_code == 200 else []
            if not items:
                raise HTTPException(status_code=404, detail="Grocery item not found.")

            # The item must sit on this user's list for this meal plan.
            owner_response = await client.get(
                f"{base_url}/rest/v1/grocery_lists",
                params={
                    "select": "id",
                    "id": f"eq.{items[0]['grocery_list_id']}",
                    "meal_id": f"eq.{meal_id}",
                    "user_id": f"eq.{user_id}",
                    "limit": "1",
                },
                headers=headers,
            )
            if owner_response.status_code != 200 or not owner_response.json():
                raise HTTPException(status_code=404, detail="Grocery item not found.")

            patch = await client.patch(
                f"{base_url}/rest/v1/grocery_items",
                params={"id": f"eq.{item_id}"},
                json={"is_purchased": update.is_purchased, "updated_at": datetime.now(timezone.utc).isoformat()},
                headers=headers,
            )
            if patch.status_code not in (200, 204):
                raise HTTPException(status_code=502, detail="Could not update the grocery item.")
            updated = patch.json() if patch.status_code == 200 else []
            return updated[0] if updated else {"id": item_id, "is_purchased": update.is_purchased}
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=503, detail="Could not reach Supabase.") from exc
