import json

from groq import Groq

from app.core.config import settings


class IngredientPlannerError(RuntimeError):
    pass


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


def _validate(parsed: dict, meal_ids: set[str]) -> dict:
    rows = parsed.get("meals")
    if not isinstance(rows, list) or len(rows) != len(meal_ids):
        raise ValueError("response must contain ingredients for every meal")

    seen: set[str] = set()
    normalized = []
    for meal in rows:
        if not isinstance(meal, dict):
            raise ValueError("each meal entry must be an object")
        meal_id = meal.get("meal_id")
        ingredients = meal.get("ingredients")
        if not isinstance(meal_id, str) or meal_id not in meal_ids or meal_id in seen:
            raise ValueError("invalid or duplicate meal_id")
        if not isinstance(ingredients, list) or not ingredients:
            raise ValueError(f"meal {meal_id} must contain ingredients")

        normalized_ingredients = []
        for ingredient in ingredients:
            if not isinstance(ingredient, dict):
                raise ValueError("ingredient must be an object")
            name = ingredient.get("ingredient_name")
            quantity = ingredient.get("quantity")
            unit = ingredient.get("unit")
            if not isinstance(name, str) or not name.strip():
                raise ValueError("ingredient_name must be a non-empty string")
            if not isinstance(quantity, (int, float)) or quantity <= 0:
                raise ValueError("quantity must be a positive number")
            if not isinstance(unit, str) or not unit.strip():
                raise ValueError("unit must be a non-empty string")
            normalized_ingredients.append({
                "ingredient_name": name.strip(),
                "quantity": quantity,
                "unit": unit.strip(),
            })

        seen.add(meal_id)
        normalized.append({"meal_id": meal_id, "ingredients": normalized_ingredients})

    if seen != meal_ids:
        raise ValueError("ingredient response is missing one or more meals")
    return {"meals": normalized}


async def generate_ingredients(meals: list[dict]) -> dict:
    if not settings.grokapi or not settings.llm_model:
        raise IngredientPlannerError("Groq provider is not configured.")

    meal_ids = {str(meal["id"]) for meal in meals}
    if not meal_ids:
        raise IngredientPlannerError("Meal plan contains no meals.")

    prompt = {
        "task": "Extract the ingredients required to cook each meal.",
        "rules": [
            "Return only valid JSON.",
            "Return exactly one entry for every supplied meal_id.",
            "Do not omit any meal_id.",
            "Use practical household quantities.",
            "Use a single clear unit such as g, kg, ml, l, piece, or tbsp.",
            "Do not include nutrition, prices, grocery categories, or cooking instructions.",
            "Do not combine ingredients across different meal_id values.",
        ],
        "meals": meals,
        "output_shape": {
            "meals": [
                {
                    "meal_id": "meal UUID",
                    "ingredients": [
                        {
                            "ingredient_name": "string",
                            "quantity": 100,
                            "unit": "g",
                        }
                    ],
                }
            ]
        },
    }

    client = Groq(api_key=settings.grokapi, timeout=settings.llm_timeout_seconds)
    try:
        completion = client.chat.completions.create(
            model=settings.llm_model,
            messages=[
                {"role": "system", "content": "You are Annora's ingredient extraction engine."},
                {"role": "user", "content": json.dumps(prompt, ensure_ascii=False)},
            ],
            temperature=0,
            max_tokens=4096,
            response_format={"type": "json_object"},
        )
    except Exception as exc:
        raise IngredientPlannerError(f"Groq ingredient request failed: {exc}") from exc

    content = completion.choices[0].message.content
    if not content:
        raise IngredientPlannerError("Groq returned an empty ingredient response.")

    try:
        return _validate(_extract_json(content), meal_ids)
    except Exception as exc:
        preview = content[:1500].replace("\n", " ")
        raise IngredientPlannerError(
            f"Groq returned invalid ingredient structure. Model response preview: {preview}"
        ) from exc
