# Architecture decisions

## Stack
- **Frontend:** Flutter/Dart -- chosen over React Native given the team's
  Python background (no existing JS/frontend experience) and the PRD's
  emphasis on camera OCR, barcode scanning, and custom swipe gestures,
  which Flutter's widget model handles natively.
- **Backend:** Python + FastAPI -- async-native, Pydantic validation,
  auto-generated docs, and keeps the whole team in one language across
  API and AI/ML work.
- **Database/Auth:** Supabase (Postgres + Auth + RLS) -- free tier viable
  for MVP, native gmail/phone-OTP support, RLS enforces per-user data
  isolation at the database layer.

## Milestone plan
Built one feature at a time, each fully working (frontend + backend +
database + tests) before moving to the next:
1. **Onboarding** (current)
2. AI meal planning & nutrition
3. Smart shopping / multi-vendor ordering
4. Inventory management (full: categorized page, OCR/barcode, swipe
   gestures, low-stock alerts -- deliberately NOT built partially during
   onboarding, even though the PRD's onboarding flow mentions initial
   pantry seeding, because that seeding step was made optional/skippable)
5. Reactive ordering (WhatsApp/voice helper loop)
6. Settings & analytics

## Direct-to-Supabase vs FastAPI
Not every read/write needs to go through the backend. The rule we're
using: if an operation is simple CRUD on the user's own data with no
business logic, no AI, and no third-party secret involved, it can go
straight from Flutter to Supabase, protected by RLS. If it involves
validation beyond what a Postgres constraint can express, AI/ML
orchestration, or a third-party API key, it goes through FastAPI.

Onboarding (Milestone 1) falls entirely in the first bucket. Meal
planning, price aggregation, and NLP parsing (later milestones) will
fall in the second.

## Onboarding schema
- `onboarding_profiles`: one row per user (`user_id` unique FK to
  `auth.users`), holding `family_size`, `monthly_budget`,
  `dietary_preference` (single required enum value), `dietary_goals`
  (optional array), and `onboarding_completed`.
- `dietary_exclusions`: zero-or-more rows per user for dislikes/allergens,
  normalized into its own table since it's optional, variable-length,
  and edited repeatedly from Settings later.
- A trigger auto-creates a placeholder `onboarding_profiles` row when a
  user signs up (`onboarding_completed = false`), so the app never has
  to handle a "no profile exists" null case -- only "profile incomplete."
- RLS policies restrict every row to `auth.uid() = user_id`.

## Required vs optional at onboarding
- **Required:** family size, monthly budget, dietary preference (single
  choice from a fixed list).
- **Optional, skippable, editable later in Settings:** dietary goals
  (multi-select), dislikes/exclusions, initial pantry inventory (in fact
  inventory seeding is deferred entirely to Milestone 4, not just made
  optional -- see Milestone plan above).
