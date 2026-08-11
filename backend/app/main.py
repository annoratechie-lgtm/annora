from fastapi import FastAPI

from app.api.v1 import health
from app.core.config import settings

app = FastAPI(
    title="Annora Backend",
    version="0.1.0",
    description="Backend services for Annora. Milestone 1 only exposes a health check "
    "-- onboarding reads/writes go directly to Supabase from the Flutter app.",
)

app.include_router(health.router, prefix="/api/v1")


@app.get("/")
def root():
    return {"service": "annora-backend", "environment": settings.environment}
