from datetime import date, timedelta
import json
import os
from pydantic import BaseModel, Field
from groq import Groq
import instructor
import asyncio
from app.api.v1.meal_plans import generate_meal_plan, GenerateMealPlanRequest

class MealPlan(BaseModel):
    meal_date: str
    breakfast: str
    lunch: list[str]
    dinner: list[str]


class MealPlanResponse(BaseModel):
    recipes: list[MealPlan]

client = instructor.from_groq(Groq(api_key=os.environ["GROQ_API_KEY"]), mode=instructor.Mode.JSON)

result = client.chat.completions.create(
    model="openai/gpt-oss-20b",
    messages=[
        {
            "role": "system",
            "content": """
Return a 7-day meal plan.

Return exactly 7 records.

Each record must contain:
- meal_date
- breakfast
- lunch
- dinner

meal_date must be DD-MM-YYYY.
breakfast must be a string.
lunch must be an array of strings.
dinner must be an array of strings.
"""
        },
        {
            "role": "user",
            "content": """
Dates:
23-08-2026
24-08-2026
25-08-2026
26-08-2026
27-08-2026
28-08-2026
29-08-2026

Breakfast recipes:
Poha
Upma
Idli

Main course recipes:
Palak Paneer
Dal Tadka
Rajma

Staple recipes:
Roti
Rice
"""
        }
    ],
    response_model=MealPlanResponse,
)

print(result)