import json
import httpx
from fastapi import APIRouter, HTTPException, status
from groq import Groq

from app.core.config import settings


class IngredientPlannerError(RuntimeError):
    pass


async def generate_ingredients(meal_plan_id: str) -> dict:
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Supabase backend configuration is missing.",
        )

    headers = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    base_url = settings.supabase_url.rstrip("/")
    try:
        async with httpx.AsyncClient(timeout=20) as client:
            ingredient_response = await client.post(
                            f"{base_url}/rest/v1/rpc/get_meal_plan_ingredients",
                            json={
                                "p_meal_plan_id": meal_plan_id},
                            headers=headers,
                        )
        content = ingredient_response.json()
    except Exception as exc:
        raise IngredientPlannerError(f"Could not reach Supabase to load meals for meal plan {meal_plan_id}.") from exc

    
    if not content:
        raise IngredientPlannerError("Groq returned an empty ingredient response.")

    return content
