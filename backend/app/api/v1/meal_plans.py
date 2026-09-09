from datetime import date
import httpx
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel
from app.core.config import settings
from app.schemas.meal_plan import MealPlanningContext
from app.services.meal_plan_repository import MealPlanRepositoryError, save_meal_plan
from app.services.meal_planner import generate_meal_plan as run_llm_meal_plan

router = APIRouter(prefix="/meal-plans", tags=["meal-plans"])
bearer_scheme = HTTPBearer(auto_error=False)


class GenerateMealPlanRequest(BaseModel):
    user_id: str
    start_date: date | None = None
    
GeneratedMealPlan = dict[str, dict[str, str | list[str]]]

class GenerateMealPlanResponse(BaseModel):
    status: str
    message: str
    meal_id: str
    plan: GeneratedMealPlan


async def _get_authenticated_user_id(
    request_user_id: str,
    credentials: HTTPAuthorizationCredentials | None,
) -> str:
    """Use the requested user id in development; validate a Supabase token otherwise."""
    if settings.environment.lower() == "development":
        return request_user_id

    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Bearer access token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Supabase backend configuration is missing.",
        )

    token = credentials.credentials.strip()
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Bearer access token.",
            headers={"WWW-Authenticate": "Bearer"},
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
            headers={"WWW-Authenticate": "Bearer"},
        )

    authenticated_user_id = response.json().get("id")
    if not authenticated_user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authenticated user id was not returned by Supabase.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if authenticated_user_id != request_user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Authenticated user does not match requested user_id.",
        )

    return authenticated_user_id


async def _load_planning_context(user_id: str) -> MealPlanningContext:
    """Read only the onboarding data needed for meal generation."""
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
    goals = profile.get("dietary_goals") or []
    if isinstance(goals, str):
        goals = [goals]

    return MealPlanningContext(
        user_id=user_id,
        family_size=profile.get("family_size"),
        monthly_budget=profile.get("monthly_budget"),
        dietary_preference=profile.get("dietary_preference"),
        dietary_goals=goals,
        dietary_exclusions=[row["ingredient_name"] for row in exclusions_response.json()],
    )


@router.post("/generate", response_model=GenerateMealPlanResponse)
async def generate_meal_plan(
    request: GenerateMealPlanRequest,
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
):
    """Generate a 7-day meal plan with LLM and persist it in Supabase."""
    user_id = await _get_authenticated_user_id(request.user_id, credentials)
    context = await _load_planning_context(user_id)
    start_date = request.start_date or date.today()

    if not settings.grokapi or not settings.llm_model:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Groq provider is not configured.",
        )

    try:
        plan = await run_llm_meal_plan(context, start_date)
        meal_id = await save_meal_plan(user_id, start_date, plan)
    except (RuntimeError, MealPlanRepositoryError) as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc

    return GenerateMealPlanResponse(
        status="active",
        message="7-day meal plan generated and saved successfully.",
        meal_id=meal_id,
        plan=plan,
    )
