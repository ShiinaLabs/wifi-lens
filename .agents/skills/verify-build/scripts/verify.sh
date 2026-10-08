#!/usr/bin/env bash
#
# verify.sh — canonical WiFi Lens verification.
#
# Default: build the public app (Debug), then run public app and Core unit bundles.
#
# Never runs UI test bundles. Never uses swift build/test. See SKILL.md.

set -euo pipefail

# Resolve repo root from this script's location
# (.agents/skills/verify-build/scripts/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
PROJECT="$REPO_ROOT/WiFiLens.xcodeproj"

if [[ $# -gt 0 ]]; then
  echo "verify.sh accepts no arguments" >&2
  exit 2
fi

DEST='platform=macOS'
COMMON=(-project "$PROJECT" -configuration Debug -destination "$DEST")

run() {
  echo "==> $*"
  xcodebuild "$@"
}

echo "verify.sh: repo root = $REPO_ROOT"

# 1. Build OSS scheme.
run "${COMMON[@]}" -scheme "WiFi Lens" build

# 2. Run the public app and shared Framework unit bundles only (no UI tests).
run "${COMMON[@]}" -scheme "WiFi Lens" -skipPackageUpdates test -only-testing:WiFiLensTests -only-testing:WiFiLensCoreTests

echo "verify.sh: OK"
