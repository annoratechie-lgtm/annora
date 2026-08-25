import asyncio
from app.api.v1.meal_plans import generate_meal_plan, GenerateMealPlanRequest

user_id = '97fe4f67-de72-40cc-9997-a7187b78d9e4'
dietary_preference = 'vegetarian'

async def test_recipe_database(dietary_preference):
    from app.services.meal_planner import _load_recipe_reference
    recipes = await _load_recipe_reference(dietary_preference)
    return recipes

async def test_meal_api(user_id=user_id):
    request = GenerateMealPlanRequest(user_id=user_id)
    recipes = await generate_meal_plan(request)
    return recipes

# recipe = asyncio.run(test_meal_api())
recipe = asyncio.run(test_recipe_database(dietary_preference))
print(recipe)
