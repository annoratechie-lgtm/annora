
#!/usr/bin/env bash
set -euo pipefail

echo "Installing Flutter SDK..."

FLUTTER_HOME="$HOME/flutter"

if [ ! -d "$FLUTTER_HOME" ]; then
  git clone --depth 1 --branch stable \
    https://github.com/flutter/flutter.git "$FLUTTER_HOME"
fi

export PATH="$FLUTTER_HOME/bin:$PATH"

flutter --version
flutter config --enable-web

echo "Checking deployment environment variables..."

: "${SUPABASE_URL:?Missing SUPABASE_URL}"
: "${SUPABASE_PUBLISHABLE_KEY:?Missing SUPABASE_PUBLISHABLE_KEY}"
: "${ANNORA_BACKEND_URL:?Missing ANNORA_BACKEND_URL}"

echo "Creating frontend .env..."

printf '%s\n' \
  "SUPABASE_URL=$SUPABASE_URL" \
  "SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY" \
  "ANNORA_BACKEND_URL=$ANNORA_BACKEND_URL" \
  > .env

echo "Checking source .env..."
test -s .env
wc -c .env

echo "Installing dependencies..."
flutter pub get

echo "Building Annora Web..."
flutter build web --release
echo "Verifying published environment asset..."

test -s build/web/assets/annora.env

echo "SUCCESS: annora.env exists in Flutter assets."
ls -la build/web/assets/annora.env

# echo "Copying .env into published Flutter assets..."

# mkdir -p build/web/assets
# cp .env build/web/assets/.env

# echo "Verifying published output..."

# test -s build/web/assets/.env

# echo "Published environment file:"
# ls -la build/web/assets/.env
# wc -c build/web/assets/.env

# echo "Checking required variable names..."

# grep -q '^SUPABASE_URL=' build/web/assets/.env
# grep -q '^SUPABASE_PUBLISHABLE_KEY=' build/web/assets/.env
# grep -q '^ANNORA_BACKEND_URL=' build/web/assets/.env

# echo "SUCCESS: All environment variables are present."
echo "Annora Web build completed!"
