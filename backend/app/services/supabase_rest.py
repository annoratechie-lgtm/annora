"""Thin helpers for Supabase PostgREST calls made with the service role key.

Every caller must scope its filters to the authenticated user; the service role
bypasses row level security.
"""

from typing import Any

import httpx

from app.core.config import settings


class SupabaseError(RuntimeError):
    pass


def configured() -> bool:
    return bool(settings.supabase_url and settings.supabase_service_role_key)


def _url(path: str) -> str:
    return f"{settings.supabase_url.rstrip('/')}/rest/v1/{path}"


def headers(prefer: str | None = None) -> dict[str, str]:
    if not configured():
        raise SupabaseError("Supabase backend configuration is missing.")
    result = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    if prefer:
        result["Prefer"] = prefer
    return result


def _check(action: str, response: httpx.Response) -> None:
    if response.status_code >= 400:
        raise SupabaseError(f"{action} failed ({response.status_code}): {response.text[:300]}")


async def select(client: httpx.AsyncClient, table: str, params: dict[str, str]) -> list[dict[str, Any]]:
    response = await client.get(_url(table), params=params, headers=headers())
    _check(f"Reading {table}", response)
    rows = response.json()
    if not isinstance(rows, list):
        raise SupabaseError(f"Supabase returned an invalid result for {table}.")
    return rows


async def insert(client: httpx.AsyncClient, table: str, rows: dict | list[dict]) -> list[dict[str, Any]]:
    response = await client.post(_url(table), json=rows, headers=headers("return=representation"))
    _check(f"Saving {table}", response)
    return response.json() if response.content else []


async def update(client: httpx.AsyncClient, table: str, filters: dict[str, str], data: dict) -> list[dict[str, Any]]:
    response = await client.patch(_url(table), params=filters, json=data, headers=headers("return=representation"))
    _check(f"Updating {table}", response)
    return response.json() if response.content else []


async def delete(client: httpx.AsyncClient, table: str, filters: dict[str, str]) -> None:
    if not filters:
        raise SupabaseError("Refusing to delete without a filter.")
    response = await client.delete(_url(table), params=filters, headers=headers("return=minimal"))
    _check(f"Deleting from {table}", response)


async def rpc(client: httpx.AsyncClient, function: str, payload: dict) -> Any:
    response = await client.post(_url(f"rpc/{function}"), json=payload, headers=headers())
    _check(f"Calling {function}", response)
    return response.json() if response.content else None
