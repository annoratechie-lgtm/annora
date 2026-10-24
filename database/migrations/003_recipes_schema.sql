create table public.recipes (
  id uuid not null default gen_random_uuid (),
  recipe_code text not null,
  source_recipe_code text null,
  recipe_name text not null,
  recipe_display_name text null,
  source text not null default 'INDB'::text,
  status text not null default 'active'::text,
  category text not null,
  meal_type text not null,
  preference text not null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint recipes_pkey primary key (id),
  constraint recipes_recipe_code_key unique (recipe_code),
  constraint recipes_category_check check (
    (
      category = any (
        array[
          'sauce_condiment'::text,
          'starter'::text,
          'main_course'::text,
          'snack'::text,
          'dessert'::text,
          'side_dish'::text,
          'beverage'::text,
          'bakery'::text,
          'breakfast'::text,
          'soup'::text,
          'staple'::text,
          'salad'::text,
          'review'::text,
          'infant_food'::text
        ]
      )
    )
  ),
  constraint recipes_preference_check check (
    (
      preference = any (
        array[
          'non_vegetarian'::text,
          'eggetarian'::text,
          'vegetarian'::text,
          'vegan'::text
        ]
      )
    )
  ),
  constraint recipes_status_check check (
    (
      status = any (
        array['active'::text, 'draft'::text, 'archived'::text]
      )
    )
  )
) TABLESPACE pg_default;
