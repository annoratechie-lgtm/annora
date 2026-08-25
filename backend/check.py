import asyncio
from app.api.v1.meal_plans import generate_meal_plan, GenerateMealPlanRequest
from app.api.v1.ingredients import generate_meal_plan_ingredients

user_id = 'ee4ea15d-30bd-4862-aeeb-3789dced8254'
meal_plan_id = 'ca39e1d5-edeb-4175-86cd-f41920f9d1ef'
dietary_preference = 'vegetarian'

async def test_recipe_database(dietary_preference):
    from app.services.meal_planner import _load_recipe_reference
    recipes = await _load_recipe_reference(dietary_preference)
    return recipes

async def test_meal_api(user_id=user_id):
    request = GenerateMealPlanRequest(user_id=user_id)
    recipes = await generate_meal_plan(request)
    return recipes

async def test_ingredients_api(meal_plan_id=meal_plan_id, user_id=user_id):
    ingredients = await generate_meal_plan_ingredients(meal_plan_id, user_id)
    return ingredients

# recipe = asyncio.run(test_meal_api())
# recipe = asyncio.run(test_recipe_database(dietary_preference))
response = asyncio.run(test_ingredients_api(meal_plan_id, user_id))
print(response)
