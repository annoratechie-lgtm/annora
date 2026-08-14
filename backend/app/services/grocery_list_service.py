from collections import defaultdict
from decimal import Decimal, ROUND_HALF_UP


class GroceryListError(RuntimeError):
    pass


def _key(name: str, unit: str) -> tuple[str, str]:
    return name.strip().casefold(), unit.strip().casefold()


def aggregate_ingredients(ingredients: list[dict]) -> list[dict]:
    """Aggregate identical ingredient/unit pairs without using an LLM."""
    totals: dict[tuple[str, str], dict] = {}

    for row in ingredients:
        name = str(row["ingredient_name"]).strip()
        unit = str(row["unit"]).strip()
        quantity = Decimal(str(row["quantity"]))
        if not name or not unit or quantity <= 0:
            raise GroceryListError("Invalid ingredient quantity, name, or unit.")

        key = _key(name, unit)
        if key not in totals:
            totals[key] = {
                "ingredient_name": name,
                "required_quantity": Decimal("0"),
                "unit": unit,
            }
        totals[key]["required_quantity"] += quantity

    result = []
    for item in sorted(totals.values(), key=lambda x: x["ingredient_name"].casefold()):
        quantity = item["required_quantity"].quantize(Decimal("0.001"), rounding=ROUND_HALF_UP)
        result.append({
            "ingredient_name": item["ingredient_name"],
            "required_quantity": float(quantity),
            "unit": item["unit"],
            "purchase_quantity": float(quantity),
            "category": None,
            "is_purchased": False,
            "is_urgent": False,
        })
    return result
