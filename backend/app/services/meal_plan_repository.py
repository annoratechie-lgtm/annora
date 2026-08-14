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


def _raise_supabase_error(action: str, response: httpx.Response) -> None:
    if response.status_code >= 400:
        detail = response.text.strip()
        if len(detail) > 500:
            detail = detail[:500]
        raise MealPlanRepositoryError(
            f"{action} failed ({response.status_code}): {detail or 'Supabase returned an empty error.'}"
        )


async def save_meal_plan(user_id: str, start_date: date, plan: GeneratedMealPlan) -> str:
    headers = _headers()
    base_url = settings.supabase_url.rstrip("/")
    end_date = max(plan.days)

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
        _raise_supabase_error("Saving meal plan", plan_response)

        plan_rows = plan_response.json()
        if not plan_rows:
            raise MealPlanRepositoryError("Supabase did not return the created meal plan.")
        plan_id = plan_rows[0]["id"]

        meal_rows = []
        for meal_date, meals in sorted(plan.days.items()):
            meal_rows.extend(
                [
                    {
                        "meal_plan_id": plan_id,
                        "meal_date": meal_date.isoformat(),
                        "meal_type": "breakfast",
                        "name": meals.breakfast[0],
                        "description": None,
                        "status": "planned",
                        "prep_time_minutes": None,
                        "nutrition": {},
                    },
                    {
                        "meal_plan_id": plan_id,
                        "meal_date": meal_date.isoformat(),
                        "meal_type": "lunch",
                        "name": meals.lunch[0],
                        "description": None,
                        "status": "planned",
                        "prep_time_minutes": None,
                        "nutrition": {},
                    },
                    {
                        "meal_plan_id": plan_id,
                        "meal_date": meal_date.isoformat(),
                        "meal_type": "dinner",
                        "name": meals.dinner[0],
                        "description": None,
                        "status": "planned",
                        "prep_time_minutes": None,
                        "nutrition": {},
                    },
                ]
            )

        meal_response = await client.post(
            f"{base_url}/rest/v1/meals",
            headers=headers,
            json=meal_rows,
        )
        _raise_supabase_error("Saving generated meals", meal_response)

        saved_meals = meal_response.json()
        if len(saved_meals) != len(meal_rows):
            raise MealPlanRepositoryError("Supabase returned an unexpected meal count.")

    return plan_id
