import json
from datetime import date, timedelta

import httpx
from groq import Groq

from app.core.config import settings
from app.schemas.meal_plan import GeneratedMealPlan, MealPlanningContext


def _expected_dates(start_date: date) -> list[str]:
    return [(start_date + timedelta(days=i)).isoformat() for i in range(7)]


async def _load_recipe_reference(mealPreference) -> list[dict[str, str | None]]:
    """Load the only allowed recipe names/codes for meal generation from Supabase."""
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise RuntimeError("Supabase backend configuration is missing.")

    base_url = settings.supabase_url.rstrip("/")
    headers = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
    }

    try:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.get(
                f"{base_url}/rest/v1/recipes",
                params={
                    "select": "recipe_name,source_recipe_code,category",
                    "status": "eq.active",
                    "preference": f"eq.{mealPreference}",
                    "category": "in.(breakfast,main_course)",
                    "order": "recipe_name.asc",
                },
                headers=headers,
            )
    except httpx.HTTPError as exc:
        raise RuntimeError("Could not reach Supabase to load recipe reference data.") from exc

    if response.status_code != 200:
        raise RuntimeError(
            f"Could not load recipe reference data from Supabase (status {response.status_code})."
        )

    rows = response.json()
    if not isinstance(rows, list) or not rows:
        raise RuntimeError("No active recipes are available in the Supabase recipe reference table.")

    recipes: list[dict[str, str | None]] = []
    seen_names: set[str] = set()
    for row in rows:
        if not isinstance(row, dict):
            continue
        recipe_name = row.get("recipe_name")
        if not isinstance(recipe_name, str) or not recipe_name.strip():
            continue
        recipe_name = recipe_name.strip()
        if recipe_name in seen_names:
            continue
        seen_names.add(recipe_name)
        source_recipe_code = row.get("source_recipe_code")
        category = row.get("category")
        recipes.append(
            {
                "recipe_name": recipe_name,
                "source_recipe_code": source_recipe_code if isinstance(source_recipe_code, str) else None,
                "category": category if isinstance(category, str) else None,
            }
        )

    if not recipes:
        raise RuntimeError("No usable recipes are available in the Supabase recipe reference table.")

    return recipes


def _build_system_prompt(
    start_date: date,
    recipe_reference: dict[str, list[str]],
) -> str:
    dates = _expected_dates(start_date)
    breakfast_recipes = recipe_reference.get("breakfast", [])
    main_course_recipes = recipe_reference.get("main_course", [])
    if not breakfast_recipes or not main_course_recipes:
        raise ValueError("The recipe reference must contain breakfast and main-course recipes.")
    example_structure = {
        meal_date: {
            "breakfast": [f'breakfast_reference_{idx}'],
            "lunch": [f'lunch_{idx}'],
            "dinner": [f'dinner_{idx}'],
        }
        for idx, meal_date in enumerate(dates)
    }
    return f"""
You are Annora's household meal-planning engine.
Create a practical 7-day meal plan for the household context provided.
Respect dietary preference, dietary goals, exclusions, family size, and budget.

RECIPE REFERENCE — THIS IS THE ONLY SOURCE OF RECIPES YOU MAY USE:

HARD RECIPE RULES — FOLLOW EXACTLY:
1. Every breakfast, lunch, and dinner MUST be selected from the RECIPE REFERENCE above.
2. Use the exact `recipe_name` value from the RECIPE REFERENCE. Do not invent, rename, paraphrase, combine, modify, or derive a recipe name.
3. `source_recipe_code` is reference metadata and must not be used as the meal name.
4. If a recipe does not exist in the RECIPE REFERENCE, you MUST NOT use it.
5. Dietary preferences, goals, exclusions, family size, and budget are filters over the available reference recipes; they do not permit creating a new recipe.
6. There should be variety in the meals across the 7 days. You may repeat a recipe, but do not repeat the same recipe for breakfast, lunch, or dinner on consecutive days.

OUTPUT RULES — FOLLOW EXACTLY:
1. Return ONLY one valid JSON object. No markdown, no ``` fences, no explanation.
2. The JSON object must contain EXACTLY these 7 top-level keys, in this order:
   {json.dumps(dates)}
3. Do NOT use a top-level "days" wrapper.
4. Each date must contain EXACTLY these 3 keys: "breakfast", "lunch", "dinner".
5. Each breakfast, lunch, and dinner MUST be an array containing EXACTLY ONE string.
6. Do not return two meal options. Choose one meal for each slot.
7. Do not add ingredients, quantities, nutrition, prep times, costs, grocery lists, or any other keys.
8. The first date MUST be {dates[0]} and the last date MUST be {dates[-1]}.
9. Every one of the 7 dates above MUST be present. Never stop after a partial plan.
10. Every meal-name string in the output MUST exactly match one `recipe_name` from the breakfast and main_course recipe references.

Use this exact structure, selecting exact recipe names from the reference:
{json.dumps(example_structure, indent=2)}
""".strip()


def _prompt(
    context: MealPlanningContext,
    start_date: date,
    recipe_reference: list[dict[str, str | None]],
) -> str:
    dates = _expected_dates(start_date)
    return json.dumps(
        {
            "required_dates_in_order": dates,
            "start_date": dates[0],
            "end_date": dates[-1],
            "family_size": context.family_size,
            "monthly_budget": context.monthly_budget,
            "dietary_preference": context.dietary_preference,
            "dietary_goals": context.dietary_goals,
            "dietary_exclusions": context.dietary_exclusions,
            "recipe_reference_rule": "Every meal must be selected exactly from the supplied recipe reference.",
            "available_recipe_names": recipe_reference,
        },
        ensure_ascii=False,
    )


def _extract_json(content: str) -> dict:
    cleaned = content.strip()
    if cleaned.startswith("```"):
        lines = cleaned.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        cleaned = "\n".join(lines).strip()
    parsed = json.loads(cleaned)
    if not isinstance(parsed, dict):
        raise ValueError("model response is not a JSON object")
    return parsed


def _normalize_plan(parsed: dict, recipe_names: set[str]) -> dict:
    """Normalize minor formatting variation while keeping one reference recipe per slot."""
    if isinstance(parsed.get("days"), dict):
        parsed = parsed["days"]

    normalized: dict = {}
    for meal_date, day in parsed.items():
        if not isinstance(day, dict):
            raise ValueError(f"day {meal_date} is not an object")

        normalized_day = {}
        for meal_type in ("breakfast", "lunch", "dinner"):
            value = day.get(meal_type)
            if isinstance(value, str):
                value = [value]
            if not isinstance(value, list) or len(value) != 1 or not isinstance(value[0], str):
                raise ValueError(f"{meal_date}.{meal_type} must contain exactly one meal-name string")

            meal_name = value[0].strip()
            if meal_name not in recipe_names:
                raise ValueError(
                    f"{meal_date}.{meal_type} contains recipe '{meal_name}' "
                    "which is not present in the Supabase recipe reference"
                )

            normalized_day[meal_type] = [meal_name]

        if set(day.keys()) != {"breakfast", "lunch", "dinner"}:
            raise ValueError(f"{meal_date} contains unexpected meal keys")
        normalized[meal_date] = normalized_day

    return normalized


def _validate_plan(
    parsed: dict,
    start_date: date,
    recipe_names: set[str],
) -> GeneratedMealPlan:
    normalized = _normalize_plan(parsed, recipe_names)
    plan = GeneratedMealPlan.model_validate({"days": normalized})
    expected_dates = [start_date + timedelta(days=i) for i in range(7)]
    actual_dates = plan.sorted_dates
    if actual_dates != expected_dates:
        raise ValueError(
            f"expected dates {[d.isoformat() for d in expected_dates]}, "
            f"got {[d.isoformat() for d in actual_dates]}"
        )
    if len(plan.days) != 7:
        raise ValueError(f"expected exactly 7 days, got {len(plan.days)}")
    return plan


async def generate_meal_plan(context: MealPlanningContext, start_date: date) -> GeneratedMealPlan:
    if not settings.grokapi or not settings.llm_model:
        raise RuntimeError("Groq provider is not configured.")

    dietary_preference = context.dietary_preference
    recipe_reference = await _load_recipe_reference(dietary_preference)
    breakfast_recipes = [r.get("recipe_name") for r in recipe_reference if r.get("category") == "breakfast"]
    main_course = [r.get("recipe_name") for r in recipe_reference if r.get("category") == "main_course"]
    recipes = {'breakfast': breakfast_recipes, 'main_course': main_course}

    client = Groq(
        api_key=settings.grokapi,
        timeout=settings.llm_timeout_seconds,
    )
    expected_dates = _expected_dates(start_date)

    try:
        completion = client.chat.completions.create(
            model=settings.llm_model,
            messages=[
                {"role": "system", "content": _build_system_prompt(start_date, recipes)},
                {"role": "user", "content": _prompt(context, start_date, recipes)},
            ],
            temperature=settings.llm_temperature,
            max_completion_tokens=4096,
            reasoning_effort="low",
        )
    except Exception as exc:
        raise RuntimeError(f"Groq request failed: {exc}") from exc

    content = completion.choices[0].message.content
    print(f"Groq response preview: {content}")
    if not content:
        raise RuntimeError("Groq returned an empty meal plan response.")

    try:
        parsed = _extract_json(content)
        recipe_names = {recipe["recipe_name"] for recipe in recipe_reference}
        return _validate_plan(parsed, start_date, recipe_names)
    except Exception as exc:
        preview = content[:1500].replace("\n", " ")
        raise RuntimeError(
            "Groq returned a meal plan with an invalid structure or a recipe outside the Supabase reference. "
            f"Expected exactly these 7 dates: {expected_dates}. "
            f"Each date must have exactly one breakfast, lunch, and dinner using only reference recipes. "
            f"Model response preview: {preview}"
        ) from exc
