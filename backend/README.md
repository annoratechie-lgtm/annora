# Annora Backend

FastAPI service for Annora's server-side meal-planning orchestration.

## Current scope

- Health check endpoints
- Authenticated `POST /api/v1/meal-plans/generate`
- Authenticated, read-only `POST /api/v1/assistant/chat`
- Supabase-backed planning context loading from onboarding data and dietary exclusions
- xAI/Grok structured 7-day meal-plan generation
- Persistence of meal plans, meals, meal ingredients, and grocery lists/items

The first meal-planning version generates a **7-day** plan. Pantry/inventory is intentionally out of scope for this milestone.

Annora Assist answers questions about Annora and the signed-in user's profile,
active meal plan, nutrition, and grocery list. It verifies the Supabase access
token and derives the user ID from that token; it does not accept a user ID in
the chat request. The backend loads only that user's selected records before
calling the configured LLM provider. The question and selected account data
are sent to that provider to generate an answer. Chat history is not persisted;
review the provider's data-use terms and disclose this processing to users
before production rollout.

Send a JSON body containing only the user's message:

```json
{"message": "What meals are planned for tomorrow?"}
```

The request must include `Authorization: Bearer <Supabase access token>`.

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

## Assistant flow

```text
Flutter Assist tab
  -> authenticated POST /api/v1/assistant/chat
  -> verify Supabase access token and derive user ID
  -> load only that user's profile, dietary exclusions, active plan, and groceries
  -> xAI-compatible LLM provider
  -> return answer without storing the conversation
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
