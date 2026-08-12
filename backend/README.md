# Annora Backend

FastAPI service for Annora's server-side meal-planning orchestration.

## Current scope

- Health check endpoints
- Authenticated `POST /api/v1/meal-plans/generate` scaffold
- Supabase-backed planning context loading from onboarding data and dietary exclusions

The first meal-planning version generates a **7-day** plan. Pantry/inventory is intentionally out of scope for this milestone.

## Planned generation flow

```text
Flutter
  -> FastAPI
  -> validate Supabase access token
  -> load onboarding profile + dietary exclusions
  -> LLM
  -> validate structured 7-day plan
  -> persist meal plan + meals + ingredients
  -> calculate grocery list
```

The LLM provider call and persistence layer are the next implementation step. The current endpoint deliberately returns a clear `501`/`503` instead of returning fake meal data.

## Setup

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate   # on Windows: .venv\\Scripts\\activate
pip install -r requirements.txt
```

Set these environment variables locally:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
LLM_API_KEY=your-server-side-llm-key
LLM_MODEL=your-model-name
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
