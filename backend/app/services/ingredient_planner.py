import httpx

from app.core.config import settings


class IngredientPlannerError(RuntimeError):
    pass


async def generate_ingredients(meal_plan_id: str) -> list[dict]:
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise IngredientPlannerError("Supabase backend configuration is missing.")

    headers = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    base_url = settings.supabase_url.rstrip("/")

    try:
        async with httpx.AsyncClient(timeout=20) as client:
            response = await client.post(
                f"{base_url}/rest/v1/rpc/get_meal_plan_ingredients",
                json={"p_meal_plan_id": meal_plan_id},
                headers=headers,
            )
    except httpx.HTTPError as exc:
        raise IngredientPlannerError(
            f"Could not reach Supabase to load ingredients for meal plan {meal_plan_id}."
        ) from exc

    if response.status_code != 200:
        raise IngredientPlannerError(
            f"Supabase ingredient RPC failed ({response.status_code}): {response.text}"
        )

    try:
        content = response.json()
    except ValueError as exc:
        raise IngredientPlannerError("Supabase returned an invalid ingredient response.") from exc

    if not isinstance(content, list):
        raise IngredientPlannerError("Supabase ingredient RPC returned an unexpected response shape.")

    if not content:
        raise IngredientPlannerError("No recipe ingredients found for this meal plan.")

    required_fields = {
        "meal_plan_id",
        "meal_date",
        "meal_type",
        "source_recipe_code",
        "food_code_org",
        "food_name",
        "amount",
        "unit",
    }
    normalized: list[dict] = []
    for row in content:
        if not isinstance(row, dict) or not required_fields.issubset(row):
            raise IngredientPlannerError("Supabase ingredient RPC returned an invalid ingredient row.")
        normalized.append({field: row[field] for field in required_fields})

    return normalized
