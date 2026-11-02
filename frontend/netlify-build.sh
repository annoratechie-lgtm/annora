
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

echo "Building Annora Web..."
flutter build web --release

echo "Copying environment file to web root..."
mkdir -p build/web/assets
echo "Checking Flutter environment asset..."

if [ ! -f build/web/assets/.env ]; then
  echo "ERROR: build/web/assets/.env was not generated!"
  echo "Checking build output:"
  ls -la build/web/assets/ || true
  exit 1
fi

echo "SUCCESS: .env exists in Flutter web assets."
echo "File size:"
wc -c < build/web/assets/.env

echo "Annora Web build completed!"
