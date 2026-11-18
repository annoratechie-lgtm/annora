"""Swap validation: only real, allowed recipes, and never on a changed plan."""

import asyncio

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import plan_ops

ROWS = [
    {"id": "row-1", "meal_date": "2026-11-19", "meal_type": "dinner", "source_recipe_code": "ASC226", "name": "Aloo gobhi"},
    {"id": "row-2", "meal_date": "2026-11-19", "meal_type": "dinner", "source_recipe_code": "ASC113", "name": "Chapati"},
]
ALLOWED = {
    "main_course": {"ASC300": {"code": "ASC300", "name": "Palak paneer", "category": "main_course"},
                    "ASC226": {"code": "ASC226", "name": "Aloo gobhi", "category": "main_course"}},
    "staple": {"ASC096": {"code": "ASC096", "name": "Jeera rice", "category": "staple"}},
}


@pytest.fixture(autouse=True)
def fake_plan(monkeypatch):
    async def load_active_plan(client, user_id):
        return ({"id": "plan-1"}, ROWS) if user_id == "user-a" else (None, [])

    async def recipe_categories(client, codes):
        return {"ASC226": "main_course", "ASC113": "staple"}

    async def load_household(client, user_id):
        return {"family_size": 2, "dietary_preference": "vegetarian", "dietary_goals": [], "dietary_exclusions": []}

    async def allowed_recipes(client, household, category):
        return ALLOWED.get(category, {})

    for name, fn in [("load_active_plan", load_active_plan), ("recipe_categories", recipe_categories),
                     ("load_household", load_household), ("allowed_recipes", allowed_recipes)]:
        monkeypatch.setattr(plan_ops, name, fn)


def validate(user, changes):
    return asyncio.run(plan_ops.validate_swaps(None, user, changes))


def test_valid_swap_is_enriched_for_the_apply_card():
    _, changes = validate("user-a", [{"meal_plan_id": "row-1", "from_code": "ASC226", "to_code": "asc300"}])
    assert changes == [{"meal_plan_id": "row-1", "date": "2026-11-19", "meal_type": "dinner",
                        "from": {"code": "ASC226", "name": "Aloo gobhi"},
                        "to": {"code": "ASC300", "name": "Palak paneer"}}]


@pytest.mark.parametrize("change, message", [
    ({"meal_plan_id": "row-1", "from_code": "ASC999", "to_code": "ASC300"}, "has changed"),
    ({"meal_plan_id": "row-1", "to_code": "ASC096"}, "isn't available"),      # staple can't replace a curry
    ({"meal_plan_id": "row-1", "to_code": "MADEUP1"}, "isn't available"),     # invented code
    ({"meal_plan_id": "row-1", "to_code": "ASC226"}, "already planned"),
    ({"meal_plan_id": "someone-elses-row", "to_code": "ASC300"}, "no longer in your plan"),
])
def test_invalid_swaps_are_refused(change, message):
    with pytest.raises(plan_ops.PlanChangeError, match=message):
        validate("user-a", [change])


def test_user_without_a_plan_cannot_swap():
    with pytest.raises(plan_ops.PlanChangeError, match="active meal plan"):
        validate("user-b", [{"meal_plan_id": "row-1", "to_code": "ASC300"}])


def test_swap_endpoints_need_a_token():
    c = TestClient(app)
    assert c.get("/api/v1/meal-plans/meals/row-1/alternatives").status_code == 401
    assert c.post("/api/v1/meal-plans/meals/row-1/swap", json={"recipe_code": "ASC300"}).status_code == 401


def test_dish_search_understands_hindi_names_and_spellings():
    terms = plan_ops._query_terms("besan ka chilla")
    assert plan_ops.match_score("Gram flour chilla/cheela (Besan chilla/cheela)", terms) == 2
    assert plan_ops.match_score("Paneer stuffed cheela/chilla", terms) == 1
    assert plan_ops.match_score("Poha", terms) == 0
    assert plan_ops.match_score("Aloo gobi", plan_ops._query_terms("aloo gobhi")) == 2


def test_find_alternatives_puts_the_named_dish_first(monkeypatch):
    async def allowed(client, household, category):
        return {c: {"code": c, "name": n, "category": "breakfast"} for c, n in [
            ("BFP047", "Paneer stuffed cheela/chilla"),
            ("OSR100", "Gram flour chilla/cheela (Besan chilla/cheela)"),
            ("BFP153", "Poha"),
        ]}

    async def categories(client, codes):
        return {"ASC226": "breakfast"}

    async def nutrition(client, codes):
        return {}

    monkeypatch.setattr(plan_ops, "allowed_recipes", allowed)
    monkeypatch.setattr(plan_ops, "recipe_categories", categories)
    monkeypatch.setattr(plan_ops, "_nutrition", nutrition)
    result = asyncio.run(plan_ops.find_alternatives(None, "user-a", "row-1", query="besan ka chilla"))
    assert [o["code"] for o in result["alternatives"]] == ["OSR100", "BFP047"]
    assert result["exact_match"] is True

    missing = asyncio.run(plan_ops.find_alternatives(None, "user-a", "row-1", query="masala dosa"))
    assert missing["exact_match"] is False and missing["alternatives"] == []
