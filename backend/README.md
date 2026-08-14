# Annora Backend

FastAPI service for Annora's server-side meal-planning orchestration.

## Current scope

- Health check endpoints
- Authenticated `POST /api/v1/meal-plans/generate`
- Supabase-backed planning context loading from onboarding data and dietary exclusions
- xAI/Grok structured 7-day meal-plan generation
- Persistence of meal plans, meals, meal ingredients, and grocery lists/items

The first meal-planning version generates a **7-day** plan. Pantry/inventory is intentionally out of scope for this milestone.

## Generation flow

```text
Flutter
  -> FastAPI
  -> validate Supabase access token
  -> load onboarding profile + dietary exclusions
  -> xAI / Grok
  -> validate structured 7-day plan
  -> persist meal plan + meals + ingredients
  -> aggregate ingredients into grocery list
```

## Setup

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate   # on Windows: .venv\\Scripts\\activate
pip install -r requirements.txt
```

Copy `.env.example` to `.env` and set your local secrets:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
LLM_API_KEY=your-xai-api-key
LLM_MODEL=grok-4.5
LLM_BASE_URL=https://api.x.ai/v1
LLM_TIMEOUT_SECONDS=90
```

**Never commit `.env` or secret keys.**

## Run

```bash
uvicorn app.main:app --reload
```

Then open:

- `http://127.0.0.1:8000/`
- `http://127.0.0.1:8000/api/v1/health`
- `http://127.0.0.1:8000/docs`

## Test

```bash
pytest tests/ -v
```
