-- Annora meal planning + grocery schema
-- Scope: first 7-day meal planning flow. Pantry/inventory is intentionally out of scope for now.

create table if not exists public.meal_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  start_date date not null,
  end_date date not null,
  status text not null default 'draft'
    check (status in ('draft', 'generating', 'active', 'completed', 'failed')),
  generation_source text not null default 'llm'
    check (generation_source in ('llm', 'manual', 'system')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint meal_plans_valid_date_range check (end_date >= start_date)
);

create index if not exists meal_plans_user_id_idx
  on public.meal_plans(user_id);

create index if not exists meal_plans_user_dates_idx
  on public.meal_plans(user_id, start_date, end_date);

create table if not exists public.meals (
  id uuid primary key default gen_random_uuid(),
  meal_plan_id uuid not null references public.meal_plans(id) on delete cascade,
  meal_date date not null,
  meal_type text not null
    check (meal_type in ('breakfast', 'lunch', 'dinner', 'snack')),
  name text not null,
  description text,
  status text not null default 'planned'
    check (status in ('planned', 'cooked', 'skipped')),
  prep_time_minutes integer
    check (prep_time_minutes is null or prep_time_minutes >= 0),
  nutrition jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint meals_unique_plan_date_type unique (meal_plan_id, meal_date, meal_type)
);

create index if not exists meals_plan_id_idx
  on public.meals(meal_plan_id);

create index if not exists meals_plan_date_idx
  on public.meals(meal_plan_id, meal_date);

create table if not exists public.meal_ingredients (
  id uuid primary key default gen_random_uuid(),
  meal_id uuid not null references public.meals(id) on delete cascade,
  ingredient_name text not null,
  quantity numeric(12,3) not null check (quantity > 0),
  unit text not null,
  created_at timestamptz not null default now()
);

create index if not exists meal_ingredients_meal_id_idx
  on public.meal_ingredients(meal_id);

create table if not exists public.grocery_lists (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  meal_plan_id uuid not null references public.meal_plans(id) on delete cascade,
  status text not null default 'active'
    check (status in ('active', 'completed', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint grocery_lists_one_list_per_plan unique (meal_plan_id)
);

create index if not exists grocery_lists_user_id_idx
  on public.grocery_lists(user_id);

create table if not exists public.grocery_items (
  id uuid primary key default gen_random_uuid(),
  grocery_list_id uuid not null references public.grocery_lists(id) on delete cascade,
  ingredient_name text not null,
  required_quantity numeric(12,3) not null check (required_quantity > 0),
  unit text not null,
  purchase_quantity numeric(12,3) not null check (purchase_quantity >= 0),
  category text,
  is_purchased boolean not null default false,
  is_urgent boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists grocery_items_list_id_idx
  on public.grocery_items(grocery_list_id);

create index if not exists grocery_items_purchase_idx
  on public.grocery_items(grocery_list_id, is_purchased);

-- Row Level Security
alter table public.meal_plans enable row level security;
alter table public.meals enable row level security;
alter table public.meal_ingredients enable row level security;
alter table public.grocery_lists enable row level security;
alter table public.grocery_items enable row level security;

-- Users can only access their own meal plans.
create policy "Users can manage own meal plans"
  on public.meal_plans
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Meals are owned through their parent meal plan.
create policy "Users can manage meals in own plans"
  on public.meals
  for all
  using (
    exists (
      select 1
      from public.meal_plans mp
      where mp.id = meals.meal_plan_id
        and mp.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.meal_plans mp
      where mp.id = meals.meal_plan_id
        and mp.user_id = auth.uid()
    )
  );

-- Meal ingredients are owned through their parent meal and meal plan.
create policy "Users can manage ingredients in own meals"
  on public.meal_ingredients
  for all
  using (
    exists (
      select 1
      from public.meals m
      join public.meal_plans mp on mp.id = m.meal_plan_id
      where m.id = meal_ingredients.meal_id
        and mp.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.meals m
      join public.meal_plans mp on mp.id = m.meal_plan_id
      where m.id = meal_ingredients.meal_id
        and mp.user_id = auth.uid()
    )
  );

-- Grocery lists are owned directly by the authenticated user.
create policy "Users can manage own grocery lists"
  on public.grocery_lists
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Grocery items are owned through their parent grocery list.
create policy "Users can manage items in own grocery lists"
  on public.grocery_items
  for all
  using (
    exists (
      select 1
      from public.grocery_lists gl
      where gl.id = grocery_items.grocery_list_id
        and gl.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.grocery_lists gl
      where gl.id = grocery_items.grocery_list_id
        and gl.user_id = auth.uid()
    )
  );
