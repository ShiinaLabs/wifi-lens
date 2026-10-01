#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${1:-$HOME/Desktop/WiFi Lens Releases}"
CONFIG="${2:-Release-OSS}"
SCHEME="WiFiLens"
DERIVED="$PROJECT_DIR/.build/DerivedData"

echo "==> Building $SCHEME ($CONFIG)…"
xcodebuild -project "$PROJECT_DIR/WiFiLens.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" \
    -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
    build

APP_PATH=$(find "$DERIVED/Build/Products/$CONFIG" -maxdepth 1 -name "*.app" | head -1)
APP_NAME=$(basename "$APP_PATH")

mkdir -p "$OUT_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
cp -R "$APP_PATH" "$OUT_DIR/${APP_NAME%.app}-$TIMESTAMP.app"

echo "==> Done: $OUT_DIR/${APP_NAME%.app}-$TIMESTAMP.app"