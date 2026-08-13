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
Return only the requested JSON structure.
""".strip()


def _schema() -> dict:
    return {
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "days": {
                "type": "array",
                "minItems": 7,
                "maxItems": 7,
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "properties": {
                        "date": {"type": "string", "format": "date"},
                        "meals": {
                            "type": "array",
                            "minItems": 1,
                            "items": {
                                "type": "object",
                                "additionalProperties": False,
                                "properties": {
                                    "type": {"type": "string", "enum": ["breakfast", "lunch", "dinner", "snack"]},
                                    "name": {"type": "string"},
                                    "description": {"type": ["string", "null"]},
                                    "prep_time_minutes": {"type": ["integer", "null"]},
                                    "nutrition": {"type": "object"},
                                    "ingredients": {
                                        "type": "array",
                                        "items": {
                                            "type": "object",
                                            "additionalProperties": False,
                                            "properties": {
                                                "name": {"type": "string"},
                                                "quantity": {"type": "number", "exclusiveMinimum": 0},
                                                "unit": {"type": "string"},
                                            },
                                            "required": ["name", "quantity", "unit"],
                                        },
                                    },
                                },
                                "required": ["type", "name", "description", "prep_time_minutes", "nutrition", "ingredients"],
                            },
                        },
                    },
                    "required": ["date", "meals"],
                },
            }
        },
        "required": ["days"],
    }


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
        raise RuntimeError("Groq returned an invalid structured meal plan.") from exc

    plan = GeneratedMealPlan.model_validate(parsed)
    expected_dates = [start_date + timedelta(days=i) for i in range(7)]
    actual_dates = [day.date for day in plan.days]
    if actual_dates != expected_dates:
        raise RuntimeError("LLM returned dates outside the requested 7-day window.")

    return plan
