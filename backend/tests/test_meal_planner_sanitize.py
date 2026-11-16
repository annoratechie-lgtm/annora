from app.services.meal_planner import sanitize_meal_plan

REFERENCE = [
    {"source_recipe_code": "BFP153", "category": "breakfast"},
    {"source_recipe_code": "ASC052", "category": "breakfast"},
    {"source_recipe_code": "BFP044", "category": "breakfast"},
    {"source_recipe_code": "ASC226", "category": "main_course"},
    {"source_recipe_code": "BFP185", "category": "main_course"},
    {"source_recipe_code": "ASC114", "category": "staple"},
    {"source_recipe_code": "ASC113", "category": "staple"},
    {"source_recipe_code": "ASC096", "category": "staple"},
]
MAIN = {"ASC226", "BFP185"}
STAPLE = {"ASC114", "ASC113", "ASC096"}
BREAKFAST = {"BFP153", "ASC052", "BFP044"}


def test_valid_codes_pass_through_unchanged():
    plan = {"2026-11-16": {"breakfast": "BFP153", "lunch": ["ASC226", "ASC113"], "dinner": ["BFP185", "ASC096"]}}
    out = sanitize_meal_plan(plan, REFERENCE)
    assert out["2026-11-16"] == {"breakfast": "BFP153", "lunch": ["ASC226", "ASC113"], "dinner": ["BFP185", "ASC096"]}


def test_name_dash_code_strings_are_reduced_to_the_code():
    # Real values seen in production meal_plan rows saved as "NA".
    plan = {"2026-11-16": {
        "breakfast": "Rice Flakes-ASC052",
        "lunch": ["Kadai Paneer-ASC226", "Plain Pulao-ASC114"],
        "dinner": ["KABULI CHANNA CURRY-BFP185", "Boiled Rice-ASC113"],
    }}
    out = sanitize_meal_plan(plan, REFERENCE)["2026-11-16"]
    assert out == {"breakfast": "ASC052", "lunch": ["ASC226", "ASC114"], "dinner": ["BFP185", "ASC113"]}


def test_two_codes_packed_in_one_string_are_split():
    plan = {"2026-11-16": {"breakfast": " bfp153 ", "lunch": ["ASC226, ASC113"], "dinner": ["BFP185,ASC096"]}}
    out = sanitize_meal_plan(plan, REFERENCE)["2026-11-16"]
    assert out == {"breakfast": "BFP153", "lunch": ["ASC226", "ASC113"], "dinner": ["BFP185", "ASC096"]}


def test_invented_codes_are_replaced_from_the_same_category():
    plan = {
        "2026-11-16": {"breakfast": "ASC539", "lunch": ["ZZZ999"], "dinner": ["Not a recipe"]},
        "2026-11-17": {"breakfast": "XYZ001", "lunch": ["ASC226", "QQQ123"], "dinner": []},
    }
    out = sanitize_meal_plan(plan, REFERENCE)
    for day in out.values():
        assert day["breakfast"] in BREAKFAST
        for meal_type in ("lunch", "dinner"):
            assert day[meal_type], f"{meal_type} must not be empty"
            assert set(day[meal_type]) <= MAIN | STAPLE
    # Valid code kept, invalid one dropped (no fallback needed when something valid remains)
    assert out["2026-11-17"]["lunch"] == ["ASC226"]
    # Replacement for an empty curry meal is a main course plus one staple
    assert out["2026-11-16"]["lunch"][0] in MAIN and out["2026-11-16"]["lunch"][1] in STAPLE
    # Replacement breakfast avoids repeating the previous day's
    assert out["2026-11-17"]["breakfast"] != out["2026-11-16"]["breakfast"]


def test_duplicate_codes_in_one_meal_are_collapsed():
    plan = {"2026-11-16": {"breakfast": "BFP153", "lunch": ["ASC226", "Kadai Paneer-ASC226", "ASC113"], "dinner": ["BFP185", "ASC096"]}}
    assert sanitize_meal_plan(plan, REFERENCE)["2026-11-16"]["lunch"] == ["ASC226", "ASC113"]
