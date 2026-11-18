from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
import httpx

from app.core.auth import require_matching_user
from app.core.config import settings
from app.schemas.grocery import GroceryListResponse
from pydantic import BaseModel

from app.services import supabase_rest as db
from app.services.grocery_list_service import GroceryListError
from app.services.plan_ops import rebuild_grocery_list

router = APIRouter(prefix="/meal-plans", tags=["grocery-lists"])


@router.post("/{meal_id}/grocery-list", response_model=GroceryListResponse)
async def generate_grocery_list(meal_id: str, user_id: str, _: str = Depends(require_matching_user)):
    """Build (or rebuild) the grocery list for a meal plan; ticked items stay ticked."""
    if not db.configured():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Supabase backend configuration is missing.",
        )
    try:
        async with httpx.AsyncClient(timeout=20) as client:
            plans = await db.select(client, "meal", {
                "select": "id", "id": f"eq.{meal_id}", "user_id": f"eq.{user_id}", "limit": "1",
            })
            if not plans:
                raise HTTPException(status_code=404, detail="Meal plan not found for this user.")
            return await rebuild_grocery_list(client, user_id, meal_id)
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=503, detail="Could not reach Supabase.") from exc
    except GroceryListError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except db.SupabaseError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


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
