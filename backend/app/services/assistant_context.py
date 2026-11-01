import httpx

from app.core.config import settings


class AssistantContextError(RuntimeError):
    pass


async def _get_rows(
    client: httpx.AsyncClient,
    table: str,
    params: dict[str, str],
) -> list[dict]:
    response = await client.get(
        f"{settings.supabase_url.rstrip('/')}/rest/v1/{table}",
        params=params,
        headers={
            "apikey": settings.supabase_service_role_key,
            "Authorization": f"Bearer {settings.supabase_service_role_key}",
        },
    )
    if response.status_code != 200:
        raise AssistantContextError(
            f"Could not load Annora context from {table} (status {response.status_code})."
        )

    try:
        rows = response.json()
    except ValueError as exc:
        raise AssistantContextError(f"Supabase returned invalid data for {table}.") from exc

    if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
        raise AssistantContextError(f"Supabase returned an invalid result for {table}.")
    return rows


async def load_user_context(user_id: str) -> dict:
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise AssistantContextError("Supabase backend configuration is missing.")

    base_params = {"user_id": f"eq.{user_id}"}
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            profiles = await _get_rows(
                client,
                "onboarding_profiles",
                {
                    **base_params,
                    "select": "family_size,monthly_budget,dietary_preference,dietary_goals",
                    "limit": "1",
                },
            )
            exclusions = await _get_rows(
                client,
                "dietary_exclusions",
                {
                    **base_params,
                    "select": "ingredient_name",
                    "order": "ingredient_name.asc",
                    "limit": "100",
                },
            )
            plans = await _get_rows(
                client,
                "meal",
                {
                    **base_params,
                    "select": "id,start_date,end_date,status",
                    "status": "eq.active",
                    "order": "created_at.desc",
                    "limit": "1",
                },
            )

            plan = plans[0] if plans else None
            meals: list[dict] = []
            grocery_list = None
            if plan is not None:
                meals = await _get_rows(
                    client,
                    "meal_plan",
                    {
                        "meal_id": f"eq.{plan['id']}",
                        "select": "meal_date,meal_type,name,description,status,nutrition",
                        "order": "meal_date.asc,meal_type.asc",
                        "limit": "50",
                    },
                )
                grocery_lists = await _get_rows(
                    client,
                    "grocery_lists",
                    {
                        **base_params,
                        "meal_id": f"eq.{plan['id']}",
                        "select": "id,status",
                        "order": "created_at.desc",
                        "limit": "1",
                    },
                )
                if grocery_lists:
                    saved_list = grocery_lists[0]
                    grocery_items = await _get_rows(
                        client,
                        "grocery_items",
                        {
                            "grocery_list_id": f"eq.{saved_list['id']}",
                            "select": (
                                "ingredient_name,required_quantity,purchase_quantity,"
                                "unit,category,is_purchased,is_urgent"
                            ),
                            "order": "ingredient_name.asc",
                            "limit": "100",
                        },
                    )
                    grocery_list = {
                        "status": saved_list.get("status"),
                        "items": grocery_items,
                    }
    except httpx.HTTPError as exc:
        raise AssistantContextError("Could not reach Supabase to load Annora context.") from exc
    except KeyError as exc:
        raise AssistantContextError("Supabase returned incomplete Annora context.") from exc

    return {
        "profile": profiles[0] if profiles else None,
        "dietary_exclusions": [row["ingredient_name"] for row in exclusions],
        "active_meal_plan": (
            {
                "start_date": plan.get("start_date"),
                "end_date": plan.get("end_date"),
                "meals": meals,
            }
            if plan is not None
            else None
        ),
        "grocery_list": grocery_list,
    }
