from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1 import health, meal_plans, ingredients, grocery_lists, read_apis
from app.core.config import settings

app = FastAPI(
    title="Annora Backend",
    version="0.2.0",
    description=(
        "Backend services for Annora. Meal planning is authenticated server-side; "
        "onboarding reads/writes continue directly from Flutter to Supabase."
    ),
)

# Flutter Web uses a separate development origin from FastAPI. The port can vary
# by launch command, so allow localhost origins on any port during development.
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"^http://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_origins=[
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "http://localhost:7357",
        "http://127.0.0.1:7357",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router, prefix="/api/v1")
app.include_router(meal_plans.router, prefix="/api/v1")
app.include_router(ingredients.router, prefix="/api/v1")
app.include_router(grocery_lists.router, prefix="/api/v1")
app.include_router(read_apis.router, prefix="/api/v1")


@app.get("/")
def root():
    return {"service": "annora-backend", "environment": settings.environment}
