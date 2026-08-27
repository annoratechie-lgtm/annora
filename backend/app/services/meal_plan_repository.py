from datetime import date

import httpx

from app.core.config import settings
# from app.schemas.meal_plan import GeneratedMealPlan


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


async def save_meal_plan(user_id: str, start_date: date, plan) -> str:
    headers = _headers()
    base_url = settings.supabase_url.rstrip("/")
    end_date = max(plan.keys())

    if len(plan) != 7:
        raise MealPlanRepositoryError(f"Expected 7-day plan, found {len(plan)}.")
    else:
        async with httpx.AsyncClient(timeout=20) as client:
            ## Fetching Active Meal Plan for the user
            active_meal_ids = await client.get(
                f"{base_url}/rest/v1/meal",
                params={
                    "select": "id,status",
                    "user_id": f"eq.{user_id}",
                    "status": "eq.active",
                },
                headers=headers,
            )
            _raise_supabase_error("Loading active meal plan",active_meal_ids)
            active_plans = active_meal_ids.json()

            # Deactivate existing active plan(s)
            if active_plans:
                active_plan_ids = [plan["id"] for plan in active_plans]
                for active_plan_id in active_plan_ids:
                    deactivate_response = await client.patch(
                        f"{base_url}/rest/v1/meal",
                        params={
                            "id": f"eq.{active_plan_id}"},
                        headers=headers,
                        json={"status": "inactive",},
                    )

                    _raise_supabase_error("Deactivating existing meal plan",deactivate_response)

            # Create the new active meal plan       
            plan_response = await client.post(
                f"{base_url}/rest/v1/meal",
                headers=headers,
                json={
                    "user_id": user_id,
                    "start_date": start_date.isoformat(),
                    "end_date": date.fromisoformat(end_date).isoformat(),
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
            for meal_date, meals in sorted(plan.items()):
                meal_rows.extend(
                    [
                        {
                            "meal_id": plan_id,
                            "meal_date": date.fromisoformat(meal_date).isoformat(),
                            "meal_type": "breakfast",
                            "name": meals.get('breakfast', '').split('-')[0] if '-' in meals.get('breakfast', '') else None,
                            "source_recipe_code": meals.get('breakfast', '').split('-')[1] if '-' in meals.get('breakfast', '') else None,
                            "description": None,
                            "status": "planned",
                            "prep_time_minutes": None,
                            "nutrition": {},
                        },
                        {
                            "meal_id": plan_id,
                            "meal_date": date.fromisoformat(meal_date).isoformat(),
                            "meal_type": "lunch",
                            "name": meals.get('lunch', [None])[0].split('-')[0] if '-' in meals.get('lunch', [None])[0] else None,
                            "source_recipe_code": meals.get('lunch', [None])[0].split('-')[1] if '-' in meals.get('lunch', [None])[0] else None,
                            "description": None,
                            "status": "planned",
                            "prep_time_minutes": None,
                            "nutrition": {},
                        },
                        {
                            "meal_id": plan_id,
                            "meal_date": date.fromisoformat(meal_date).isoformat(),
                            "meal_type": "dinner",
                            "name": meals.get('dinner', [None])[0].split('-')[0] if '-' in meals.get('dinner', [None])[0] else None,
                            "source_recipe_code": meals.get('dinner', [None])[0].split('-')[1] if '-' in meals.get('dinner', [None])[0] else None,
                            "description": None,
                            "status": "planned",
                            "prep_time_minutes": None,
                            "nutrition": {},
                        },
                    ]
                )

            meal_response = await client.post(
                f"{base_url}/rest/v1/meal_plan",
                headers=headers,
                json=meal_rows,
            )
            _raise_supabase_error("Saving generated meals", meal_response)

            saved_meals = meal_response.json()
            if len(saved_meals) != len(meal_rows):
                raise MealPlanRepositoryError("Supabase returned an unexpected meal count.")

    return plan_id
