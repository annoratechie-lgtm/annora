import re
from typing import Any

import httpx
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.core.auth import AuthenticatedUser, require_authenticated_user_details
from app.core.config import settings

router = APIRouter(prefix="/users", tags=["users"])
_PHONE_NUMBER = re.compile(r"^\+?[0-9\s()-]{7,20}$")
_PROFILE_COLUMNS = "user_id,name,email,phone,photo_uploaded"


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


def _supabase_headers() -> dict[str, str]:
    return {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "Content-Type": "application/json",
    }


def _decode_profile_rows(response: httpx.Response, action: str) -> list[dict[str, Any]]:
    if response.status_code != status.HTTP_200_OK:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Could not {action} user profile ({response.status_code}).",
        )
    try:
        rows = response.json()
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Supabase returned an invalid user profile response.",
        ) from exc
    if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Supabase returned an invalid user profile response.",
        )
    return rows


async def _sync_profile_row(
    user: AuthenticatedUser,
    *,
    name: str | None,
    phone: str | None,
) -> dict[str, Any]:
    base_url = settings.supabase_url.rstrip("/")
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.post(
                f"{base_url}/rest/v1/rpc/sync_user_profile",
                headers=_supabase_headers(),
                json={
                    "p_user_id": user.id,
                    "p_name": name,
                    "p_email": user.email,
                    "p_phone": phone,
                },
            )
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Could not reach Supabase.",
        ) from exc

    rows = _decode_profile_rows(response, "save")
    if not rows:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Supabase did not return the saved user profile.",
        )
    return rows[0]


@router.get("/me/profile")
async def get_my_profile(
    user: AuthenticatedUser = Depends(require_authenticated_user_details),
) -> dict[str, Any]:
    """Return the signed-in user's profile, creating it for existing accounts."""
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Supabase backend configuration is missing.",
        )

    base_url = settings.supabase_url.rstrip("/")
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.get(
                f"{base_url}/rest/v1/users",
                params={
                    "select": _PROFILE_COLUMNS,
                    "user_id": f"eq.{user.id}",
                    "limit": "1",
                },
                headers=_supabase_headers(),
            )
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Could not reach Supabase.",
        ) from exc

    rows = _decode_profile_rows(response, "load")
    if rows:
        return rows[0]

    return await _sync_profile_row(
        user,
        name=_profile_name(user),
        phone=(
            user.user_metadata.get("contact_phone")
            if isinstance(user.user_metadata.get("contact_phone"), str)
            else None
        ),
    )


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

    return await _sync_profile_row(
        user,
        name=(
            request.name
            if "name" in request.model_fields_set
            else _profile_name(user)
        ),
        phone=(
            request.phone
            if "phone" in request.model_fields_set
            else (
                user.user_metadata.get("contact_phone")
                if isinstance(user.user_metadata.get("contact_phone"), str)
                else None
            )
        ),
    )
