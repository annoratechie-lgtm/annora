import asyncio
from app.api.v1.meal_plans import generate_meal_plan, GenerateMealPlanRequest
from app.api.v1.ingredients import generate_meal_plan_ingredients
from app.api.v1.grocery_lists import generate_grocery_list

user_id = 'ee4ea15d-30bd-4862-aeeb-3789dced8254'
meal_id = '2ee226f5-3d9c-4998-9914-1db99eaa7f39'
dietary_preference = 'vegetarian'

async def test_recipe_database(dietary_preference):
    from app.services.meal_planner import _load_recipe_reference
    recipes = await _load_recipe_reference(dietary_preference)
    return recipes

async def test_meal_api(user_id=user_id):
    request = GenerateMealPlanRequest(user_id=user_id)
    recipes = await generate_meal_plan(request)
    return recipes

async def test_ingredients_api(meal_id=meal_id, user_id=user_id):
    ingredients = await generate_meal_plan_ingredients(meal_id, user_id)
    return ingredients

async def test_grocery_list_api(meal_id=meal_id, user_id=user_id):
    grocery_list = await generate_grocery_list(meal_id, user_id)
    return grocery_list

# response = asyncio.run(test_meal_api(user_id))
# recipe = asyncio.run(test_recipe_database(dietary_preference))
# response = asyncio.run(test_ingredients_api(meal_id, user_id))
response = asyncio.run(test_grocery_list_api(meal_id, user_id))
print(response)
