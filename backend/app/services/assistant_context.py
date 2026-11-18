"""The signed-in user's own Annora data, shaped for the Ask Annora prompt.

Meal slots are given short refs (M1, M2, ...) so the model never sees or
invents database ids; the backend maps refs back to meal_plan ids.
"""

from dataclasses import dataclass, field

import httpx

from app.services import assistant_store, plan_ops
from app.services import supabase_rest as db


class AssistantContextError(RuntimeError):
    pass


@dataclass
class UserContext:
    user_id: str
    data: dict
    plan: dict | None = None
    slots: dict[str, dict] = field(default_factory=dict)  # "M1" -> meal_plan row

    def slot_id(self, ref: str) -> str | None:
        row = self.slots.get(str(ref or "").strip().upper())
        return row["id"] if row else None

    def ref_for(self, meal_plan_id: str) -> str | None:
        return next((ref for ref, row in self.slots.items() if row["id"] == meal_plan_id), None)


def _kcal(nutrition: dict | None) -> int | None:
    value = (nutrition or {}).get("unit_serving_energy_kcal")
    return round(value) if isinstance(value, (int, float)) and value <= plan_ops.IMPLAUSIBLE_KCAL else None


def _protein(nutrition: dict | None) -> float | None:
    value = (nutrition or {}).get("unit_serving_protein_g")
    return round(value, 1) if isinstance(value, (int, float)) else None


async def load_user_context(client: httpx.AsyncClient, user_id: str) -> UserContext:
    try:
        household = await plan_ops.load_household(client, user_id)
        profiles = await db.select(client, "onboarding_profiles", {
            "select": "monthly_budget", "user_id": f"eq.{user_id}", "limit": "1",
        })
        plan, rows = await plan_ops.load_active_plan(client, user_id)
        memory = await assistant_store.memory_facts(client, user_id)

        grocery = None
        if plan is not None:
            lists = await db.select(client, "grocery_lists", {
                "select": "id",
                "meal_id": f"eq.{plan['id']}",
                "user_id": f"eq.{user_id}",
                "limit": "1",
            })
            if lists:
                items = await db.select(client, "grocery_items", {
                    "select": "ingredient_name,purchase_quantity,unit,category,is_purchased",
                    "grocery_list_id": f"eq.{lists[0]['id']}",
                    "order": "ingredient_name.asc",
                    "limit": "150",
                })
                grocery = {
                    "to_buy": [f"{i['ingredient_name']} {float(i.get('purchase_quantity') or 0):g} {i['unit']}".strip()
                               for i in items if not i.get("is_purchased")],
                    "already_bought": [i["ingredient_name"] for i in items if i.get("is_purchased")],
                }
    except (db.SupabaseError, httpx.HTTPError, KeyError, TypeError, ValueError) as exc:
        raise AssistantContextError("Could not load your Annora data.") from exc

    slots: dict[str, dict] = {}
    meals = []
    for i, row in enumerate(rows, start=1):
        ref = f"M{i}"
        slots[ref] = row
        meals.append({
            "ref": ref,
            "date": row["meal_date"],
            "meal_type": row["meal_type"],
            "dish": row.get("name"),
            "recipe_code": row.get("source_recipe_code"),
            "kcal_per_serving": _kcal(row.get("nutrition")),
            "protein_g": _protein(row.get("nutrition")),
            "changed_by": {"app_swap": "you in the app", "annora_chat": "Ask Annora"}.get(row.get("origin") or ""),
        })

    data = {
        "household": {
            "people": household["family_size"],
            "diet": household["dietary_preference"],
            "health_goals": household["dietary_goals"],
            "foods_to_avoid": household["dietary_exclusions"],
            "monthly_budget_inr": (profiles[0].get("monthly_budget") if profiles else None),
        },
        "remembered_about_user": memory,
        "active_meal_plan": (
            {"start_date": plan["start_date"], "end_date": plan["end_date"], "meals": meals} if plan else None
        ),
        "grocery_list": grocery,
    }
    return UserContext(user_id=user_id, data=data, plan=plan, slots=slots)
