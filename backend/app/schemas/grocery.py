from pydantic import BaseModel, Field


class GroceryItem(BaseModel):
    ingredient_name: str = Field(min_length=1)
    required_quantity: float = Field(gt=0)
    purchase_quantity: float = Field(gt=0)
    unit: str = Field(min_length=1)
    category: str | None = None
    is_purchased: bool = False
    is_urgent: bool = False


class GroceryListResponse(BaseModel):
    grocery_list_id: str
    meal_id: str
    item_count: int = Field(ge=0)
    items: list[GroceryItem]
