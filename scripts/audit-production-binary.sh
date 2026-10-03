#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <WiFi Lens Pro.app>" >&2
    exit 64
fi

app_path=${1%/}
if [[ ! -d "$app_path/Contents" ]]; then
    echo "App bundle not found: $app_path" >&2
    exit 66
fi

executable_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_path/Contents/Info.plist")
main_executable="$app_path/Contents/MacOS/$executable_name"
if [[ ! -f "$main_executable" ]]; then
    echo "Main executable not found: $main_executable" >&2
    exit 66
fi

info_plist="$app_path/Contents/Info.plist"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wifi-lens-binary-audit.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

assert_plist_value() {
    local key=$1
    local expected=$2
    local actual
    actual=$(/usr/libexec/PlistBuddy -c "Print :$key" "$info_plist" 2>/dev/null || true)
    if [[ "$actual" != "$expected" ]]; then
        echo "Unexpected $key in production app: '$actual' (expected '$expected')" >&2
        exit 1
    fi
}

assert_plist_value CFBundleIdentifier com.kaoru.wifi-lens-pro
assert_plist_value CFBundleDisplayName "WiFi Lens Pro"
assert_plist_value APP_ENVIRONMENT production
assert_plist_value DEFAULT_MCP_PORT 19840

codesign --display --entitlements :- "$app_path" > "$tmp_dir/entitlements.plist" 2>/dev/null || {
    echo "Could not read signed entitlements from production app: $app_path" >&2
    exit 1
}
app_sandbox=$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$tmp_dir/entitlements.plist" 2>/dev/null || true)
if [[ "$app_sandbox" != "true" ]]; then
    echo "Production app is missing the App Sandbox entitlement: $app_path" >&2
    exit 1
fi

for tool in otool nm strings; do
    command -v "$tool" >/dev/null || { echo "Required tool not found: $tool" >&2; exit 69; }
done

patterns='AppStage|WiFiLensCaptureSupport|StageControlClient|--appstage-|roaming-handoff|heatmap-demo|ap-radar-tracking|channel-recommendation|demo-ap-radar0|demo-channels0|demo-inert0|demo-wifi0|DEMO-2G-01'
binary_count=0

while IFS= read -r -d '' binary; do
    file "$binary" | rg -q 'Mach-O' || continue
    binary_count=$((binary_count + 1))

    otool -L "$binary" > "$tmp_dir/linked-libraries.txt"
    if rg -n -i 'AppStage|WiFiLensCaptureSupport' "$tmp_dir/linked-libraries.txt"; then
        echo "Forbidden linked framework in: $binary" >&2
        exit 1
    fi

    nm -a "$binary" 2>/dev/null > "$tmp_dir/symbols.txt" || true
    if rg -n "$patterns" "$tmp_dir/symbols.txt"; then
        echo "Forbidden symbol in: $binary" >&2
        exit 1
    fi

    strings "$binary" > "$tmp_dir/strings.txt"
    if rg -n "$patterns" "$tmp_dir/strings.txt"; then
        echo "Forbidden string in: $binary" >&2
        exit 1
    fi
done < <(find "$app_path/Contents" -type f -print0)

if [[ $binary_count -eq 0 ]]; then
    echo "No Mach-O binaries found in: $app_path" >&2
    exit 1
fi

echo "PASS: audited $binary_count Mach-O binary/binaries in $app_path"
