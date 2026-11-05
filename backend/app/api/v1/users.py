import re
from typing import Any

import httpx
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.core.auth import AuthenticatedUser, require_authenticated_user_details
from app.core.config import settings

router = APIRouter(prefix="/users", tags=["users"])
_PHONE_NUMBER = re.compile(r"^\+?[0-9\s()-]{7,20}$")


class UserProfileUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str | None = Field(default=None, max_length=120)
    phone: str | None = Field(default=None, max_length=20)

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        return cleaned or None

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, value: str | None) -> str | None:
        if value is None or not value.strip():
            return None
        cleaned = value.strip()
        if not _PHONE_NUMBER.fullmatch(cleaned):
            raise ValueError("Enter a valid phone number.")
        return cleaned


def _profile_name(user: AuthenticatedUser) -> str | None:
    for key in ("full_name", "name", "display_name"):
        value = user.user_metadata.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    if user.email:
        return user.email.split("@", 1)[0]
    return None


@router.put("/me/profile")
async def upsert_my_profile(
    request: UserProfileUpdate,
    user: AuthenticatedUser = Depends(require_authenticated_user_details),
) -> dict[str, Any]:
    """Create or update the signed-in user's public profile row."""
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Supabase backend configuration is missing.",
        )

    profile_data: dict[str, Any] = {
        "user_id": user.id,
        "name": _profile_name(user),
        "email": user.email,
    }
    if "name" in request.model_fields_set:
        profile_data["name"] = request.name
    if "phone" in request.model_fields_set:
        profile_data["phone"] = request.phone

    base_url = settings.supabase_url.rstrip("/")
    headers = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates,return=representation",
    }
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.post(
                f"{base_url}/rest/v1/users",
                params={"on_conflict": "user_id"},
                headers=headers,
                json=profile_data,
            )
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Could not reach Supabase.",
        ) from exc

    if response.status_code not in (200, 201):
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Could not save user profile ({response.status_code}).",
        )

    try:
        rows = response.json()
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Supabase returned an invalid user profile response.",
        ) from exc

    if not isinstance(rows, list) or not rows or not isinstance(rows[0], dict):
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Supabase did not return the saved user profile.",
        )
    return rows[0]
