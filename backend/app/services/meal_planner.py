import json
from datetime import date, timedelta

from groq import Groq

from app.core.config import settings
from app.schemas.meal_plan import GeneratedMealPlan, MealPlanningContext


SYSTEM_PROMPT = """
You are Annora's household meal-planning engine.
Create a practical 7-day meal plan for the household context provided.
Respect dietary preference, dietary goals, exclusions, family size, and budget.

Return ONLY valid JSON. Do not return markdown, explanations, ingredients, quantities,
nutrition, prep times, grocery lists, or costs.

The JSON must contain exactly 7 consecutive date keys, starting on the requested
start date. Each date must contain exactly three keys: breakfast, lunch, dinner.
Each meal value must be an array containing exactly one meal-name string.

Return this exact shape:
{
  "YYYY-MM-DD": {
    "breakfast": ["meal name"],
    "lunch": ["meal name"],
    "dinner": ["meal name"]
  }
}
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


def _normalize_plan(parsed: dict) -> dict:
    """Accept the two common JSON-object forms returned by Llama.

    Preferred form is the date map directly. If the model wraps that map in a
    top-level `days` object, unwrap it. Also normalize a single meal string to
    the required one-item array; this keeps the API contract strict while being
    tolerant of minor LLM formatting variation.
    """
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
            if not isinstance(value, list) or not value or not all(isinstance(x, str) for x in value):
                raise ValueError(f"{meal_date}.{meal_type} must be an array of meal names")
            normalized_day[meal_type] = value

        normalized[meal_date] = normalized_day

    return normalized


def _validate_plan(parsed: dict, start_date: date) -> GeneratedMealPlan:
    normalized = _normalize_plan(parsed)
    plan = GeneratedMealPlan.model_validate({"days": normalized})
    expected_dates = [start_date + timedelta(days=i) for i in range(7)]
    actual_dates = plan.sorted_dates
    if actual_dates != expected_dates:
        raise ValueError(
            f"expected dates {[d.isoformat() for d in expected_dates]}, "
            f"got {[d.isoformat() for d in actual_dates]}"
        )
    return plan


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

    content = completion.choices[0].message.content
    if not content:
        raise RuntimeError("Groq returned an empty meal plan response.")

    try:
        parsed = _extract_json(content)
        return _validate_plan(parsed, start_date)
    except Exception as exc:
        preview = content[:1000].replace("\n", " ")
        raise RuntimeError(
            "Groq returned a meal plan with an invalid structure. "
            f"Expected 7 date keys with breakfast/lunch/dinner arrays. "
            f"Model response preview: {preview}"
        ) from exc
