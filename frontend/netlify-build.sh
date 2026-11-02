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

echo "Checking environment variables..."

: "${SUPABASE_URL:?Missing SUPABASE_URL}"
: "${SUPABASE_PUBLISHABLE_KEY:?Missing SUPABASE_PUBLISHABLE_KEY}"
: "${ANNORA_BACKEND_URL:?Missing ANNORA_BACKEND_URL}"

echo "Creating assets/env before Flutter build..."

mkdir -p assets
printf '%s\n' \
  "SUPABASE_URL=$SUPABASE_URL" \
  "SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY" \
  "ANNORA_BACKEND_URL=$ANNORA_BACKEND_URL" \
  > assets/env

test -s assets/env

echo "Installing dependencies..."
flutter pub get

echo "Building Flutter Web..."
flutter build web --release

echo "Verifying final deployment directory..."
test -s build/web/index.html
test -s build/web/assets/assets/env
ls -la build/web/index.html build/web/assets/assets/env

echo "Build completed successfully."