import json
import logging
import random
import re
from datetime import date, timedelta
import instructor
import httpx
from groq import Groq
from instructor.v2.core.errors import InstructorRetryException
from app.core.config import settings
from app.schemas.meal_plan import MealPlanningContext, mealPlanResponse
from app.services.recipe_filters import (
    excluded_recipe_codes,
    exclusion_rules,
    goals_guidance,
    match_terms,
    recipe_preferences_for,
)


def _expected_dates(start_date: date) -> list[str]:
    return [(start_date + timedelta(days=i)).isoformat() for i in range(7)]


async def _load_recipe_reference(preferences: list[str]) -> list[dict[str, str | None]]:
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
                    "preference": f"in.({','.join(preferences)})",
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


async def _load_excluded_codes(exclusions: list[str]) -> set[str]:
    """Recipe codes containing any ingredient the household wants to avoid."""
    rules = exclusion_rules(exclusions)
    terms = match_terms(rules)
    if not terms:
        return set()
    headers = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
    }
    or_filter = "(" + ",".join(f"food_name.ilike.*{t}*" for t in terms) + ")"
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            response = await client.get(
                f"{settings.supabase_url.rstrip('/')}/rest/v1/recipe_ingredient",
                params={"select": "source_recipe_code,food_name", "or": or_filter},
                headers=headers,
            )
    except httpx.HTTPError as exc:
        raise RuntimeError("Could not reach Supabase to apply foods to avoid.") from exc
    if response.status_code != 200:
        raise RuntimeError(f"Could not apply foods to avoid (status {response.status_code}).")
    return excluded_recipe_codes(response.json(), rules)


def _build_system_prompt(start_date: date, context: MealPlanningContext | None = None) -> str:
    dates = _expected_dates(start_date)
    household = goals_guidance(context.dietary_goals) if context else ""
    notes = [n.strip()[:200] for n in (context.notes if context else []) if n and n.strip()][:30]
    if notes:
        # From Ask Annora memory / the user's request. Preferences only: recipe
        # codes are still restricted to the reference and sanitised afterwards.
        household = "\n".join(filter(None, [household, *[f"- User note: {n}" for n in notes]]))
    household_block = f"\nHOUSEHOLD PREFERENCES:\n{household}\n" if household else ""
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

{household_block}
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

    recipe_reference = await _load_recipe_reference(recipe_preferences_for(context.dietary_preference))

    # Foods to avoid are a hard filter: excluded recipes never reach the LLM,
    # and sanitize_meal_plan() drops any code outside this reference.
    excluded = await _load_excluded_codes(context.dietary_exclusions)
    if excluded:
        recipe_reference = [
            r for r in recipe_reference
            if (r.get("source_recipe_code") or "").strip().upper() not in excluded
        ]
    if not any(r.get("category") == "breakfast" for r in recipe_reference) or not any(
        r.get("category") == "main_course" for r in recipe_reference
    ):
        raise RuntimeError(
            "No recipes are left after applying your foods to avoid. Remove some items in Profile and try again."
        )
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
                {"role": "system", "content": _build_system_prompt(start_date, context)},
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

    return sanitize_meal_plan(content, recipe_reference)


logger = logging.getLogger(__name__)

# Recipe codes look like ASC113, BFP153, OSR107.
_RECIPE_CODE_RE = re.compile(r"[A-Z]{2,}\d+")


def _extract_codes(value, allowed: set[str]) -> list[str]:
    """Pull valid recipe codes out of whatever the LLM returned for one item.

    The model is shown recipes as "Name-CODE" and sometimes echoes that whole
    string ("Plain Pulao-ASC114"), or packs two codes into one string
    ("ASC226, ASC113"). Keep only codes that exist in the recipe reference.
    """
    if not isinstance(value, str):
        return []
    text = value.strip().upper()
    if text in allowed:
        return [text]
    return [code for code in _RECIPE_CODE_RE.findall(text) if code in allowed]


def _pick_fallback(candidates: list[str], avoid: set[str]) -> str | None:
    pool = [c for c in candidates if c not in avoid] or candidates
    return random.choice(pool) if pool else None


def sanitize_meal_plan(plan: dict, recipe_reference: list[dict]) -> dict:
    """Normalise LLM output so every saved meal uses a real recipe code.

    Invalid or invented codes are dropped; a meal left empty is filled from the
    same category (breakfast, or a main course + staple pair) so a plan never
    ends up with unnamed "NA" meals.
    """
    by_category: dict[str, list[str]] = {}
    for recipe in recipe_reference:
        code = recipe.get("source_recipe_code")
        if isinstance(code, str) and code.strip():
            by_category.setdefault(recipe.get("category") or "", []).append(code.strip().upper())
    allowed = {code for codes in by_category.values() for code in codes}

    previous: dict[str, set[str]] = {"breakfast": set(), "lunch": set(), "dinner": set()}
    for meal_date in sorted(plan):
        meals = plan[meal_date] or {}

        breakfast_codes = _extract_codes(meals.get("breakfast"), allowed)
        breakfast = breakfast_codes[0] if breakfast_codes else None
        if breakfast is None:
            breakfast = _pick_fallback(by_category.get("breakfast", []), previous["breakfast"])
            logger.warning("Meal plan %s: replaced invalid breakfast %r with %s",
                           meal_date, meals.get("breakfast"), breakfast)
        meals["breakfast"] = breakfast
        previous["breakfast"] = {breakfast} if breakfast else set()

        for meal_type in ("lunch", "dinner"):
            raw = meals.get(meal_type) or []
            if isinstance(raw, str):
                raw = [raw]
            codes: list[str] = []
            for item in raw:
                for code in _extract_codes(item, allowed):
                    if code not in codes:
                        codes.append(code)
            if not codes:
                main = _pick_fallback(by_category.get("main_course", []), previous[meal_type])
                staple = _pick_fallback(by_category.get("staple", []), set())
                codes = [c for c in (main, staple) if c]
                logger.warning("Meal plan %s: replaced invalid %s %r with %s",
                               meal_date, meal_type, raw, codes)
            meals[meal_type] = codes
            previous[meal_type] = set(codes)

        plan[meal_date] = meals
    return plan

def format_meal_plan_output(recipes):
    formatted_output = {}
    for recipe in recipes['recipes']:
        formatted_output[recipe.get('meal_date')] = {
            "breakfast": recipe.get('breakfast'),
            "lunch": recipe.get('lunch'),
            "dinner": recipe.get('dinner')
        }
    return formatted_output