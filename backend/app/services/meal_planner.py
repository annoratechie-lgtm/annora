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
        print("SUPABASE ERROR:", repr(exc))
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

Create a practical 7-day Indian household meal plan using ONLY recipes from the RECIPE REFERENCE.

CRITICAL:
- You may ONLY select source_recipe_code values present in RECIPE REFERENCE.
- Never output recipe_name.
- Never invent a source_recipe_code.
- Never modify a source_recipe_code.
- The final answer must contain ONLY source_recipe_code values for meals.

MEAL STRUCTURE:

BREAKFAST:
- Exactly 1 source_recipe_code.

LUNCH:
- If the selected recipe is a complete non-curry dish, return exactly 1 source_recipe_code.
- If the selected recipe is a curry/main-course curry/gravy, return exactly 2 source_recipe_codes:
  1. exactly 1 curry/main-course recipe
  2. exactly 1 staple recipe
- Never return more than 1 staple.

DINNER:
- If the selected recipe is a complete non-curry dish, return exactly 1 source_recipe_code.
- If the selected recipe is a curry/main-course curry/gravy, return exactly 2 source_recipe_codes:
  1. exactly 1 curry/main-course recipe
  2. exactly 1 staple recipe
- Never return more than 1 staple.

IMPORTANT:
A curry MUST NEVER be served alone.

Example:
If the curry code is C123 and the roti code is S001:
["C123", "S001"]

If the curry code is C123 and rice code is S002:
["C123", "S002"]

Do NOT output:
["C123"]

BREAKFAST:
["B001"]

This is WRONG:
["Paneer Butter Masala", "Roti"]

This is CORRECT:
["C123", "S001"]

REPETITION:
- Do not use the same recipe on consecutive days for breakfast.
- Do not use the same recipe on consecutive days for lunch and dinner.

DATES:
{", ".join(dates)}

Return exactly 7 records.

Each record must contain:
- meal_date
- breakfast
- lunch
- dinner

OUTPUT ONLY JSON matching the provided response schema.
Do not return recipe names.
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
#     content = {
#   "2026-09-01": {
#     "breakfast": "BFP153",
#     "lunch": [
#       "ASC142"
#     ],
#     "dinner": [
#       "BFP185",
#       "ASC113"
#     ]
#   },
#   "2026-09-02": {
#     "breakfast": "BFP114",
#     "lunch": [
#       "ASC096"
#     ],
#     "dinner": [
#       "ASC096"
#     ]
#   },
#   "2026-09-03": {
#     "breakfast": "BFP116",
#     "lunch": [
#       "BFP205",
#       "ASC113"
#     ],
#     "dinner": [
#       "ASC167",
#       "ASC113"
#     ]
#   },
#   "2026-09-04": {
#     "breakfast": "BFP548",
#     "lunch": [
#       "ASC052"
#     ],
#     "dinner": [
#       "ASC114"
#     ]
#   },
#   "2026-09-05": {
#     "breakfast": "BFP044",
#     "lunch": [
#       "ASC167",
#       "ASC113"
#     ],
#     "dinner": [
#       "ASC226",
#       "ASC113"
#     ]
#   },
#   "2026-09-06": {
#     "breakfast": "BFP043",
#     "lunch": [
#       "ASC114"
#     ],
#     "dinner": [
#       "ASC142"
#     ]
#   },
#   "2026-09-07": {
#     "breakfast": "BFP036",
#     "lunch": [
#       "ASC226",
#       "ASC113"
#     ],
#     "dinner": [
#       "BFP205",
#       "ASC113"
#     ]
#   }
# }
    # print(json.dumps(content, indent=2))
  
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