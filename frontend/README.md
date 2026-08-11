# Annora -- Frontend (Flutter)

This folder is a **scaffold**, not yet a real Flutter project. The Flutter SDK
isn't available in the environment used to generate this repo, so the native
`android/`, `ios/`, etc. folders that `flutter create` normally generates
don't exist yet. You'll create those locally in one step:

## One-time setup

1. Install the Flutter SDK: https://docs.flutter.dev/get-started/install
2. From this `frontend/` folder, run:
   ```
   flutter create --org com.annora --project-name annora .
   ```
   This fills in the native platform folders around the `lib/` and
   `pubspec.yaml` that are already here -- it will NOT overwrite `lib/`.
3. Install dependencies:
   ```
   flutter pub get
   ```
4. Create `frontend/.env` with just the two Flutter-relevant values:
   ```
   SUPABASE_URL=...
   SUPABASE_PUBLISHABLE_KEY=...
   ```
   The app loads this file at startup. It is ignored by Git. The Supabase
   publishable key is intended for client use; Row Level Security protects the data.

## Folder layout

```
lib/
  core/                          # theme, shared widgets, app-wide config
  features/
    onboarding/
      presentation/              # screens & widgets for onboarding
      state/                     # Riverpod providers/notifiers
      data/                      # repository + Supabase client calls
```

Each feature folder is self-contained: presentation talks to state, state
talks to the repository in data/, and the repository is the only thing that
talks to Supabase. This keeps Supabase calls out of widgets, so they stay
testable and swappable later.

## Running

Once `flutter create` has been run locally:
```
flutter run
```
