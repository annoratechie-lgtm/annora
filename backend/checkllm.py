from datetime import date, timedelta
import json
import os
from pydantic import BaseModel, Field
from groq import Groq
import instructor
import asyncio
from openai import OpenAI
from google import genai

client = instructor.from_groq(Groq(api_key=os.environ["GROQ_API_KEY"]), mode=instructor.Mode.JSON)
model = "openai/gpt-oss-20b"
# model = "qwen/qwen3.6-27b"
# model = "gemini-3.5-flash-lite"
dietary_preference = 'vegetarian'

async def test_recipe_database(dietary_preference):
    from app.services.meal_planner import _load_recipe_reference
    recipes = await _load_recipe_reference(dietary_preference)
    return recipes

recipe = asyncio.run(test_recipe_database(dietary_preference))
breakfast_recipes = [r.get("recipe_name") for r in recipe if r.get("category") == "breakfast"]
main_course = [r.get("recipe_name") for r in recipe if r.get("category") == "main_course"]
staple_recipes = [r.get("recipe_name") for r in recipe if r.get("category") == "staple"]
recipes = {'breakfast': breakfast_recipes, 'main_course': main_course, 'staple': staple_recipes}

dates = ['23-08-2026','24-08-2026','25-08-2026','26-08-2026','27-08-2026','28-08-2026','29-08-2026']


class mealPlan(BaseModel):
    meal_date: str
    breakfast: str 
    lunch: list[str] = Field(..., 
                             description="Lunch meal name. Add Roti or Rice if the main course is a curry.",
                             examples=[["Chicken Curry, Roti"], ["Paneer Butter Masala, Rice"]])
    dinner: list[str] = Field(..., 
                              description="Dinner meal name. Add Roti or Rice if the main course is a curry.",
                              examples=[["Beef Curry, Roti"], ["Dal Tadka, Rice"]])

class mealPlanResponse(BaseModel):
    recipes: list[mealPlan] = Field(..., description="Meal plan for the 7 days, with each day containing breakfast, lunch, and dinner meal names.")

system_prompt = f"""
You are Annora's household meal-planning engine.

Create a practical 7-day meal plan for the household context provided.

HARD RECIPE RULES — FOLLOW EXACTLY:

1. Every breakfast, lunch, and dinner MUST be selected from the input JSON RECIPE REFERENCE.
2. Use the exact `recipe_name` value from the RECIPE REFERENCE.
3. Do not invent, rename, paraphrase, combine, modify, or derive recipe names.
4. If a recipe does not exist in the RECIPE REFERENCE, you MUST NOT use it.
5. Dietary preferences, goals, exclusions, family size, and budget are filters over
   available recipes; they do not permit creating a new recipe.
6. Do not repeat the same recipe for breakfast, lunch, or dinner on consecutive days.
7. If a main course is a curry, add exactly one staple (Roti or Rice) to the meal.
8. If the main course is not a curry, do not add a staple.
9. Every recipe name must exactly match a `recipe_name` from the input reference.

OUTPUT RULES:

1. Return exactly 7 meal-plan records.
2. The dates MUST be exactly:
   {", ".join(dates)}
3. Each record must contain:
   - meal_date
   - breakfast
   - lunch
   - dinner
4. breakfast must contain exactly one recipe name.
5. lunch must contain the selected main course and, when required, exactly one staple.
6. dinner must contain the selected main course and, when required, exactly one staple.
7. Do not return any recipe that is not present in the recipe reference.
8. Do not return markdown or explanations.
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