import json
from datetime import date, timedelta

from groq import Groq

from app.core.config import settings
from app.schemas.meal_plan import GeneratedMealPlan, MealPlanningContext


SYSTEM_PROMPT = """
You are Annora's household meal-planning engine.
Create a practical 7-day meal plan for the household context provided.
Respect dietary preference, dietary goals, exclusions, family size, and budget.
Use realistic household-friendly meals and avoid excluded ingredients.
Return exactly 7 consecutive dates beginning on the requested start date.
Each day should normally contain breakfast, lunch, and dinner.
Every meal must include the ingredients and quantities needed to prepare it.
Do not invent medical claims or present nutrition information as medical advice.

OUTPUT FORMAT IS STRICT:
Return ONLY JSON with exactly this top-level shape: {"days": [...]}
The "days" value must be an array of exactly 7 day objects.
Never use dates as JSON keys. Never return a top-level cost, grocery, budget, or summary field.
Each day must contain "date" and "meals".
Each meal must contain "type", "name", "description", "prep_time_minutes", "nutrition", and "ingredients".
The meal type must be breakfast, lunch, dinner, or snack.
Each ingredient must contain "name", positive numeric "quantity", and "unit".
"ingredients" must be an array, not a string or object.
"nutrition" must be an object.
"description" may be null.
"prep_time_minutes" may be null.

Example:
{"days":[{"date":"YYYY-MM-DD","meals":[{"type":"breakfast","name":"Meal name","description":"Short description","prep_time_minutes":15,"nutrition":{},"ingredients":[{"name":"ingredient","quantity":1,"unit":"cup"}]}]}]}
""".strip()


def _prompt(context: MealPlanningContext, start_date: date) -> str:
    return json.dumps(
        {
            "start_date": start_date.isoformat(),
            "end_date": (start_date + timedelta(days=6)).isoformat(),
            "family_size": context.family_size,
            "monthly_budget": context.monthly_budget,
            "dietary_preference": context.dietary_preference,
            "dietary_goals": context.dietary_goals,
            "dietary_exclusions": context.dietary_exclusions,
        },
        ensure_ascii=False,
    )


def _extract_json(content: str) -> dict:
    """Parse JSON returned by the model, tolerating accidental markdown fences."""
    cleaned = content.strip()
    if cleaned.startswith("```"):
        lines = cleaned.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        cleaned = "\n".join(lines).strip()
    return json.loads(cleaned)


async def generate_meal_plan(context: MealPlanningContext, start_date: date) -> GeneratedMealPlan:
    if not settings.grokapi or not settings.llm_model:
        raise RuntimeError("Groq provider is not configured.")

    client = Groq(
        api_key=settings.grokapi,
        timeout=settings.llm_timeout_seconds,
    )

    try:
        completion = client.chat.completions.create(
            model=settings.llm_model,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": _prompt(context, start_date)},
            ],
            temperature=settings.llm_temperature,
            response_format={"type": "json_object"},
        )
    except Exception as exc:
        raise RuntimeError(f"Groq request failed: {exc}") from exc

    try:
        content = completion.choices[0].message.content
        if not content:
            raise ValueError("empty model response")
        parsed = _extract_json(content)
    except (IndexError, TypeError, ValueError, json.JSONDecodeError) as exc:
        raise RuntimeError("Groq returned invalid JSON.") from exc

    try:
        plan = GeneratedMealPlan.model_validate(parsed)
    except Exception as exc:
        raise RuntimeError("Groq returned a meal plan with an invalid structure. Expected a top-level 'days' array with 7 days and structured meals/ingredients.") from exc

    expected_dates = [start_date + timedelta(days=i) for i in range(7)]
    actual_dates = [day.date for day in plan.days]
    if actual_dates != expected_dates:
        raise RuntimeError("LLM returned dates outside the requested 7-day window.")

    return plan
