from datetime import date
from pydantic import BaseModel, Field


class MealPlanningContext(BaseModel):
    user_id: str
    family_size: int | None = None
    monthly_budget: float | None = None
    dietary_preference: str | None = None
    dietary_goals: list[str] = Field(default_factory=list)
    dietary_exclusions: list[str] = Field(default_factory=list)

class mealPlan(BaseModel):
    meal_date: str
    breakfast: str 
    lunch: list[str] = Field(..., 
                             description="Lunch meal name. Add Roti or Rice if the main course is a curry.",
                             examples=[["BFP208, ASC096"], ["ASC226, ASC113"]])
    dinner: list[str] = Field(..., 
                              description="Dinner meal name. Add Roti or Rice if the main course is a curry.",
                              examples=[["ASC224, ASC096"], ["OSR139, ASC113"]])

class mealPlanResponse(BaseModel):
    recipes: list[mealPlan] = Field(..., description="Meal plan for the 7 days, with each day containing breakfast, lunch, and dinner meal names.")

