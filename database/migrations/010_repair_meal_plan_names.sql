-- 010: One-time repair of saved meal names (safe to re-run).
--
-- 1. Rows saved with name 'NA' because the LLM returned "Name-CODE"
--    (e.g. 'Plain Pulao-ASC114') instead of the bare code. Normalise the code,
--    fill in the display name, and fill the nutrition that was skipped at save
--    time. Rows whose code does not exist at all (invented by the LLM) are left
--    untouched.
-- 2. Switch names saved from recipes.recipe_name ('BOILED RICE') to the
--    friendlier recipes.recipe_display_name ('Boiled rice (Uble chawal)'),
--    matching what the backend now saves for new plans.

with fixed as (
  select mp.id,
         r.source_recipe_code as code,
         coalesce(nullif(btrim(r.recipe_display_name), ''), r.recipe_name) as display_name
  from public.meal_plan mp
  join public.recipes r
    on r.source_recipe_code = (regexp_match(upper(mp.source_recipe_code), '([A-Z]{2,}[0-9]+)\s*$'))[1]
  where mp.name = 'NA'
)
update public.meal_plan mp
set source_recipe_code = f.code,
    name = f.display_name,
    nutrition = coalesce(
      (select jsonb_build_object(
                'servings_unit', n.servings_unit,
                'unit_serving_carb_g', n.unit_serving_carb_g,
                'unit_serving_protein_g', n.unit_serving_protein_g,
                'unit_serving_energy_kcal', n.unit_serving_energy_kcal)
         from public.recipe_nutrition n
        where n.source_recipe_code = f.code
        limit 1),
      mp.nutrition),
    updated_at = now()
from fixed f
where mp.id = f.id;

update public.meal_plan mp
set name = coalesce(nullif(btrim(r.recipe_display_name), ''), r.recipe_name),
    updated_at = now()
from public.recipes r
where r.source_recipe_code = mp.source_recipe_code
  and mp.name = r.recipe_name
  and coalesce(nullif(btrim(r.recipe_display_name), ''), r.recipe_name) <> mp.name;
