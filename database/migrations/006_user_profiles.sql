create table if not exists public.users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  name text,
  email text,
  phone text,
  photo_uploaded boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.users enable row level security;

drop policy if exists "Users can read own profile" on public.users;
create policy "Users can read own profile"
  on public.users
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can create own profile" on public.users;
drop policy if exists "Users can update own profile" on public.users;

grant select on public.users to authenticated;
grant all on public.users to service_role;

create or replace function public.set_users_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_users_updated_at on public.users;
create trigger trg_users_updated_at
  before update on public.users
  for each row execute function public.set_users_updated_at();
