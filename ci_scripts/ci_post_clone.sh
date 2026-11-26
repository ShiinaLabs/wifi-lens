#!/bin/sh
set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
exec /bin/sh "$repo_root/scripts/install-rust-toolchain.sh" "$repo_root/rust-core"
