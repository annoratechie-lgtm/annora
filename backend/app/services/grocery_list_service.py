"""Turns a meal plan's recipe ingredients into a shopper-friendly grocery list.

Steps: drop water, clean dataset names ("Onion, big (Allium cepa)" -> "Onion"),
convert units to grams / millilitres / counts and merge them, scale by the
household size, sort into aisles, and round up to sizes shops sell.
Spoon measures of dry things (spices, salt, dal) become grams; only liquids stay
in ml. Deep-frying oil is reused, so it is one separate line, not a running sum.
Pure functions only; the API layer does the Supabase I/O.
"""

import math
import re
from collections import defaultdict


class GroceryListError(RuntimeError):
    pass


# Dataset (INDB) name -> what a shopper calls it.
DISPLAY_NAMES = {
    "oil, sunflower": "Sunflower oil",
    "oil, olive": "Olive oil",
    "oil, mustard": "Mustard oil",
    "flour, gram": "Besan (gram flour)",
    "wheat flour, atta": "Atta",
    "wheat flour, refined": "Maida",
    "wheat, semolina": "Suji (semolina)",
    "wheat, vermicelli, roasted": "Vermicelli",
    "rice, parboiled, milled": "Rice",
    "chillies, green - all varieties": "Green chillies",
    "chillies, red": "Dried red chillies",
    "beans, chick peas, kabuli, whole, dried, raw": "Kabuli chana",
    "yogurt, whole milk, plain": "Curd",
    "milk, whole, cow": "Milk",
    "ghee, butter": "Ghee",
    "butter, unsalted": "Butter",
    "butter, salted": "Butter",
    "black gram, dal": "Urad dal",
    "red gram, dal": "Toor dal",
    "bengal gram, dal": "Chana dal",
    "green gram, dal": "Moong dal",
    "ladies finger": "Bhindi",
    "beet root": "Beetroot",
    "maize, dry": "Makki atta",
    "ajwain seed whole organic spices": "Ajwain",
    "coconut, kernel, fresh": "Coconut",
    "coconut, kernal, dry": "Dry coconut",
    "spring onions, bulbs and tops, raw": "Spring onions",
    "soy sauce, light and dark varieties": "Soy sauce",
    "lemons, flesh only, raw, weighed with peel and pips": "Lemon",
    "pasta, white, dried, raw": "Pasta",
    "tamarind, pulp": "Tamarind",
    "button mushroom, fresh": "Mushrooms",
    "radish, elongate, white skin": "Radish",
    "turnip, flesh only, raw": "Turnip",
    "cardamom, black": "Black cardamom",
    "pepper, black": "Black pepper",
    "pepper, white": "White pepper",
    "bay leaf, dried": "Bay leaves",
    "oregano, dried, ground": "Oregano",
    "tomato sauce, homemade": "Tomato sauce",
    "sugar, white": "Sugar",
    "sugar, icing": "Icing sugar",
    "brinjal - all varieties": "Brinjal",
    "onion, big": "Onion",
    "tomato, ripe, hybrid": "Tomato",
    "potato, brown skin, big": "Potato",
    "garlic, small clove": "Garlic",
    "ginger, fresh": "Ginger",
    "ginger, ground": "Dry ginger powder",
    "carrot, orange": "Carrot",
    "peas, fresh": "Green peas",
    "french beans, hybrid": "French beans",
    "capsicum, green": "Capsicum",
    "cabbage, green": "Cabbage",
    "cinnamon, ground": "Cinnamon",
    "beansprouts, mung, boiled in unsalted water": "Moong sprouts",
    "sauces, indian cook in, other": "Curry sauce",
    "milk, condensed, whole, sweetened": "Condensed milk",
}

# Ordered (category, keywords). First match wins; multi-word keywords first.
CATEGORY_RULES = [
    ("Pantry", ["coconut milk", "chilli powder", "chilli sauce", "coriander seeds", "dried red chillies", "garam masala",
                "baking powder", "soy sauce", "tomato sauce", "tomato puree", "curry sauce", "dry ginger"]),
    ("Grains & flours", ["besan", "gram flour", "atta", "maida", "suji", "semolina", "rice", "pasta", "noodle",
                         "vermicelli", "poha", "oats", "bread", "flour"]),
    ("Dals & pulses", ["dal", "chana", "rajma", "lentil", "moong", "masoor", "lobia", "soya chunks", "sprouts"]),
    ("Dairy", ["paneer", "curd", "yogurt", "milk", "butter", "cheese", "cream", "khoa", "khoya"]),
    ("Pantry", ["salt", "sugar", "oil", "ghee", "turmeric", "cumin", "pepper", "clove", "cardamom", "cinnamon",
                "bay leaves", "mustard seeds", "ajwain", "asafoetida", "hing", "fenugreek seeds", "fennel", "poppy",
                "saffron", "nutmeg", "oregano", "vinegar", "yeast", "tamarind", "jaggery", "honey", "sauce", "masala",
                "seeds", "powder"]),
    ("Fruits", ["banana", "apple", "mango", "orange", "papaya", "pomegranate", "grapes", "guava", "pineapple"]),
]
VEGETABLE_DEFAULT = "Vegetables & herbs"
CATEGORY_ORDER = ["Vegetables & herbs", "Fruits", "Dairy", "Grains & flours", "Dals & pulses", "Other", "Pantry"]

# unit -> (base unit, factor)
_UNITS = {
    "g": ("g", 1), "gm": ("g", 1), "gms": ("g", 1), "gram": ("g", 1), "grams": ("g", 1),
    "kg": ("g", 1000), "mg": ("g", 0.001),
    "ml": ("ml", 1), "l": ("ml", 1000), "litre": ("ml", 1000), "liter": ("ml", 1000),
    "tsp": ("ml", 5), "teaspoon": ("ml", 5), "tbsp": ("ml", 15), "tablespoon": ("ml", 15),
    "c": ("ml", 240), "cup": ("ml", 240), "cups": ("ml", 240),
}

_SPOON_UNITS = {"tsp", "teaspoon", "tbsp", "tablespoon", "c", "cup", "cups"}
# Things measured by volume in a kitchen and sold by volume.
_LIQUID_WORDS = ("oil", "ghee", "milk", "sauce", "vinegar", "juice", "cream", "honey", "syrup", "puree", "water")
# Grams per ml for dry things measured with spoons (1 tsp of a ground spice is about 3 g).
_SPOON_DENSITY = (("salt", 1.2), ("sugar", 0.85), ("butter", 0.95), ("dal", 0.8), ("coconut", 0.5))
_DRY_SPOON_DENSITY = 0.6
# A single recipe line with this much oil per serving is deep-frying oil.
FRYING_OIL_ML = 120
SPRIG_GRAMS = 2

_VEGETABLE_WORDS = {
    "onion", "tomato", "potato", "spinach", "carrot", "peas", "beans", "capsicum", "cabbage", "cauliflower",
    "brinjal", "bhindi", "radish", "turnip", "beetroot", "drumstick", "mushroom", "ginger", "garlic", "chillies",
    "coriander leaves", "curry leaves", "mint", "bathua", "spring onions", "lemon", "coconut", "methi", "gourd",
    "pumpkin", "cucumber", "corn", "leaves", "lettuce", "celery", "zucchini",
}


def display_name(food_name: str) -> str:
    """'Onion, big (Allium cepa)' -> 'Onion'; known dataset names use DISPLAY_NAMES."""
    raw = re.sub(r"\s+", " ", str(food_name or "")).strip()
    no_latin = re.sub(r"\s*\(.*?\)\s*", " ", raw).strip()
    key = no_latin.lower().rstrip(",").strip()
    if key in DISPLAY_NAMES:
        return DISPLAY_NAMES[key]
    first = no_latin.split(",")[0].strip() or raw
    if first.isupper():
        first = first.title()
    return first[:1].upper() + first[1:]


def category_for(name: str) -> str:
    lowered = name.lower()
    for category, words in CATEGORY_RULES:
        if any(w in lowered for w in words):
            return category
    if any(w in lowered for w in _VEGETABLE_WORDS):
        return VEGETABLE_DEFAULT
    return "Other"


def _is_water(food_name: str) -> bool:
    return bool(re.match(r"^\s*water\b", str(food_name or ""), re.I))


def _is_liquid(name: str) -> bool:
    lowered = name.lower()
    return any(w in lowered for w in _LIQUID_WORDS)


def _to_base(name: str, amount: float, unit: str) -> tuple[float, str]:
    """Convert one recipe quantity to g, ml or a count unit."""
    base, factor = _UNITS.get(unit, (unit or "piece", 1))
    quantity = amount * factor
    if unit in _SPOON_UNITS and not _is_liquid(name):
        lowered = name.lower()
        density = next((d for w, d in _SPOON_DENSITY if w in lowered), _DRY_SPOON_DENSITY)
        return quantity * density, "g"
    return quantity, base


def _shop_round(base_unit: str, quantity: float) -> tuple[float, str]:
    """Round up to a size shops sell: 1/5/25/50/250 steps by size; >=1000 shown in kg/l."""
    if base_unit in ("g", "ml"):
        big = "kg" if base_unit == "g" else "l"
        if quantity < 5:
            step = 1  # saffron, hing, nutmeg: a pinch, not a 25 g pack
        elif quantity < 25:
            step = 5
        elif quantity < 100:
            step = 25
        elif quantity < 1000:
            step = 50
        else:
            step = 250
        rounded = math.ceil(quantity / step) * step
        if rounded >= 1000:
            return round(rounded / 1000, 2), big
        return float(rounded), base_unit
    return float(math.ceil(quantity - 1e-9)), base_unit


def aggregate_ingredients(ingredients: list[dict], household_size: int = 1) -> list[dict]:
    """Merge a plan's ingredient rows into grocery items (see module docstring)."""
    scale = max(1, int(household_size or 1))
    totals: dict[tuple[str, str], float] = defaultdict(float)
    names: dict[tuple[str, str], str] = {}
    frying: dict[str, float] = {}  # oil name -> largest single frying quantity (ml)

    for row in ingredients:
        food = str(row.get("food_name") or "").strip()
        if not food or _is_water(food):
            continue
        try:
            amount = float(row.get("amount"))
        except (TypeError, ValueError):
            continue
        if amount <= 0:
            continue
        unit = str(row.get("unit") or "").strip().lower()
        name = display_name(food)
        quantity, base = _to_base(name, amount, unit)
        if base == "ml" and "oil" in name.lower() and quantity >= FRYING_OIL_ML:
            frying[name] = max(frying.get(name, 0), quantity)
            continue
        key = (name.casefold(), base)
        names[key] = name
        totals[key] += quantity * scale

    # Frying oil is topped up and reused across the week: buy the biggest batch once.
    for name, quantity in frying.items():
        label = f"{name} (for frying)"
        key = (label.casefold(), "ml")
        names[key] = label
        totals[key] = quantity

    if not totals:
        raise GroceryListError("No ingredients to shop for in this meal plan.")

    # If an item appears in both g and ml (e.g. oil), keep one line in the larger measure.
    by_name: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for key in totals:
        by_name[key[0]].append(key)
    for keys in by_name.values():
        # Herbs listed both in grams and sprigs (coriander) -> one line in grams.
        sprig = next((k for k in keys if k[1] == "sprig"), None)
        grams = next((k for k in keys if k[1] == "g"), None)
        if sprig and grams:
            totals[grams] += totals.pop(sprig) * SPRIG_GRAMS
            names.pop(sprig, None)
            keys = [k for k in keys if k != sprig]
        measures = [k for k in keys if k[1] in ("g", "ml")]
        if len(measures) == 2:
            keep, drop = sorted(measures, key=lambda k: totals[k], reverse=True)
            totals[keep] += totals.pop(drop)  # ~1 g per ml for kitchen liquids/fats
            names.pop(drop, None)

    items = []
    for key, required in totals.items():
        name = names[key]
        purchase, unit = _shop_round(key[1], required)
        items.append({
            "ingredient_name": name,
            "required_quantity": round(required, 3),
            "purchase_quantity": purchase,
            "unit": unit,
            "category": category_for(name),
            "is_purchased": False,
            "is_urgent": False,
        })
    order = {c: i for i, c in enumerate(CATEGORY_ORDER)}
    items.sort(key=lambda i: (order.get(i["category"], len(order)), i["ingredient_name"].casefold()))
    return items


def carry_over_purchased(items: list[dict], previously_purchased: set[str]) -> list[dict]:
    """Keep items ticked when a list is rebuilt (matched by display name)."""
    for item in items:
        if item["ingredient_name"].casefold() in previously_purchased:
            item["is_purchased"] = True
    return items
