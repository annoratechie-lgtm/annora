
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
flutter pub get
flutter build web --release

echo "Copying environment file to web root..."
mkdir -p build/web/assets
cp .env build/web/assets/.env
echo "Verifying Flutter environment asset..."

if [ ! -f build/web/assets/.env ]; then
  echo "ERROR: Flutter did not package .env"
  exit 1
fi

echo "Environment asset found."

echo "Annora Web build completed!"
