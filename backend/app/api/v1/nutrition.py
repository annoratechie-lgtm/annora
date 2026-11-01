import re
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException, status

from app.core.config import settings

router = APIRouter(prefix="/nutrition", tags=["nutrition"])

_NUTRITION_COLUMNS = (
    "unit_serving_energy_kcal",
    "unit_serving_protein_g",
    "unit_serving_carb_g",
    "servings_unit",
)
_RECIPE_CODE = re.compile(r"^[A-Za-z0-9_-]+$")


class NutritionFetchError(RuntimeError):
    """Raised when recipe nutrition cannot be read from Supabase."""


def _headers() -> dict[str, str]:
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise NutritionFetchError("Supabase backend configuration is missing.")
    return {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
    }


async def fetch_recipe_nutrition(
    source_recipe_codes: list[str],
    *,
    client: httpx.AsyncClient | None = None,
) -> dict[str, dict[str, Any]]:
    """Fetch INDB per-serving nutrition, keyed by recipes.source_recipe_code.

    INDB stores the matching recipe identifier in recipe_nutrition.food_code.
    Missing recipe rows are omitted so callers can attach an empty nutrition map.
    """
    # codes = sorted({str(code).strip().upper() for code in source_recipe_codes if code})
    codes = source_recipe_codes
    print(codes)
    # if not codes:
    #     return {}
    # if any(not _RECIPE_CODE.fullmatch(code) for code in codes):
    #     raise NutritionFetchError("A recipe code has an unsupported format.")

    async def _fetch(using_client: httpx.AsyncClient) -> dict[str, dict[str, Any]]:
        response = await using_client.get(
            f"{settings.supabase_url.rstrip('/')}/rest/v1/recipe_nutrition",
            params={
                "select": ",".join(("source_recipe_code", *_NUTRITION_COLUMNS)),
                "source_recipe_code": f"in.({','.join(codes)})",
            },
            headers=_headers(),
        )
        if response.status_code != 200:
            detail = response.text.strip()[:300]
            raise NutritionFetchError(
                f"Could not load recipe nutrition from Supabase ({response.status_code}): "
                f"{detail or 'Supabase returned an empty error.'}"
            )

        rows = response.json()
        print(rows)
        if not isinstance(rows, list):
            raise NutritionFetchError("Supabase returned an invalid recipe nutrition response.")

        return {
            row["source_recipe_code"]: {column: row.get(column) for column in _NUTRITION_COLUMNS}
            for row in rows
            if isinstance(row, dict) and row.get("source_recipe_code") in codes
        }

    _headers()  # Fail clearly before opening a client when configuration is absent.
    try:
        if client is not None:
            return await _fetch(client)
        async with httpx.AsyncClient(timeout=15) as owned_client:
            return await _fetch(owned_client)
    except httpx.HTTPError as exc:
        raise NutritionFetchError("Could not reach Supabase while loading recipe nutrition.") from exc


@router.get("/recipes/{source_recipe_code}")
async def get_recipe_nutrition(source_recipe_code: str):
    """Return the per-serving INDB values for one recipe code."""
    try:
        nutrition_by_code = await fetch_recipe_nutrition([source_recipe_code])
    except NutritionFetchError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from exc

    code = source_recipe_code.strip().upper()
    return {
        "source_recipe_code": code,
        "nutrition": nutrition_by_code.get(code, {}),
    }
