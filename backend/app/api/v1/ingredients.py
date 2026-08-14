from fastapi import APIRouter, HTTPException, status
import httpx

from app.core.config import settings
from app.schemas.ingredients import GeneratedIngredients
from app.services.ingredient_planner import IngredientPlannerError, generate_ingredients

router = APIRouter(prefix="/meal-plans", tags=["meal-plan-ingredients"])


@router.post("/{meal_plan_id}/ingredients", response_model=GeneratedIngredients)
async def generate_meal_plan_ingredients(meal_plan_id: str, user_id: str):
    """Generate ingredients with Llama and persist them to meal_ingredients."""
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Supabase backend configuration is missing.",
        )

    headers = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    base_url = settings.supabase_url.rstrip("/")

    try:
        async with httpx.AsyncClient(timeout=20) as client:
            plan_response = await client.get(
                f"{base_url}/rest/v1/meal_plans",
                params={"select": "id", "id": f"eq.{meal_plan_id}", "user_id": f"eq.{user_id}", "limit": "1"},
                headers=headers,
            )
            if plan_response.status_code != 200:
                raise HTTPException(status_code=502, detail="Could not load meal plan from Supabase.")
            if not plan_response.json():
                raise HTTPException(status_code=404, detail="Meal plan not found for this user.")

            meals_response = await client.get(
                f"{base_url}/rest/v1/meals",
                params={
                    "select": "id,meal_date,meal_type,name,description",
                    "meal_plan_id": f"eq.{meal_plan_id}",
                    "order": "meal_date.asc,meal_type.asc",
                },
                headers=headers,
            )
            if meals_response.status_code != 200:
                raise HTTPException(status_code=502, detail="Could not load meals from Supabase.")

            meals = meals_response.json()
            if len(meals) != 21:
                raise HTTPException(
                    status_code=422,
                    detail=f"Expected 21 meals for a 7-day plan, found {len(meals)}.",
                )

            generated = await generate_ingredients(meals)

            meal_ids = {str(meal["id"]) for meal in meals}
            rows = []
            for meal_entry in generated["meals"]:
                if meal_entry["meal_id"] not in meal_ids:
                    raise HTTPException(status_code=422, detail="Ingredient response contains an unknown meal_id.")
                for ingredient in meal_entry["ingredients"]:
                    rows.append({
                        "meal_id": meal_entry["meal_id"],
                        "ingredient_name": ingredient["ingredient_name"],
                        "quantity": ingredient["quantity"],
                        "unit": ingredient["unit"],
                    })

            # Make the endpoint repeatable: replace existing ingredients for these meals.
            delete_response = await client.delete(
                f"{base_url}/rest/v1/meal_ingredients",
                params={"meal_id": "in.(" + ",".join(meal_ids) + ")"},
                headers=headers,
            )
            if delete_response.status_code not in (200, 204):
                raise HTTPException(
                    status_code=502,
                    detail=f"Could not clear existing meal ingredients: {delete_response.text}",
                )

            save_response = await client.post(
                f"{base_url}/rest/v1/meal_ingredients",
                json=rows,
                headers=headers,
            )
            if save_response.status_code not in (200, 201, 204):
                raise HTTPException(
                    status_code=502,
                    detail=f"Could not save meal ingredients: {save_response.text}",
                )

            return generated
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=503, detail="Could not reach Supabase.") from exc
    except IngredientPlannerError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
