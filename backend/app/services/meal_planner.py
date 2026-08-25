import json
from datetime import date, timedelta
import instructor
import httpx
from groq import Groq
from instructor.v2.core.errors import InstructorRetryException
from app.core.config import settings
from app.schemas.meal_plan import MealPlanningContext, mealPlanResponse


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
                    "category": "in.(breakfast,main_course,staple)",
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


def _build_system_prompt(start_date: date,) -> str:
    dates = _expected_dates(start_date)
    return f"""
You are Annora's household meal-planning engine.

Create a practical 7-day meal plan for the household context provided.

HARD RECIPE RULES — FOLLOW EXACTLY:

1. Every breakfast, lunch, and dinner MUST be selected from the input JSON RECIPE REFERENCE.
2. Use the exact `recipe_name` value from the RECIPE REFERENCE.
3. Do not invent, rename, paraphrase, combine, modify, or derive recipe names.
4. If a recipe does not exist in the RECIPE REFERENCE, you MUST NOT use it.
5. Dietary preferences, goals, exclusions, family size, and budget are filters over
   available recipes; they do not permit creating a new recipe.
6. Do not repeat the same recipe for breakfast, lunch, or dinner on consecutive days.
7. If a main course is a curry, add exactly one staple (Roti or Rice) to the meal.
8. If the main course is not a curry, do not add a staple.
9. Every recipe name must exactly match a `recipe_name` from the input reference.

OUTPUT RULES:

1. Return exactly 7 meal-plan records.
2. The dates MUST be exactly Format: YYYY-MM-DD exactly:
   {", ".join(dates)}
3. Each record must contain:
   - meal_date
   - breakfast
   - lunch
   - dinner
4. breakfast must contain exactly one recipe name.
5. lunch must contain the selected main course and, when required, exactly one staple.
6. dinner must contain the selected main course and, when required, exactly one staple.
7. Do not return any recipe that is not present in the recipe reference.
8. Do not return markdown or explanations.
""".strip()


async def generate_meal_plan(context: MealPlanningContext, start_date: date):
    if not settings.grokapi or not settings.llm_model:
        raise RuntimeError("Groq provider is not configured.")

    dietary_preference = context.dietary_preference
    recipe_reference = await _load_recipe_reference(dietary_preference)
    breakfast_recipes = [f'{r.get("recipe_name")}-{r.get("source_recipe_code")}' for r in recipe_reference if r.get("category") == "breakfast"]
    main_course = [f'{r.get("recipe_name")}-{r.get("source_recipe_code")}' for r in recipe_reference if r.get("category") == "main_course"]
    staple_recipes = [f'{r.get("recipe_name")}-{r.get("source_recipe_code")}'  for r in recipe_reference if r.get("category") == "staple"]
    recipes = {'breakfast': breakfast_recipes, 'main_course': main_course, 'staple': staple_recipes}

    client = Groq(api_key=settings.grokapi)
    client = instructor.from_groq(client, mode=instructor.Mode.JSON)
    

    try:
        response, completion = client.chat.completions.create_with_completion(
            model=settings.llm_model,
            messages=[
                {"role": "system", "content": _build_system_prompt(start_date)},
                {"role": "user", "content": json.dumps(recipes)},
            ],
            # temperature=settings.llm_temperature,
            response_model=mealPlanResponse,
            max_tokens=4096,
        )
    except Exception as exc:
        raise RuntimeError(f"Groq request failed: {exc}") from exc
    content = json.loads(response.model_dump_json(indent=2))
    content = format_meal_plan_output(content)

  
    if not content:
        raise RuntimeError("Groq returned an empty meal plan response.")

    return content

def format_meal_plan_output(recipes):
    formatted_output = {}
    for recipe in recipes['recipes']:
        formatted_output[recipe.get('meal_date')] = {
            "breakfast": recipe.get('breakfast'),
            "lunch": recipe.get('lunch'),
            "dinner": recipe.get('dinner')
        }
    return formatted_output