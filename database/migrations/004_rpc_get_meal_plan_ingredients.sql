CREATE OR REPLACE FUNCTION get_meal_plan_ingredients(
    p_meal_plan_id uuid
)
RETURNS TABLE (
    meal_plan_id uuid,
    meal_date date,
    meal_type text,
    source_recipe_code text,
    food_code_org text,
    food_name text,
    amount numeric,
    unit text
)
LANGUAGE sql
AS $$
    SELECT
        m.meal_plan_id,
        m.meal_date,
        m.meal_type,
        m.source_recipe_code,
        ri.food_code_org,
        ri.food_name,
        ri.amount,
        ri.unit
    FROM meals m
    JOIN recipe_ingredient ri
        ON ri.source_recipe_code = m.source_recipe_code
    WHERE m.meal_plan_id = p_meal_plan_id
    ORDER BY m.meal_date, m.meal_type;
$$;