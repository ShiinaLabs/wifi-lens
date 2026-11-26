#!/bin/sh
set -eu

: "${SRCROOT:?Xcode did not provide SRCROOT}"
: "${DERIVED_FILE_DIR:?Xcode did not provide DERIVED_FILE_DIR}"
: "${ARCHS:?Xcode did not provide ARCHS}"
: "${CONFIGURATION:?Xcode did not provide CONFIGURATION}"
: "${SDKROOT:?Xcode did not provide SDKROOT}"
: "${MACOSX_DEPLOYMENT_TARGET:?Xcode did not provide MACOSX_DEPLOYMENT_TARGET}"

echo "Building WiFiLens Rust Core ($CONFIGURATION; architectures: $ARCHS)"

case "$SDKROOT" in
    */MacOSX*.sdk) ;;
    *)
        echo "WiFiLens Rust Core supports macOS SDK builds only; got SDKROOT=$SDKROOT" >&2
        exit 1
        ;;
esac

case "$CONFIGURATION" in
    Debug) profile=debug ;;
    Release) profile=release ;;
    *)
        echo "Unsupported Xcode configuration: $CONFIGURATION" >&2
        exit 1
        ;;
esac

cargo_home=${CARGO_HOME:-"$HOME/.cargo"}
cargo_bin=$(command -v cargo || true)
if [ -z "$cargo_bin" ] && [ -x "$cargo_home/bin/cargo" ]; then
    cargo_bin="$cargo_home/bin/cargo"
fi
if [ -z "$cargo_bin" ] || [ ! -x "$cargo_bin" ]; then
    echo "Rust is not installed. Install rustup; rust-core/rust-toolchain.toml pins the toolchain and targets." >&2
    exit 1
fi

rust_core_dir="$SRCROOT/rust-core"
output_library="$DERIVED_FILE_DIR/libwifi_lens_core.a"
export CARGO_TARGET_DIR="$DERIVED_FILE_DIR/rust-core-target"
export CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER="$(/usr/bin/xcrun --sdk macosx --find clang)"
export CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER="$CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER"
export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-C link-arg=-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"

mkdir -p "$DERIVED_FILE_DIR"
cd "$rust_core_dir"
set --

for arch in $ARCHS; do
    case "$arch" in
        arm64) target=aarch64-apple-darwin ;;
        x86_64) target=x86_64-apple-darwin ;;
        *)
            echo "Unsupported Rust Core architecture from Xcode: $arch" >&2
            exit 1
            ;;
    esac

    if [ "$profile" = release ]; then
        "$cargo_bin" build --locked --target "$target" --release
    else
        "$cargo_bin" build --locked --target "$target"
    fi

    archive="$CARGO_TARGET_DIR/$target/$profile/libwifi_lens_core.a"
    if [ ! -f "$archive" ]; then
        echo "Cargo did not produce the expected static library: $archive" >&2
        exit 1
    fi
    set -- "$@" "$archive"
done

case "$#" in
    0)
        echo "Xcode selected no supported Rust Core architectures" >&2
        exit 1
        ;;
    1) /bin/cp -f "$1" "$output_library" ;;
    *) /usr/bin/xcrun lipo -create "$@" -output "$output_library" ;;
esac

/usr/bin/xcrun lipo -verify_arch $ARCHS "$output_library"
