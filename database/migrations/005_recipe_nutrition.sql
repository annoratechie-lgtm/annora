begin;

-- Recipe-level INDB values per serving. food_code maps to
-- recipes.source_recipe_code; the column names match the INDB workbook.
create table if not exists public.recipe_nutrition (
  id uuid primary key default gen_random_uuid(),
  source_recipe_code text not null,
  unit_serving_energy_kcal numeric,
  unit_serving_protein_g numeric,
  unit_serving_carb_g numeric,
  servings_unit text,
  constraint recipe_nutrition_nonnegative check (
    (unit_serving_energy_kcal is null or unit_serving_energy_kcal >= 0)
    and (unit_serving_protein_g is null or unit_serving_protein_g >= 0)
    and (unit_serving_carb_g is null or unit_serving_carb_g >= 0)
  )
);

alter table public.recipe_nutrition enable row level security;

create policy "Authenticated users can read recipe nutrition"
  on public.recipe_nutrition
  for select
  to authenticated
  using (true);

grant select on public.recipe_nutrition to authenticated;

commit;
