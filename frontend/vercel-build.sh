#!/bin/bash
set -e

if [ ! -d "$HOME/flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
fi
export PATH="$HOME/flutter/bin:$PATH"

# Create the env asset the app bundles
mkdir -p assets
cat > assets/env <<EOF
SUPABASE_URL=$SUPABASE_URL
SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
ANNORA_BACKEND_URL=$ANNORA_BACKEND_URL
EOF

flutter config --enable-web
flutter pub get
flutter build web --release