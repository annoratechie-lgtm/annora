"""Changes to a user's active meal plan, shared by the app and Ask Annora.

- find_alternatives: recipes that may replace one dish (same category, the
  household's diet, none of its foods to avoid).
- apply_swaps: replace dishes, log each change in plan_changes with its source,
  refresh the plan's ingredients and rebuild its grocery list (ticks kept).
Every function takes the authenticated user's id and scopes all reads/writes to it.
"""

import random
from datetime import datetime, timezone

import httpx

from app.api.v1.nutrition import NutritionFetchError, fetch_recipe_nutrition
from app.services import supabase_rest as db
from app.services.grocery_list_service import (
    GroceryListError,
    aggregate_ingredients,
    carry_over_purchased,
    display_name,
)
from app.services.recipe_filters import recipe_preferences_for

SWAPPABLE_CATEGORIES = ("breakfast", "main_course", "staple")
# Calorie values above this per serving are data errors in the recipe set (see Dish.caloriesUnverified).
IMPLAUSIBLE_KCAL = 1500

SOURCES = {"app", "annora_chat"}
SLOT_ORIGIN = {"app": "app_swap", "annora_chat": "annora_chat"}


class PlanChangeError(RuntimeError):
    """A change can't be made (stale proposal, recipe not allowed, no plan...)."""


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


async def load_active_plan(client: httpx.AsyncClient, user_id: str) -> tuple[dict | None, list[dict]]:
    plans = await db.select(client, "meal", {
        "select": "id,start_date,end_date,status,origin",
        "user_id": f"eq.{user_id}",
        "status": "eq.active",
        "order": "created_at.desc",
        "limit": "1",
    })
    if not plans:
        return None, []
    rows = await db.select(client, "meal_plan", {
        "select": "id,meal_id,meal_date,meal_type,source_recipe_code,name,nutrition,origin",
        "meal_id": f"eq.{plans[0]['id']}",
        "order": "meal_date.asc,meal_type.asc,created_at.asc",
    })
    return plans[0], rows


async def load_household(client: httpx.AsyncClient, user_id: str) -> dict:
    profiles = await db.select(client, "onboarding_profiles", {
        "select": "family_size,dietary_preference,dietary_goals",
        "user_id": f"eq.{user_id}",
        "limit": "1",
    })
    exclusions = await db.select(client, "dietary_exclusions", {
        "select": "ingredient_name",
        "user_id": f"eq.{user_id}",
    })
    profile = profiles[0] if profiles else {}
    return {
        "family_size": profile.get("family_size") or 1,
        "dietary_preference": profile.get("dietary_preference"),
        "dietary_goals": profile.get("dietary_goals") or [],
        "dietary_exclusions": [r["ingredient_name"] for r in exclusions if r.get("ingredient_name")],
    }


def _name(row: dict) -> str:
    return (row.get("recipe_display_name") or "").strip() or (row.get("recipe_name") or "").strip()


async def recipe_categories(client: httpx.AsyncClient, codes: list[str]) -> dict[str, str]:
    codes = sorted({c for c in codes if c})
    if not codes:
        return {}
    rows = await db.select(client, "recipes", {
        "select": "source_recipe_code,category",
        "source_recipe_code": f"in.({','.join(codes)})",
    })
    return {r["source_recipe_code"]: r.get("category") or "" for r in rows if r.get("source_recipe_code")}


async def allowed_recipes(client: httpx.AsyncClient, household: dict, category: str) -> dict[str, dict]:
    """Recipes of one category this household may eat, keyed by code."""
    # Imported here to avoid a cycle (meal_planner imports the LLM client stack).
    from app.services.meal_planner import _load_excluded_codes

    if category not in SWAPPABLE_CATEGORIES:
        return {}
    rows = await db.select(client, "recipes", {
        "select": "source_recipe_code,recipe_name,recipe_display_name,category",
        "status": "eq.active",
        "category": f"eq.{category}",
        "preference": f"in.({','.join(recipe_preferences_for(household.get('dietary_preference')))})",
    })
    try:
        excluded = await _load_excluded_codes(household.get("dietary_exclusions") or [])
    except RuntimeError as exc:
        raise PlanChangeError(str(exc)) from exc
    allowed = {}
    for row in rows:
        code = (row.get("source_recipe_code") or "").strip().upper()
        if code and code not in excluded and code not in allowed and _name(row):
            allowed[code] = {"code": code, "name": _name(row), "category": category}
    return allowed


async def _nutrition(client: httpx.AsyncClient, codes: list[str]) -> dict[str, dict]:
    if not codes:
        return {}
    try:
        return await fetch_recipe_nutrition(sorted(set(codes)), client=client)
    except NutritionFetchError:
        return {}


def _nutrition_summary(n: dict | None) -> dict:
    n = n or {}
    kcal = n.get("unit_serving_energy_kcal")
    return {
        "kcal": round(kcal) if isinstance(kcal, (int, float)) else None,
        "protein_g": round(n["unit_serving_protein_g"], 1) if isinstance(n.get("unit_serving_protein_g"), (int, float)) else None,
        "carbs_g": round(n["unit_serving_carb_g"], 1) if isinstance(n.get("unit_serving_carb_g"), (int, float)) else None,
        "kcal_unverified": isinstance(kcal, (int, float)) and kcal > IMPLAUSIBLE_KCAL,
    }


async def recipe_details(client: httpx.AsyncClient, code: str) -> dict | None:
    """Name, category, per-serving nutrition and ingredients of one recipe."""
    code = (code or "").strip().upper()
    if not code:
        return None
    recipes = await db.select(client, "recipes", {
        "select": "source_recipe_code,recipe_name,recipe_display_name,category,preference",
        "source_recipe_code": f"eq.{code}",
        "limit": "1",
    })
    if not recipes:
        return None
    ingredients = await db.select(client, "recipe_ingredient", {
        "select": "food_name,amount,unit",
        "source_recipe_code": f"eq.{code}",
    })
    nutrition = await _nutrition(client, [code])
    return {
        "code": code,
        "name": _name(recipes[0]),
        "category": recipes[0].get("category"),
        "diet": recipes[0].get("preference"),
        "per_serving": _nutrition_summary(nutrition.get(code)),
        "ingredients": [
            {"name": display_name(i.get("food_name", "")), "amount": i.get("amount"), "unit": i.get("unit") or ""}
            for i in ingredients
            if not str(i.get("food_name", "")).lower().startswith("water")
        ],
        "note": "Annora's recipe data has ingredients and nutrition but no cooking steps.",
    }


async def find_alternatives(
    client: httpx.AsyncClient,
    user_id: str,
    meal_plan_id: str,
    sort: str = "any",
    limit: int = 6,
) -> dict:
    """Recipes that could replace one dish in the active plan."""
    plan, rows = await load_active_plan(client, user_id)
    row = next((r for r in rows if r["id"] == meal_plan_id), None)
    if plan is None or row is None:
        raise PlanChangeError("That meal isn't in your current plan.")
    current = (row.get("source_recipe_code") or "").upper()
    category = (await recipe_categories(client, [current])).get(current) or "main_course"
    household = await load_household(client, user_id)
    allowed = await allowed_recipes(client, household, category)

    in_plan = {(r.get("source_recipe_code") or "").upper() for r in rows}
    candidates = [c for code, c in allowed.items() if code not in in_plan] or [
        c for code, c in allowed.items() if code != current
    ]
    if sort in ("protein", "lighter"):
        sample = candidates
    else:
        sample = random.sample(candidates, min(len(candidates), limit * 4))
    nutrition = await _nutrition(client, [c["code"] for c in sample])
    options = [dict(c, **_nutrition_summary(nutrition.get(c["code"]))) for c in sample]
    if sort == "protein":
        options.sort(key=lambda o: -(o["protein_g"] or 0))
    elif sort == "lighter":
        options = [o for o in options if o["kcal"] and not o["kcal_unverified"]]
        options.sort(key=lambda o: o["kcal"])
    return {
        "meal": {
            "meal_plan_id": row["id"],
            "date": row["meal_date"],
            "meal_type": row["meal_type"],
            "current": {"code": current, "name": row.get("name"), **_nutrition_summary(row.get("nutrition"))},
            "category": category,
        },
        "alternatives": options[:limit],
    }


async def validate_swaps(client: httpx.AsyncClient, user_id: str, changes: list[dict]) -> tuple[dict, list[dict]]:
    """Check proposed swaps against the live plan; returns (plan, enriched changes).

    Each change: {meal_plan_id, to_code, from_code?}. A from_code that no longer
    matches means the plan changed since the proposal -> PlanChangeError.
    """
    if not changes:
        raise PlanChangeError("No changes to make.")
    plan, rows = await load_active_plan(client, user_id)
    if plan is None:
        raise PlanChangeError("You don't have an active meal plan.")
    by_id = {r["id"]: r for r in rows}
    current_codes = [(by_id.get(c.get("meal_plan_id")) or {}).get("source_recipe_code") or "" for c in changes]
    categories = await recipe_categories(client, [c.upper() for c in current_codes])
    household = await load_household(client, user_id)
    allowed_by_category: dict[str, dict] = {}

    enriched = []
    for change in changes:
        row = by_id.get(change.get("meal_plan_id"))
        if row is None:
            raise PlanChangeError("A meal in this change is no longer in your plan.")
        current = (row.get("source_recipe_code") or "").upper()
        expected = (change.get("from_code") or "").upper()
        if expected and expected != current:
            raise PlanChangeError(
                f"{row['meal_type'].title()} on {row['meal_date']} has changed since this was suggested."
            )
        category = categories.get(current) or "main_course"
        if category not in allowed_by_category:
            allowed_by_category[category] = await allowed_recipes(client, household, category)
        to_code = (change.get("to_code") or "").strip().upper()
        target = allowed_by_category[category].get(to_code)
        if target is None:
            raise PlanChangeError("That recipe isn't available for this meal with your diet and foods to avoid.")
        if to_code == current:
            raise PlanChangeError(f"{target['name']} is already planned there.")
        enriched.append({
            "meal_plan_id": row["id"],
            "date": row["meal_date"],
            "meal_type": row["meal_type"],
            "from": {"code": current, "name": row.get("name")},
            "to": {"code": to_code, "name": target["name"]},
        })
    return plan, enriched


async def refresh_meal_ingredients(client: httpx.AsyncClient, meal_id: str) -> list[dict]:
    """Recompute meal_ingredients for a plan from its current recipes."""
    generated = await db.rpc(client, "get_meal_plan_ingredients", {"p_meal_id": meal_id}) or []
    rows = [
        {
            "meal_id": g["meal_id"],
            "meal_type": g["meal_type"],
            "source_recipe_code": g["source_recipe_code"],
            "food_code_org": g.get("food_code_org"),
            "food_name": g["food_name"],
            "amount": g["amount"],
            "unit": g["unit"],
        }
        for g in generated
        if g.get("amount") and float(g["amount"]) > 0
    ]
    await db.delete(client, "meal_ingredients", {"meal_id": f"eq.{meal_id}"})
    if rows:
        await db.insert(client, "meal_ingredients", rows)
    return generated


async def rebuild_grocery_list(
    client: httpx.AsyncClient, user_id: str, meal_id: str, create_if_missing: bool = True
) -> dict | None:
    """Rebuild (or create) the plan's grocery list, keeping ticked items ticked."""
    ingredients = await db.select(client, "meal_ingredients", {
        "select": "food_name,amount,unit",
        "meal_id": f"eq.{meal_id}",
    })
    household = await load_household(client, user_id)
    items = aggregate_ingredients(ingredients, household_size=household["family_size"])

    existing = await db.select(client, "grocery_lists", {
        "select": "id",
        "meal_id": f"eq.{meal_id}",
        "user_id": f"eq.{user_id}",
        "order": "created_at.desc",
        "limit": "1",
    })
    if existing:
        list_id = existing[0]["id"]
        ticked = await db.select(client, "grocery_items", {
            "select": "ingredient_name",
            "grocery_list_id": f"eq.{list_id}",
            "is_purchased": "eq.true",
        })
        carry_over_purchased(items, {str(r.get("ingredient_name", "")).casefold() for r in ticked})
        await db.delete(client, "grocery_items", {"grocery_list_id": f"eq.{list_id}"})
        await db.update(client, "grocery_lists", {"id": f"eq.{list_id}"}, {"status": "active", "updated_at": _now()})
    elif create_if_missing:
        created = await db.insert(client, "grocery_lists", {"user_id": user_id, "meal_id": meal_id, "status": "active"})
        if not created:
            raise db.SupabaseError("Supabase did not return the created grocery list.")
        list_id = created[0]["id"]
    else:
        return None

    await db.insert(client, "grocery_items", [dict(item, grocery_list_id=list_id) for item in items])
    return {"grocery_list_id": list_id, "meal_id": meal_id, "item_count": len(items), "items": items}


async def apply_swaps(
    client: httpx.AsyncClient,
    user_id: str,
    changes: list[dict],
    source: str,
    message_id: str | None = None,
) -> dict:
    """Validate and apply swaps, then refresh ingredients and the grocery list."""
    if source not in SOURCES:
        raise ValueError(f"Unknown change source {source!r}.")
    plan, enriched = await validate_swaps(client, user_id, changes)
    nutrition = await _nutrition(client, [c["to"]["code"] for c in enriched])

    for change in enriched:
        await db.update(client, "meal_plan", {"id": f"eq.{change['meal_plan_id']}", "meal_id": f"eq.{plan['id']}"}, {
            "source_recipe_code": change["to"]["code"],
            "name": change["to"]["name"],
            "nutrition": nutrition.get(change["to"]["code"], {}),
            "origin": SLOT_ORIGIN[source],
            "updated_at": _now(),
        })
    await db.insert(client, "plan_changes", [
        {
            "user_id": user_id,
            "meal_id": plan["id"],
            "meal_plan_id": c["meal_plan_id"],
            "change_type": "swap",
            "source": source,
            "message_id": message_id,
            "before": c["from"],
            "after": c["to"],
        }
        for c in enriched
    ])

    await refresh_meal_ingredients(client, plan["id"])
    grocery = None
    try:
        grocery = await rebuild_grocery_list(client, user_id, plan["id"], create_if_missing=False)
    except GroceryListError:
        grocery = None
    return {"meal_id": plan["id"], "changes": enriched, "grocery_list_rebuilt": grocery is not None}
