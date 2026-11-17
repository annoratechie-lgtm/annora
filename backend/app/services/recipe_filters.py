"""Rules that turn a household's onboarding answers into recipe filters.

Kept free of I/O so they can be unit-tested; meal_planner.py does the
Supabase calls.
"""

import re

# recipes.preference values each onboarding diet may eat.
DIET_TO_RECIPE_PREFERENCES: dict[str, list[str]] = {
    "vegan": ["vegan"],
    "vegetarian": ["vegetarian", "vegan"],
    "eggetarian": ["eggetarian", "vegetarian", "vegan"],
    "non_vegetarian": ["non_vegetarian", "eggetarian", "vegetarian", "vegan"],
    "no_restriction": ["non_vegetarian", "eggetarian", "vegetarian", "vegan"],
}


def recipe_preferences_for(diet: str | None) -> list[str]:
    """Recipe preference tags allowed for an onboarding diet (unknown -> vegetarian set)."""
    return DIET_TO_RECIPE_PREFERENCES.get((diet or "").strip().lower(), DIET_TO_RECIPE_PREFERENCES["vegetarian"])


# Onboarding preset -> (ingredient words that match, words that cancel a match).
# Tuned against recipe_ingredient.food_name (INDB naming), e.g. "Coconut milk"
# is not dairy, "Buckwheat" is gluten-free, "Cream of tartar" is not cream.
_PRESETS: dict[str, tuple[list[str], list[str]]] = {
    "peanuts": (["peanut", "groundnut"], []),
    "mushroom": (["mushroom"], []),
    "onion & garlic": (["onion", "garlic"], []),
    "gluten": (
        ["wheat", "atta", "maida", "semolina", "suji", "sooji", "rava", "vermicelli", "bread", "pasta",
         "noodle", "barley", "rye", "seitan"],
        ["buckwheat"],
    ),
    "dairy": (
        ["milk", "butter", "ghee", "cheese", "paneer", "khoa", "khoya", "cream", "curd", "yoghurt", "yogurt",
         "dahi", "whey", "lassi"],
        ["coconut milk", "almond milk", "soy milk", "soya milk", "oat milk", "rice milk", "cashew milk",
         "peanut butter", "cocoa butter", "almond butter", "cream of tartar"],
    ),
    "seafood": (
        ["fish", "prawn", "shrimp", "crab", "lobster", "squid", "octopus", "mussel", "oyster", "clam", "scallop",
         "anchovy", "sardine", "mackerel", "tuna", "salmon", "pomfret", "rohu", "catla", "hilsa", "seer", "cod",
         "surmai", "bombay duck"],
        [],
    ),
}

_SAFE = re.compile(r"[^a-z0-9 \-]")


def _clean(term: str) -> str:
    # Only letters, digits, spaces and hyphens reach the PostgREST filter.
    return re.sub(r"\s+", " ", _SAFE.sub(" ", term.lower())).strip()


def exclusion_rules(exclusions: list[str]) -> list[tuple[list[str], list[str]]]:
    """Expand the user's foods-to-avoid into (match words, exception words) rules."""
    rules: list[tuple[list[str], list[str]]] = []
    for raw in exclusions:
        key = (raw or "").strip().lower()
        if not key:
            continue
        if key in _PRESETS:
            rules.append(_PRESETS[key])
            continue
        term = _clean(key)
        if len(term) < 3:
            continue
        words = {term}
        if term.endswith("s") and len(term) > 4:  # "brinjals" -> "brinjal"
            words.add(term[:-1])
        rules.append((sorted(words), []))
    return rules


def match_terms(rules: list[tuple[list[str], list[str]]]) -> list[str]:
    """All match words, cleaned and de-duplicated, for one ilike query."""
    seen: list[str] = []
    for positives, _ in rules:
        for word in positives:
            word = _clean(word)
            if word and word not in seen:
                seen.append(word)
    return seen


def excluded_recipe_codes(rows: list[dict], rules: list[tuple[list[str], list[str]]]) -> set[str]:
    """Recipe codes with at least one ingredient hit by a rule (and not saved by an exception)."""
    codes: set[str] = set()
    for row in rows:
        name = str(row.get("food_name") or "").lower()
        code = str(row.get("source_recipe_code") or "").strip().upper()
        if not name or not code:
            continue
        for positives, negatives in rules:
            if any(p in name for p in positives) and not any(n in name for n in negatives):
                codes.add(code)
                break
    return codes


_GOAL_TEXT = {
    "keto": "keto (low carbohydrate)",
    "diabetic_friendly": "diabetic-friendly (low glycaemic, limited sugar and refined carbs)",
    "high_protein": "high protein",
    "low_sodium": "low sodium",
}


def goals_guidance(goals: list[str]) -> str:
    """Prompt line describing the household's health goals ('' when none)."""
    labels = [_GOAL_TEXT[g] for g in goals if g in _GOAL_TEXT]
    if not labels:
        return ""
    return "- Health goals: " + ", ".join(labels) + ". Prefer recipes that suit these goals."
