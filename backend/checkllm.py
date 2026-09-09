from datetime import date, timedelta
import json
import os
from pydantic import BaseModel, Field
from groq import Groq
import instructor
import asyncio
from openai import OpenAI
from google import genai
from app.core.config import settings

client = instructor.from_groq(Groq(api_key=settings.grokapi), mode=instructor.Mode.JSON)
model = "openai/gpt-oss-20b"
# model = "qwen/qwen3.6-27b"
# model = "gemini-3.5-flash-lite"
dietary_preference = 'vegetarian'

async def test_recipe_database(dietary_preference):
    from app.services.meal_planner import _load_recipe_reference
    recipes = await _load_recipe_reference(dietary_preference)
    return recipes

recipe_reference = asyncio.run(test_recipe_database(dietary_preference))
breakfast_recipes = [f'{r.get("recipe_name")}-{r.get("source_recipe_code")}' for r in recipe_reference if r.get("category") == "breakfast"]
main_course = [f'{r.get("recipe_name")}-{r.get("source_recipe_code")}' for r in recipe_reference if r.get("category") == "main_course"]
staple_recipes = [f'{r.get("recipe_name")}-{r.get("source_recipe_code")}'  for r in recipe_reference if r.get("category") == "staple"]
recipes = {'breakfast': breakfast_recipes, 'main_course': main_course, 'staple': staple_recipes}


dates = ['23-08-2026','24-08-2026','25-08-2026','26-08-2026','27-08-2026','28-08-2026','29-08-2026']


class mealPlan(BaseModel):
    meal_date: str
    breakfast: str = Field(..., description="source_recipe_code for breakfast recipe", examples=["BFP208"])
    lunch: list[str] = Field(..., 
                             description="List of source_recipe_codes.If the main course is a curry, this MUST contain exactly the curry code plus exactly one staple code",
                             examples=[["BFP208, ASC096"], ["ASC226, ASC113"]])
    dinner: list[str] = Field(..., 
                              description="List of source_recipe_codes.If the main course is a curry, this MUST contain exactly the curry code plus exactly one staple code",
                              examples=[["ASC224, ASC096"], ["OSR139, ASC113"]])

class mealPlanResponse(BaseModel):
    recipes: list[mealPlan] = Field(..., description="Meal plan for the 7 days, with each day containing breakfast, lunch, and dinner meal names.")

system_prompt = f"""
You are Annora's household meal-planning engine.

Create a practical 7-day Indian household meal plan using ONLY recipes from the RECIPE REFERENCE.

CRITICAL:
- You may ONLY select source_recipe_code values present in RECIPE REFERENCE.
- Never output recipe_name.
- Never invent a source_recipe_code.
- Never modify a source_recipe_code.
- The final answer must contain ONLY source_recipe_code values for meals.

MEAL STRUCTURE:

BREAKFAST:
- Exactly 1 source_recipe_code.

LUNCH:
- If the selected recipe is a complete non-curry dish, return exactly 1 source_recipe_code.
- If the selected recipe is a curry/main-course curry/gravy, return exactly 2 source_recipe_codes:
  1. exactly 1 curry/main-course recipe
  2. exactly 1 staple recipe
- Never return more than 2 codes.
- Never return more than 1 staple.

DINNER:
- If the selected recipe is a complete non-curry dish, return exactly 1 source_recipe_code.
- If the selected recipe is a curry/main-course curry/gravy, return exactly 2 source_recipe_codes:
  1. exactly 1 curry/main-course recipe
  2. exactly 1 staple recipe
- Never return more than 2 codes.
- Never return more than 1 staple.

IMPORTANT:
A curry MUST NEVER be served alone.

Example:
If the curry code is C123 and the roti code is S001:
["C123", "S001"]

If the curry code is C123 and rice code is S002:
["C123", "S002"]

Do NOT output:
["C123"]

BREAKFAST:
["B001"]

This is WRONG:
["Paneer Butter Masala", "Roti"]

This is CORRECT:
["C123", "S001"]

REPETITION:
- Do not use the same recipe on consecutive days for breakfast.
- Do not use the same recipe on consecutive days for lunch.
- Do not use the same recipe on consecutive days for dinner.

DATES:
{", ".join(dates)}

Return exactly 7 records.

Each record must contain:
- meal_date
- breakfast
- lunch
- dinner

OUTPUT ONLY JSON matching the provided response schema.
Do not return recipe names.
Do not return explanations.
""".strip()

result = response, completion = client.chat.completions.create_with_completion(
    model=model,
    messages=[
        {"role": "system","content": system_prompt},
        {"role": "user","content": json.dumps(recipes)}
    ],
    response_model=mealPlanResponse,
    max_tokens=4096,
)

content = json.loads(response.model_dump_json(indent=2))

def format_meal_plan_output(recipes):
    formatted_output = {}
    for recipe in recipes['recipes']:
        formatted_output[recipe.get('meal_date')] = {
            "breakfast": recipe.get('breakfast'),
            "lunch": recipe.get('lunch'),
            "dinner": recipe.get('dinner')
        }
    return formatted_output

recipes = format_meal_plan_output(content)
print(json.dumps(recipes, indent=2))