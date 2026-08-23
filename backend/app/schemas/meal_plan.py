from datetime import date

from pydantic import BaseModel, Field


class MealPlanningContext(BaseModel):
    user_id: str
    family_size: int | None = None
    monthly_budget: float | None = None
    dietary_preference: str
    dietary_goals: list[str] = Field(default_factory=list)
    dietary_exclusions: list[str] = Field(default_factory=list)


class DailyMeals(BaseModel):
    # The API/LLM contract uses arrays, while the current database schema
    # permits one meal per meal type per date.
    breakfast: list[str] = Field(min_length=1, max_length=1)
    lunch: list[str] = Field(min_length=1, max_length=1)
    dinner: list[str] = Field(min_length=1, max_length=1)


class GeneratedMealPlan(BaseModel):
    days: dict[date, DailyMeals]

    @property
    def sorted_dates(self) -> list[date]:
        return sorted(self.days)
