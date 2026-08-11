from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/health")
def health_check():
    """
    Confirms the backend process is up. Used for local sanity checks now,
    and by uptime/CI checks later. Deliberately has no dependency on
    Supabase or any other service -- if this fails, the process itself is broken.
    """
    return {"status": "ok"}
