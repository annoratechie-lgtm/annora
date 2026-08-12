from datetime import date, timedelta
from typing import Annotated

import httpx
from fastapi import APIRouter, Header, HTTPException, status
from pydantic import BaseModel, Field

from app.core.config import settings

router = APIRouter(prefix="/meal-plans", tags=["meal-plans"])


class GenerateMealPlanRequest(BaseModel):
    start_date: date | None = None

    model: str | None = Field(
        default=None,
        description="Optional LLM model override for development/testing.",
    )


class GenerateMealPlanResponse(BaseModel):
    status: str
    message: str
    start_date: date
    end_date: date
    days: int = 7


class MealPlanningContext(BaseModel):
    user_id: str
    family_size: int | None = None
    monthly_budget: float | None = None
    dietary_preference: str | None = None
    dietary_goals: list[str] = Field(default_factory=list)
    dietary_exclusions: list[str] = Field(default_factory=list)


async def _get_authenticated_user_id(authorization: str | None) -> str:
    """Validate the Supabase access token and return the authenticated user id."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Bearer access token.",
        )

    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Supabase backend configuration is missing.",
        )

    token = authorization.split(" ", 1)[1].strip()
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Bearer access token.",
        )

    try:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.get(
                f"{settings.supabase_url.rstrip('/')}/auth/v1/user",
                headers={
                    "apikey": settings.supabase_service_role_key,
                    "Authorization": f"Bearer {token}",
                },
            )
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Could not reach Supabase Auth.",
        ) from exc

    if response.status_code != 200:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired access token.",
        )

    user = response.json()
    user_id = user.get("id")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authenticated user id was not returned by Supabase.",
        )

    return user_id


async def _load_planning_context(user_id: str) -> MealPlanningContext:
    """Read only the onboarding data needed for the first meal-planning version."""
    base_headers = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
    }
    base_url = settings.supabase_url.rstrip("/")

    try:
        async with httpx.AsyncClient(timeout=10) as client:
            profile_response = await client.get(
                f"{base_url}/rest/v1/onboarding_profiles",
                params={
                    "select": "family_size,monthly_budget,dietary_preference,dietary_goals",
                    "user_id": f"eq.{user_id}",
                    "limit": "1",
                },
                headers=base_headers,
            )
            exclusions_response = await client.get(
                f"{base_url}/rest/v1/dietary_exclusions",
                params={
                    "select": "ingredient_name",
                    "user_id": f"eq.{user_id}",
                    "order": "ingredient_name.asc",
                },
                headers=base_headers,
            )
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Could not reach Supabase.",
        ) from exc

    if profile_response.status_code != 200 or exclusions_response.status_code != 200:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Could not load meal-planning data from Supabase.",
        )

    profiles = profile_response.json()
    if not profiles:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Onboarding profile not found.",
        )

    profile = profiles[0]
    exclusions = exclusions_response.json()

    goals = profile.get("dietary_goals") or []
    if isinstance(goals, str):
        goals = [goals]

    return MealPlanningContext(
        user_id=user_id,
        family_size=profile.get("family_size"),
        monthly_budget=profile.get("monthly_budget"),
        dietary_preference=profile.get("dietary_preference"),
        dietary_goals=goals,
        dietary_exclusions=[row["ingredient_name"] for row in exclusions],
    )


@router.post("/generate", response_model=GenerateMealPlanResponse, status_code=202)
async def generate_meal_plan(
    request: GenerateMealPlanRequest,
    authorization: Annotated[str | None, Header()] = None,
):
    """Start the first 7-day meal-plan generation flow.

    The endpoint intentionally does not accept onboarding fields from the client.
    It derives planning context from the authenticated user's Supabase records.
    The LLM provider is the next implementation step; until configured, this
    endpoint returns a clear 503 instead of generating fake meal data.
    """
    user_id = await _get_authenticated_user_id(authorization)
    await _load_planning_context(user_id)

    start_date = request.start_date or date.today()
    end_date = start_date + timedelta(days=6)

    if not settings.llm_api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="LLM provider is not configured yet. Meal generation is not available.",
        )

    # The validated planning context and provider call will be implemented next.
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail=(
            "Meal-plan generation provider is not implemented yet. "
            "The endpoint and authenticated planning context are ready."
        ),
    )
