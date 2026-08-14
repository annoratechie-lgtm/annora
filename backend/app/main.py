from fastapi import FastAPI

from app.api.v1 import health, meal_plans, ingredients
from app.core.config import settings

app = FastAPI(
    title="Annora Backend",
    version="0.2.0",
    description=(
        "Backend services for Annora. Meal planning is authenticated server-side; "
        "onboarding reads/writes continue directly from Flutter to Supabase."
    ),
)

app.include_router(health.router, prefix="/api/v1")
app.include_router(meal_plans.router, prefix="/api/v1")
app.include_router(ingredients.router, prefix="/api/v1")


@app.get("/")
def root():
    return {"service": "annora-backend", "environment": settings.environment}
