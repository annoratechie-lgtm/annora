from app.services.meal_plan_repository import build_meal_rows


def test_build_meal_rows_keeps_one_row_per_date_and_meal_type():
    plan = {
        "2026-09-01": {
            "breakfast": "BFP153",
            "lunch": ["ASC142"],
            "dinner": ["BFP185", "ASC113"],
        },
        "2026-09-02": {
            "breakfast": "BFP114",
            "lunch": ["ASC096"],
            "dinner": ["ASC096"],
        },
    }

    rows = build_meal_rows("plan-123", plan, {"BFP153": "X", "ASC142": "Y", "BFP185": "Z", "ASC113": "W", "BFP114": "Q", "ASC096": "R"})

    keys = {(row["meal_date"], row["meal_type"]) for row in rows}
    assert len(rows) == len(keys)
    assert len(rows) == 6
    dinner_rows = [row for row in rows if row["meal_date"] == "2026-09-01" and row["meal_type"] == "dinner"]
    assert len(dinner_rows) == 1
    assert dinner_rows[0]["source_recipe_code"] == "BFP185"
    assert dinner_rows[0]["description"] == '{"additional_source_recipe_codes": ["ASC113"]}'
