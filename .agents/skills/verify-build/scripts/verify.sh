#!/usr/bin/env bash
#
# verify.sh — canonical WiFi Lens verification.
#
# Default:  build "WiFi Lens" + "WiFi Lens Pro" (Debug), then run WiFiLensTests.
# --quick:  build + test only "WiFi Lens" (skip the Pro build).
#
# Never runs UI test bundles. Never uses swift build/test. See SKILL.md.

set -euo pipefail

# Resolve repo root from this script's location
# (.agents/skills/verify-build/scripts/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
PROJECT="$REPO_ROOT/WiFiLens.xcodeproj"

QUICK=false
for arg in "$@"; do
  case "$arg" in
    --quick) QUICK=true ;;
    -h|--help)
      grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "verify.sh: unknown argument '$arg' (use --quick or --help)" >&2
      exit 2 ;;
  esac
done

DEST='platform=macOS'
COMMON=(-project "$PROJECT" -configuration Debug -destination "$DEST")

run() {
  echo "==> $*"
  xcodebuild "$@"
}

echo "verify.sh: repo root = $REPO_ROOT"

# 1. Build OSS scheme.
run "${COMMON[@]}" -scheme "WiFi Lens" build

# 2. Build Pro scheme (shared source safety) unless --quick.
if [ "$QUICK" = false ]; then
  run "${COMMON[@]}" -scheme "WiFi Lens Pro" build
else
  echo "==> (--quick) skipping WiFi Lens Pro build"
fi

# 3. Run the unit test bundle only (no UI tests).
run "${COMMON[@]}" -scheme "WiFi Lens" -skipPackageUpdates test -only-testing:WiFiLensTests

echo "verify.sh: OK"
