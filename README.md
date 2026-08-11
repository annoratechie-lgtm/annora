# Annora

Meal planning, pantry management, and multi-vendor grocery delivery for
Indian households. See `docs/architecture.md` for the full stack rationale.

**Current milestone: Onboarding.** Nothing beyond auth + profile capture is
built yet, on purpose -- see `docs/architecture.md` for the milestone plan.

## Stack

- **Frontend:** Flutter/Dart, Riverpod for state management
- **Backend:** Python + FastAPI (currently just a health check -- see below)
- **Database/Auth:** Supabase (Postgres + Supabase Auth + Row Level Security)

## Repo layout

```
annora/
  frontend/     # Flutter app -- see frontend/README.md
  backend/      # FastAPI service -- see backend/README.md
  database/
    migrations/ # version-controlled SQL, applied via Supabase CLI or dashboard
    seeds/       # optional local dev seed data (empty for now)
  docs/         # architecture notes
  scripts/      # dev setup helpers
```

## First-time setup (in order)

1. **Supabase project:** create a free project at https://supabase.com,
   then apply `database/migrations/0001_onboarding_schema.sql` via the
   SQL editor in the Supabase dashboard (or the Supabase CLI once we
   set that up).
2. **Backend:** follow `backend/README.md`.
3. **Frontend:** follow `frontend/README.md`.
4. Copy `.env.example` to `.env` at the root and fill in your Supabase
   project URL + keys (found in Supabase dashboard -> Project Settings -> API).

## Why onboarding doesn't use the backend

For Milestone 1, the Flutter app talks directly to Supabase (via the
`onboarding` feature's `data/` repository) instead of going through FastAPI.
Validation is enforced by Postgres constraints and Row Level Security
instead of a service layer, since onboarding has no business logic beyond
"save this user's own profile." Later milestones (meal-plan generation,
price aggregation, NLP) will go through FastAPI, since those need
server-side AI orchestration and third-party API keys that must never
reach the client. See `docs/architecture.md` for the full reasoning.

## Branching & commits

- `main` is always deployable.
- Feature branches: `feature/<milestone>-<short-description>`, e.g.
  `feature/onboarding-profile-screen`.
- Commit messages: short imperative summary, e.g. `Add onboarding profile schema`.
- Open a PR into `main` for every change; at minimum, tests must pass
  (`pytest` for backend, `flutter test` for frontend once screens exist).
