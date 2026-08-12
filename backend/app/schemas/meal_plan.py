from datetime import date
from pydantic import BaseModel, Field


class MealPlanningContext(BaseModel):
    user_id: str
    family_size: int | None = None
    monthly_budget: float | None = None
    dietary_preference: str | None = None
    dietary_goals: list[str] = Field(default_factory=list)
    dietary_exclusions: list[str] = Field(default_factory=list)


class GeneratedIngredient(BaseModel):
    name: str = Field(min_length=1)
    quantity: float = Field(gt=0)
    unit: str = Field(min_length=1)


class GeneratedMeal(BaseModel):
    type: str = Field(pattern="^(breakfast|lunch|dinner|snack)$")
    name: str = Field(min_length=1)
    description: str | None = None
    prep_time_minutes: int | None = Field(default=None, ge=0)
    nutrition: dict = Field(default_factory=dict)
    ingredients: list[GeneratedIngredient] = Field(default_factory=list)


class GeneratedDay(BaseModel):
    date: date
    meals: list[GeneratedMeal] = Field(min_length=1)


class GeneratedMealPlan(BaseModel):
    days: list[GeneratedDay] = Field(min_length=7, max_length=7)
