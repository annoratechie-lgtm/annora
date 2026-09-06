from fastapi import APIRouter, HTTPException, status
import httpx

from app.core.config import settings
from app.schemas.ingredients import GeneratedIngredients
from app.services.ingredient_planner import IngredientPlannerError, generate_ingredients

router = APIRouter(prefix="/meal-plans", tags=["meal-plan-ingredients"])


@router.post("/{meal_id}/ingredients", response_model=GeneratedIngredients)
async def generate_meal_plan_ingredients(meal_id: str, user_id: str):
    """Generate recipe ingredients for a meal plan, replace saved rows, and return them."""
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Supabase backend configuration is missing.",
        )

    headers = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Prefer": "return=minimal",
    }
    base_url = settings.supabase_url.rstrip("/")

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
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail=f"Could not load meal plan from Supabase ({plan_response.status_code}).",
                )
            if not plan_response.json():
                raise HTTPException(status_code=404, detail="Meal plan not found for this user.")

            generated = await generate_ingredients(meal_id)

            for ingredient in generated:
                if str(ingredient["meal_plan_id"]) != str(meal_id):
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail="Ingredient response contains an unknown meal plan.",
                    )

            rows = [
                {
                    "meal_id": ingredient["meal_plan_id"],
                    "meal_type": ingredient["meal_type"],
                    "source_recipe_code": ingredient["source_recipe_code"],
                    "food_code_org": ingredient["food_code_org"],
                    "food_name": ingredient["food_name"],
                    "amount": ingredient["amount"],
                    "unit": ingredient["unit"],
                }
                for ingredient in generated
            ]

            delete_response = await client.delete(
                f"{base_url}/rest/v1/meal_ingredients",
                params={"meal_id": f"eq.{meal_id}"},
                headers=headers,
            )
            if delete_response.status_code not in (200, 204):
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail=f"Could not clear existing meal ingredients: {delete_response.text}",
                )

            save_response = await client.post(
                f"{base_url}/rest/v1/meal_ingredients",
                json=rows,
                headers=headers,
            )
            if save_response.status_code not in (200, 201, 204):
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail=f"Could not save meal ingredients: {save_response.text}",
                )

            return {
                "meal_plan_id": meal_id,
                "item_count": len(generated),
                "ingredients": generated,
            }
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=503, detail="Could not reach Supabase.") from exc
    except IngredientPlannerError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
