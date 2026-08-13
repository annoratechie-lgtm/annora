import json
from datetime import date, timedelta

from groq import Groq

from app.core.config import settings
from app.schemas.meal_plan import GeneratedMealPlan, MealPlanningContext


SYSTEM_PROMPT = """
You are Annora's household meal-planning engine.
Create a practical 7-day meal plan for the household context provided.
Respect dietary preference, dietary goals, exclusions, family size, and budget.

Return ONLY JSON. Do not return markdown, explanations, ingredients, quantities,
nutrition, prep times, grocery lists, or costs.

The JSON must have exactly 7 date keys. Each date must contain exactly these keys:
breakfast, lunch, dinner.
Each value must be an array of meal-name strings.
Dates must be consecutive, starting on the requested start date.

Required shape:
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
    return json.loads(cleaned)


def _validate_plan(parsed: dict, start_date: date) -> GeneratedMealPlan:
    plan = GeneratedMealPlan.model_validate({"days": parsed})
    expected_dates = [start_date + timedelta(days=i) for i in range(7)]
    actual_dates = plan.sorted_dates
    if actual_dates != expected_dates:
        raise ValueError("LLM returned dates outside the requested 7-day window.")
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

    try:
        content = completion.choices[0].message.content
        if not content:
            raise ValueError("empty model response")
        parsed = _extract_json(content)
        return _validate_plan(parsed, start_date)
    except Exception as exc:
        raise RuntimeError(
            "Groq returned a meal plan with an invalid structure. Expected 7 date keys, each with breakfast, lunch, and dinner arrays."
        ) from exc
