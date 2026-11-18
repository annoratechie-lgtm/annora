-- Ask Annora: saved chat, long-term memory, and where every plan change came from.
--
-- One continuous chat per user (assistant_messages). Messages older than 90 days
-- are deleted by the backend (purge_old_assistant_messages). Facts Annora should
-- remember across chats live in assistant_memory and are editable in Profile.
-- plan_changes is the audit log for generate / swap / new-week, with its source.
-- All writes go through the backend (service role); users may only read their own rows.

create table if not exists public.assistant_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null check (char_length(content) between 1 and 8000),
  -- A change Annora proposed in this reply (swap meals / new week), applied only on confirm.
  action jsonb,
  action_status text check (action_status in ('proposed', 'applied', 'dismissed', 'failed', 'expired')),
  meal_id uuid references public.meal(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint assistant_messages_action_has_status check ((action is null) = (action_status is null))
);

create index if not exists assistant_messages_user_created_idx
  on public.assistant_messages(user_id, created_at desc);
create index if not exists assistant_messages_created_idx
  on public.assistant_messages(created_at);

create table if not exists public.assistant_memory (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  fact text not null check (char_length(fact) between 2 and 200),
  kind text not null default 'preference'
    check (kind in ('dislike', 'like', 'preference', 'routine', 'health', 'other')),
  source_message_id uuid references public.assistant_messages(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists assistant_memory_user_fact_uidx
  on public.assistant_memory(user_id, lower(fact));

create table if not exists public.plan_changes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  meal_id uuid not null references public.meal(id) on delete cascade,
  meal_plan_id uuid references public.meal_plan(id) on delete set null,
  change_type text not null check (change_type in ('generate', 'swap')),
  source text not null check (source in ('onboarding', 'app', 'annora_chat')),
  message_id uuid references public.assistant_messages(id) on delete set null,
  before jsonb,
  after jsonb,
  created_at timestamptz not null default now()
);

create index if not exists plan_changes_user_created_idx
  on public.plan_changes(user_id, created_at desc);

-- Where a whole plan came from, and where each meal slot's current dish came from.
alter table public.meal
  add column if not exists origin text not null default 'app'
    constraint meal_origin_check check (origin in ('onboarding', 'app', 'annora_chat')),
  add column if not exists origin_message_id uuid references public.assistant_messages(id) on delete set null;

alter table public.meal_plan
  add column if not exists origin text not null default 'planner'
    constraint meal_plan_origin_check check (origin in ('planner', 'app_swap', 'annora_chat'));

-- Row level security: read your own rows; the backend (service role) does the writes.
alter table public.assistant_messages enable row level security;
alter table public.assistant_memory enable row level security;
alter table public.plan_changes enable row level security;

create policy "read own assistant messages" on public.assistant_messages
  for select to authenticated using (auth.uid() = user_id);

create policy "read own assistant memory" on public.assistant_memory
  for select to authenticated using (auth.uid() = user_id);

create policy "read own plan changes" on public.plan_changes
  for select to authenticated using (auth.uid() = user_id);

-- 90-day chat retention. Called by the backend; safe to schedule with pg_cron later.
create or replace function public.purge_old_assistant_messages(p_days integer default 90)
returns integer
language sql
security definer
set search_path = public
as $$
  with deleted as (
    delete from public.assistant_messages
    where created_at < now() - make_interval(days => p_days)
    returning 1
  )
  select count(*)::integer from deleted;
$$;

revoke all on function public.purge_old_assistant_messages(integer) from public, anon, authenticated;
