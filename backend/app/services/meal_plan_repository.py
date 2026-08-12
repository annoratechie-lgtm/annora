from datetime import date

import httpx

from app.core.config import settings
from app.schemas.meal_plan import GeneratedMealPlan


class MealPlanRepositoryError(RuntimeError):
    pass


def _headers() -> dict[str, str]:
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise MealPlanRepositoryError("Supabase backend configuration is missing.")
    return {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


async def save_meal_plan(user_id: str, start_date: date, plan: GeneratedMealPlan) -> tuple[str, str]:
    headers = _headers()
    base_url = settings.supabase_url.rstrip("/")
    end_date = plan.days[-1].date

    async with httpx.AsyncClient(timeout=20) as client:
        plan_response = await client.post(
            f"{base_url}/rest/v1/meal_plans",
            headers=headers,
            json={
                "user_id": user_id,
                "start_date": start_date.isoformat(),
                "end_date": end_date.isoformat(),
                "status": "active",
                "generation_source": "llm",
            },
        )
        if plan_response.status_code >= 400:
            raise MealPlanRepositoryError("Could not save meal plan.")

        plan_rows = plan_response.json()
        if not plan_rows:
            raise MealPlanRepositoryError("Supabase did not return the created meal plan.")
        plan_id = plan_rows[0]["id"]

        meal_rows = []
        for day in plan.days:
            for meal in day.meals:
                meal_rows.append({
                    "meal_plan_id": plan_id,
                    "meal_date": day.date.isoformat(),
                    "meal_type": meal.type,
                    "name": meal.name,
                    "description": meal.description,
                    "status": "planned",
                    "prep_time_minutes": meal.prep_time_minutes,
                    "nutrition": meal.nutrition,
                })

        meal_response = await client.post(
            f"{base_url}/rest/v1/meals",
            headers=headers,
            json=meal_rows,
        )
        if meal_response.status_code >= 400:
            raise MealPlanRepositoryError("Could not save generated meals.")

        saved_meals = meal_response.json()
        if len(saved_meals) != len(meal_rows):
            raise MealPlanRepositoryError("Supabase returned an unexpected meal count.")

        meal_id_by_key = {
            (row["meal_date"], row["meal_type"]): row["id"] for row in saved_meals
        }

        ingredient_rows = []
        for day in plan.days:
            for meal in day.meals:
                meal_id = meal_id_by_key[(day.date.isoformat(), meal.type)]
                for ingredient in meal.ingredients:
                    ingredient_rows.append({
                        "meal_id": meal_id,
                        "ingredient_name": ingredient.name,
                        "quantity": ingredient.quantity,
                        "unit": ingredient.unit,
                    })

        if ingredient_rows:
            ingredient_response = await client.post(
                f"{base_url}/rest/v1/meal_ingredients",
                headers=headers,
                json=ingredient_rows,
            )
            if ingredient_response.status_code >= 400:
                raise MealPlanRepositoryError("Could not save meal ingredients.")

        grocery_response = await client.post(
            f"{base_url}/rest/v1/grocery_lists",
            headers=headers,
            json={
                "user_id": user_id,
                "meal_plan_id": plan_id,
                "status": "active",
            },
        )
        if grocery_response.status_code >= 400:
            raise MealPlanRepositoryError("Could not create grocery list.")

        grocery_rows = grocery_response.json()
        if not grocery_rows:
            raise MealPlanRepositoryError("Supabase did not return the grocery list.")
        grocery_list_id = grocery_rows[0]["id"]

        aggregated: dict[tuple[str, str], float] = {}
        for day in plan.days:
            for meal in day.meals:
                for ingredient in meal.ingredients:
                    key = (ingredient.name.strip().lower(), ingredient.unit.strip().lower())
                    aggregated[key] = aggregated.get(key, 0) + ingredient.quantity

        grocery_items = [
            {
                "grocery_list_id": grocery_list_id,
                "ingredient_name": name,
                "required_quantity": quantity,
                "unit": unit,
                "purchase_quantity": quantity,
                "is_purchased": False,
                "is_urgent": False,
            }
            for (name, unit), quantity in aggregated.items()
        ]

        if grocery_items:
            items_response = await client.post(
                f"{base_url}/rest/v1/grocery_items",
                headers=headers,
                json=grocery_items,
            )
            if items_response.status_code >= 400:
                raise MealPlanRepositoryError("Could not save grocery items.")

    return plan_id, grocery_list_id
