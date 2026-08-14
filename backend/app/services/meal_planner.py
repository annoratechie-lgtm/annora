import json
from datetime import date, timedelta

from groq import Groq

from app.core.config import settings
from app.schemas.meal_plan import GeneratedMealPlan, MealPlanningContext


def _expected_dates(start_date: date) -> list[str]:
    return [(start_date + timedelta(days=i)).isoformat() for i in range(7)]


def _build_system_prompt(start_date: date) -> str:
    dates = _expected_dates(start_date)
    return f"""
You are Annora's household meal-planning engine.
Create a practical 7-day meal plan for the household context provided.
Respect dietary preference, dietary goals, exclusions, family size, and budget.

OUTPUT RULES — FOLLOW EXACTLY:
1. Return ONLY one valid JSON object. No markdown, no ``` fences, no explanation.
2. The JSON object must contain EXACTLY these 7 top-level keys, in this order:
   {json.dumps(dates)}
3. Do NOT use a top-level "days" wrapper.
4. Each date must contain EXACTLY these 3 keys: "breakfast", "lunch", "dinner".
5. Each breakfast, lunch, and dinner MUST be an array containing EXACTLY ONE string.
6. Do not return two meal options. Choose one meal for each slot.
7. Do not add ingredients, quantities, nutrition, prep times, costs, grocery lists, snacks, or any other keys.
8. The first date MUST be {dates[0]} and the last date MUST be {dates[-1]}.
9. Every one of the 7 dates above MUST be present. Never stop after a partial plan.

Use this exact structure and replace the example meal names:
{{
  "{dates[0]}": {{
    "breakfast": ["meal name"],
    "lunch": ["meal name"],
    "dinner": ["meal name"]
  }},
  "{dates[1]}": {{
    "breakfast": ["meal name"],
    "lunch": ["meal name"],
    "dinner": ["meal name"]
  }},
  "...": {{
    "breakfast": ["meal name"],
    "lunch": ["meal name"],
    "dinner": ["meal name"]
  }},
  "{dates[-1]}": {{
    "breakfast": ["meal name"],
    "lunch": ["meal name"],
    "dinner": ["meal name"]
  }}
}}
""".strip()


def _prompt(context: MealPlanningContext, start_date: date) -> str:
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
    """Normalize minor formatting variation while keeping one meal per slot."""
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
            normalized_day[meal_type] = value

        if set(day.keys()) != {"breakfast", "lunch", "dinner"}:
            raise ValueError(f"{meal_date} contains unexpected meal keys")
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
    if len(plan.days) != 7:
        raise ValueError(f"expected exactly 7 days, got {len(plan.days)}")
    return plan


async def generate_meal_plan(context: MealPlanningContext, start_date: date) -> GeneratedMealPlan:
    if not settings.grokapi or not settings.llm_model:
        raise RuntimeError("Groq provider is not configured.")

    client = Groq(
        api_key=settings.grokapi,
        timeout=settings.llm_timeout_seconds,
    )
    expected_dates = _expected_dates(start_date)

    try:
        completion = client.chat.completions.create(
            model=settings.llm_model,
            messages=[
                {"role": "system", "content": _build_system_prompt(start_date)},
                {"role": "user", "content": _prompt(context, start_date)},
            ],
            temperature=settings.llm_temperature,
            max_tokens=2048,
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
        preview = content[:1500].replace("\n", " ")
        raise RuntimeError(
            "Groq returned a meal plan with an invalid structure. "
            f"Expected exactly these 7 dates: {expected_dates}. "
            f"Each date must have exactly one breakfast, lunch, and dinner. "
            f"Model response preview: {preview}"
        ) from exc
