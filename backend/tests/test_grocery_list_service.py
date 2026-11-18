import pytest

from app.services.grocery_list_service import (
    GroceryListError,
    aggregate_ingredients,
    carry_over_purchased,
    category_for,
    display_name,
)


def row(name, amount, unit):
    return {"food_name": name, "amount": amount, "unit": unit}


def by_name(items):
    return {i["ingredient_name"]: i for i in items}


def test_display_names_read_like_a_shopping_list():
    assert display_name("Onion, big (Allium cepa)") == "Onion"
    assert display_name("Wheat flour, atta (Triticum aestivum)") == "Atta"
    assert display_name("Oil, sunflower") == "Sunflower oil"
    assert display_name("AJWAIN SEED WHOLE ORGANIC SPICES") == "Ajwain"
    assert display_name("Spinach (Spinacia oleracea)") == "Spinach"
    assert display_name("Paneer") == "Paneer"
    assert display_name("Cauliflower") == "Cauliflower"


def test_categories():
    assert category_for("Onion") == "Vegetables & herbs"
    assert category_for("Green chillies") == "Vegetables & herbs"
    assert category_for("Coriander leaves") == "Vegetables & herbs"
    assert category_for("Paneer") == "Dairy"
    assert category_for("Besan (gram flour)") == "Grains & flours"
    assert category_for("Rice") == "Grains & flours"
    assert category_for("Toor dal") == "Dals & pulses"
    assert category_for("Kabuli chana") == "Dals & pulses"
    assert category_for("Sunflower oil") == "Pantry"
    assert category_for("Coriander seeds") == "Pantry"
    assert category_for("Chilli powder") == "Pantry"
    assert category_for("Coconut milk") == "Pantry"


def test_merges_units_drops_water_scales_and_rounds():
    items = by_name(aggregate_ingredients([
        row("Onion, big (Allium cepa)", 400, "g"),
        row("Onion, big (Allium cepa)", 310, "g"),
        row("Oil, sunflower", 2, "tbsp"),       # 30 ml
        row("Oil, sunflower", 4, "tsp"),        # 20 ml
        row("Oil, sunflower", 30, "g"),         # merged into the larger measure
        row("Water, distilled", 1455, "ml"),
        row("Garlic, small clove (Allium sativum)", 11, "g"),
        row("Coriander leaves (Coriandrum sativum)", 5, "sprig"),
        row("Salt", 1, ""),                     # empty unit used to crash the whole list
    ], household_size=4))

    assert "Water" not in items
    onion = items["Onion"]
    assert onion["required_quantity"] == 2840          # 710 g x 4 people
    assert (onion["purchase_quantity"], onion["unit"]) == (3.0, "kg")  # rounded up to 250 g steps
    assert items["Garlic"]["purchase_quantity"] == 50 and items["Garlic"]["unit"] == "g"  # 44 g -> 50 g
    oil = items["Sunflower oil"]
    assert oil["required_quantity"] == 320 and oil["category"] == "Pantry"  # (30+20+30) x 4
    assert items["Coriander leaves"]["unit"] == "sprig" and items["Coriander leaves"]["purchase_quantity"] == 20
    assert items["Salt"]["unit"] == "piece"
    # Fresh produce first, pantry staples last.
    names = [i["ingredient_name"] for i in aggregate_ingredients([row("Salt", 1, "tsp"), row("Paneer", 100, "g"), row("Onion, big", 100, "g")])]
    assert names == ["Onion", "Paneer", "Salt"]


def test_rebuild_keeps_ticked_items():
    items = aggregate_ingredients([row("Paneer", 265, "g"), row("Rice, parboiled, milled", 700, "g")])
    carry_over_purchased(items, {"rice"})
    assert by_name(items)["Rice"]["is_purchased"] is True
    assert by_name(items)["Paneer"]["is_purchased"] is False


def test_nothing_to_buy_is_an_error():
    with pytest.raises(GroceryListError):
        aggregate_ingredients([row("Water, distilled", 100, "ml")])


def test_spoons_of_dry_things_become_grams_and_liquids_stay_ml():
    items = by_name(aggregate_ingredients([
        row("Cumin seeds (Cuminum cyminum)", 1, "tsp"),     # 5 ml -> 3 g
        row("Salt", 1, "tsp"),                              # 5 ml -> 6 g
        row("Oil, olive", 1, "tbsp"),                       # stays 15 ml
        row("Milk, whole, Cow", 1, "tbsp"),
    ]))
    assert (items["Cumin seeds"]["required_quantity"], items["Cumin seeds"]["unit"]) == (3, "g")
    assert (items["Salt"]["required_quantity"], items["Salt"]["unit"]) == (6, "g")
    assert items["Olive oil"]["unit"] == "ml" and items["Milk"]["unit"] == "ml"


def test_tiny_amounts_are_not_rounded_up_to_a_big_pack():
    items = by_name(aggregate_ingredients([
        row("Saffron", 0.5, "g"),
        row("Nutmeg (Myristica fragrans)", 0.25, "tsp"),
        row("Ajwain seed whole organic spices", 2.5, "tsp"),   # 7.5 g
    ]))
    assert (items["Saffron"]["purchase_quantity"], items["Saffron"]["unit"]) == (1, "g")
    assert items["Nutmeg"]["purchase_quantity"] == 1
    assert items["Ajwain"]["purchase_quantity"] == 10


def test_frying_oil_is_one_reusable_batch_not_a_sum():
    items = by_name(aggregate_ingredients([
        row("Oil, sunflower", 480, "ml"),
        row("Oil, sunflower", 240, "ml"),
        row("Oil, sunflower", 2, "C"),
        row("Oil, sunflower", 1, "tbsp"),
        row("Oil, sunflower", 2, "tsp"),
    ], household_size=2))
    assert items["Sunflower oil (for frying)"]["required_quantity"] == 480   # biggest batch, once
    assert items["Sunflower oil (for frying)"]["category"] == "Pantry"
    assert items["Sunflower oil"]["required_quantity"] == 50                 # (15 + 10) x 2


def test_herb_sprigs_and_grams_become_one_line():
    items = aggregate_ingredients([
        row("Coriander leaves (Coriandrum sativum)", 4, "g"),
        row("Coriander leaves (Coriandrum sativum)", 5, "sprig"),
        row("Curry leaves", 6, "sprig"),
    ])
    coriander = [i for i in items if i["ingredient_name"] == "Coriander leaves"]
    assert len(coriander) == 1 and coriander[0]["unit"] == "g" and coriander[0]["required_quantity"] == 14
    assert by_name(items)["Curry leaves"]["unit"] == "sprig"
