#!/bin/bash
set -euo pipefail

fail() {
  printf 'WiFi Link Probe: %s\n' "$1" >&2
  exit 1
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "macOS 14 or later is required."
fi
major_version="$(sw_vers -productVersion | cut -d. -f1)"
if [[ ! "$major_version" =~ ^[0-9]+$ ]] || (( major_version < 14 )); then
  fail "macOS 14 or later is required."
fi
command -v xcrun >/dev/null 2>&1 || fail "xcrun is required (install Xcode Command Line Tools)."
command -v swiftc >/dev/null 2>&1 || fail "swiftc is required (install Xcode Command Line Tools)."
command -v python3 >/dev/null 2>&1 || fail "python3 is required."

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_file="$script_dir/LinkProbe.swift"
runner="$script_dir/run_experiment.py"
[[ -f "$source_file" ]] || fail "LinkProbe.swift was not found next to run.sh."

# The experiment runner invokes this script again as its collector. Reuse the
# already-built executable from the public entry point.
if [[ -n "${WIFI_LINK_LAB_OUTPUT_DIR:-}" && -n "${WIFI_LINK_LAB_COLLECTOR_BINARY:-}" && -x "$WIFI_LINK_LAB_COLLECTOR_BINARY" ]]; then
  exec "$WIFI_LINK_LAB_COLLECTOR_BINARY" "$WIFI_LINK_LAB_OUTPUT_DIR"
fi

build_dir="$(mktemp -d "${TMPDIR:-/tmp}/wifi-link-probe.XXXXXX")" || fail "Unable to create a temporary build directory."
cleanup() { rm -rf "$build_dir"; }
trap cleanup EXIT

xcrun swiftc \
  -target "$(uname -m)-apple-macosx14.0" \
  "$source_file" \
  -framework CoreWLAN \
  -framework SystemConfiguration \
  -framework Network \
  -framework Foundation \
  -framework AppKit \
  -o "$build_dir/LinkProbe" || fail "Swift compilation failed."

# Direct invocation by the experiment runner uses the freshly built collector.
if [[ -n "${WIFI_LINK_LAB_OUTPUT_DIR:-}" ]]; then
  exec "$build_dir/LinkProbe" "$WIFI_LINK_LAB_OUTPUT_DIR"
fi

if [[ $# -gt 1 ]]; then
  fail "Usage: ./tools/wifi-link-lab/run.sh [output-root]"
fi

if [[ $# -eq 1 ]]; then
  output_root="$1"
else
  output_root="$HOME/Desktop"
fi

prepare_output_root() {
  mkdir -p "$1" 2>/dev/null && [[ -d "$1" && -w "$1" ]] || return 1
  local probe
  probe="$(mktemp "$1/.wifi-link-lab-write-test.XXXXXX" 2>/dev/null)" || return 1
  rm -f "$probe"
}

if ! prepare_output_root "$output_root"; then
  if [[ $# -gt 0 ]]; then
    fail "The requested output root is not writable: $output_root"
  fi
  output_root="$HOME/Library/Logs"
  prepare_output_root "$output_root" || fail "Neither Desktop nor the user log directory is writable."
  printf 'Desktop is unavailable; using %s\n' "$output_root" >&2
fi

export WIFI_LINK_LAB_COLLECTOR_BINARY="$build_dir/LinkProbe"
printf 'Evidence root: %s\n' "$output_root"
python3 "$runner" "$build_dir/LinkProbe" --output-root "$output_root"
