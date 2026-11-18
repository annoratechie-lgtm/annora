"""Swap one dish from the app's Plan tab (source = 'app').

Ask Annora swaps use the same plan_ops code via /assistant/messages/{id}/apply.
"""

from typing import Literal

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field

from app.core.auth import require_authenticated_user
from app.services import assistant_store, plan_ops
from app.services import supabase_rest as db

router = APIRouter(prefix="/meal-plans/meals", tags=["meal-swaps"])


class SwapRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    recipe_code: str = Field(min_length=2, max_length=20)
    # The dish the user saw; a mismatch means the plan changed meanwhile.
    from_code: str | None = Field(default=None, max_length=20)


def _require_supabase() -> None:
    if not db.configured():
        raise HTTPException(status_code=503, detail="Supabase backend configuration is missing.")


@router.get("/{meal_plan_id}/alternatives")
async def alternatives(
    meal_plan_id: str,
    sort: Literal["any", "protein", "lighter"] = "any",
    q: str = Query(default="", max_length=80),
    user_id: str = Depends(require_authenticated_user),
):
    _require_supabase()
    try:
        async with httpx.AsyncClient(timeout=20) as client:
            return await plan_ops.find_alternatives(client, user_id, meal_plan_id, sort, limit=8, query=q)
    except plan_ops.PlanChangeError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except (db.SupabaseError, httpx.HTTPError) as exc:
        raise HTTPException(status_code=502, detail="Could not load alternatives.") from exc


@router.post("/{meal_plan_id}/swap")
async def swap(meal_plan_id: str, body: SwapRequest, user_id: str = Depends(require_authenticated_user)):
    _require_supabase()
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            result = await plan_ops.apply_swaps(
                client,
                user_id,
                [{"meal_plan_id": meal_plan_id, "to_code": body.recipe_code, "from_code": body.from_code}],
                source="app",
            )
            # Any open Ask Annora suggestion was made against the old plan.
            await assistant_store.expire_open_proposals(client, user_id)
            return result
    except plan_ops.PlanChangeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except (db.SupabaseError, httpx.HTTPError) as exc:
        raise HTTPException(status_code=502, detail="Could not swap this meal. Please try again.") from exc
