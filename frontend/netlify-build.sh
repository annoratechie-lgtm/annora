printf '%s\n' \
  "SUPABASE_URL=$SUPABASE_URL" \
  "SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY" \
  "ANNORA_BACKEND_URL=$ANNORA_BACKEND_URL" \
  > env-check.txt

flutter pub get
flutter build web --release

mkdir -p build/web/assets
cp env-check.txt build/web/assets/env-check.txt