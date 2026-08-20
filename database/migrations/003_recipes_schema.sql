create table public.recipes (
    id uuid primary key default gen_random_uuid(),

    recipe_code text not null unique,
    source_recipe_code text,

    name text not null,
    display_name text,

    source text not null default 'INDB',

    status text not null default 'active'
        check (status in ('active', 'draft', 'archived')),

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);