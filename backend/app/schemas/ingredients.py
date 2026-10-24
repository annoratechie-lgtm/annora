from datetime import date
from decimal import Decimal
from uuid import UUID
from pydantic import BaseModel, Field


class IngredientItem(BaseModel):
    meal_id: UUID
    meal_type: str = Field(min_length=1)
    source_recipe_code: str = Field(min_length=1)
    food_code_org: str = Field(min_length=1)
    food_name: str = Field(min_length=1)
    amount: Decimal = Field(gt=0)
    unit: str = Field(min_length=1)


class GeneratedIngredients(BaseModel):
    ingredients: list[IngredientItem]
