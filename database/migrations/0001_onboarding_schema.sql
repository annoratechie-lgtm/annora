-- Migration 0001: Onboarding schema
-- Creates the profile and dietary-exclusion tables for Milestone 1 (Onboarding),
-- linked to Supabase's built-in auth.users table.

create type dietary_preference as enum (
  'vegetarian', 'eggetarian', 'non_vegetarian', 'vegan', 'no_restriction'
);

create type dietary_goal as enum (
  'keto', 'diabetic_friendly', 'high_protein', 'low_sodium', 'no_preference'
);

create table public.onboarding_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,

  family_size integer not null check (family_size > 0 and family_size <= 20),
  monthly_budget numeric(10,2) not null check (monthly_budget > 0),
  dietary_preference dietary_preference not null,
  dietary_goals dietary_goal[] not null default '{}',

  onboarding_completed boolean not null default false,
  onboarding_completed_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.dietary_exclusions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  ingredient_name text not null,
  created_at timestamptz not null default now(),
  unique (user_id, ingredient_name)
);

create index idx_dietary_exclusions_user on public.dietary_exclusions(user_id);

-- Keep updated_at current on every write
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger trg_onboarding_profiles_updated_at
  before update on public.onboarding_profiles
  for each row execute function public.set_updated_at();

-- Row Level Security: a user can only ever see/write their own rows
alter table public.onboarding_profiles enable row level security;
alter table public.dietary_exclusions enable row level security;

create policy "own profile only" on public.onboarding_profiles
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own exclusions only" on public.dietary_exclusions
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Auto-create an (incomplete) profile row whenever a new auth user signs up,
-- so the Flutter app always has a row to read/update instead of handling
-- a "no profile yet" null case everywhere.
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.onboarding_profiles (user_id, family_size, monthly_budget, dietary_preference)
  values (new.id, 1, 0.01, 'no_restriction')
  on conflict (user_id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
