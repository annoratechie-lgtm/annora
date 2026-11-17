from app.services.meal_planner import _build_system_prompt
from app.schemas.meal_plan import MealPlanningContext
from app.services.recipe_filters import (
    excluded_recipe_codes,
    exclusion_rules,
    goals_guidance,
    match_terms,
    recipe_preferences_for,
)
from datetime import date

# food_name values as they appear in recipe_ingredient (INDB naming)
ROWS = [
    {"source_recipe_code": "ASC001", "food_name": "Peanuts, dry roasted"},
    {"source_recipe_code": "ASC002", "food_name": "Coconut milk"},
    {"source_recipe_code": "ASC003", "food_name": "Milk, whole, cow"},
    {"source_recipe_code": "ASC004", "food_name": "Peanut butter, smooth"},
    {"source_recipe_code": "ASC005", "food_name": "Buckwheat, groats"},
    {"source_recipe_code": "ASC006", "food_name": "Wheat flour, atta (Triticum aestivum)"},
    {"source_recipe_code": "ASC007", "food_name": "Cream of tartar"},
    {"source_recipe_code": "ASC008", "food_name": "Paneer"},
    {"source_recipe_code": "ASC009", "food_name": "Tiger prawns, brown (Solenocera crassicornis)"},
    {"source_recipe_code": "ASC010", "food_name": "Brinjal, round (Solanum melongena)"},
    {"source_recipe_code": "ASC011", "food_name": "Onion, big (Allium cepa)"},
    {"source_recipe_code": "asc012", "food_name": "Garlic powder"},
]


def codes(exclusions):
    return excluded_recipe_codes(ROWS, exclusion_rules(exclusions))


def test_diet_maps_to_every_recipe_tag_it_may_eat():
    assert recipe_preferences_for("vegan") == ["vegan"]
    assert recipe_preferences_for("vegetarian") == ["vegetarian", "vegan"]
    assert recipe_preferences_for("eggetarian") == ["eggetarian", "vegetarian", "vegan"]
    # Previously these matched nothing (no_restriction) or only meat dishes (non_vegetarian).
    assert set(recipe_preferences_for("non_vegetarian")) == {"non_vegetarian", "eggetarian", "vegetarian", "vegan"}
    assert set(recipe_preferences_for("no_restriction")) == {"non_vegetarian", "eggetarian", "vegetarian", "vegan"}
    assert recipe_preferences_for(None) == ["vegetarian", "vegan"]


def test_presets_respect_exceptions():
    assert codes(["Dairy"]) == {"ASC003", "ASC008"}          # not coconut milk, peanut butter, cream of tartar
    assert codes(["Gluten"]) == {"ASC006"}                   # not buckwheat
    assert codes(["Peanuts"]) == {"ASC001", "ASC004"}        # peanut butter counts as peanuts
    assert codes(["Seafood"]) == {"ASC009"}
    assert codes(["Onion & garlic"]) == {"ASC011", "ASC012"}  # codes normalised to upper case


def test_custom_items_match_singular_and_plural():
    assert codes(["brinjals"]) == {"ASC010"}
    assert codes(["  Brinjal "]) == {"ASC010"}


def test_unsafe_characters_never_reach_the_query():
    rules = exclusion_rules(["milk),food_name.ilike.*", "x", ""])
    terms = match_terms(rules)
    assert all(set(t) <= set("abcdefghijklmnopqrstuvwxyz0123456789 -") for t in terms)
    assert "x" not in terms  # too short to be meaningful


def test_goals_are_described_for_the_prompt():
    assert goals_guidance([]) == ""
    assert goals_guidance(["no_preference"]) == ""
    line = goals_guidance(["high_protein", "low_sodium"])
    assert "high protein" in line and "low sodium" in line

    ctx = MealPlanningContext(user_id="u", dietary_preference="vegetarian", dietary_goals=["keto"])
    prompt = _build_system_prompt(date(2026, 11, 17), ctx)
    assert "HOUSEHOLD PREFERENCES" in prompt and "keto" in prompt
    assert "HOUSEHOLD PREFERENCES" not in _build_system_prompt(date(2026, 11, 17), MealPlanningContext(user_id="u"))
