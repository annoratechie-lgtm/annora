from pydantic import BaseModel, Field


class IngredientItem(BaseModel):
    ingredient_name: str = Field(min_length=1)
    quantity: float = Field(gt=0)
    unit: str = Field(min_length=1)


class MealIngredients(BaseModel):
    meal_id: str
    ingredients: list[IngredientItem] = Field(min_length=1)


class GeneratedIngredients(BaseModel):
    meals: list[MealIngredients] = Field(min_length=1)
