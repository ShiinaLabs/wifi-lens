#!/bin/sh
set -eu

rust_core_dir=${1:-"$(cd "$(dirname "$0")/.." && pwd)/rust-core"}
toolchain_file="$rust_core_dir/rust-toolchain.toml"

if [ ! -f "$toolchain_file" ]; then
    echo "Rust toolchain manifest not found: $toolchain_file" >&2
    exit 1
fi

toolchain=$(sed -n 's/^[[:space:]]*channel[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$toolchain_file")
if [ -z "$toolchain" ]; then
    echo "Rust toolchain channel is missing from $toolchain_file" >&2
    exit 1
fi

case "$toolchain" in
    *nightly*|*beta*)
        echo "WiFi Lens CI requires a stable Rust toolchain; found $toolchain" >&2
        exit 1
        ;;
esac

cargo_home=${CARGO_HOME:-"$HOME/.cargo"}
rustup_home=${RUSTUP_HOME:-"$HOME/.rustup"}
export CARGO_HOME="$cargo_home"
export RUSTUP_HOME="$rustup_home"

rustup_bin="$CARGO_HOME/bin/rustup"
if [ ! -x "$rustup_bin" ]; then
    rustup_bin=$(command -v rustup || true)
fi

if [ -z "$rustup_bin" ] || [ ! -x "$rustup_bin" ]; then
    if ! command -v curl >/dev/null 2>&1; then
        echo "curl is required to install the pinned Rust toolchain" >&2
        exit 1
    fi
    installer_path=$(mktemp "${TMPDIR:-/tmp}/rustup-init.XXXXXX")
    trap 'rm -f "$installer_path"' EXIT
    curl --fail --location --silent --show-error https://sh.rustup.rs -o "$installer_path"
    /bin/sh "$installer_path" -y --profile minimal --default-toolchain none --no-modify-path
    rustup_bin="$CARGO_HOME/bin/rustup"
fi

"$rustup_bin" toolchain install "$toolchain" --profile minimal \
    --component rustfmt \
    --target aarch64-apple-darwin \
    --target x86_64-apple-darwin
"$rustup_bin" run "$toolchain" rustc --version

if [ -n "${GITHUB_PATH:-}" ]; then
    printf '%s\n' "$CARGO_HOME/bin" >> "$GITHUB_PATH"
fi
