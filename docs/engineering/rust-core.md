# Rust Core

## Ownership and interface

The public `rust-core/` crate implements the channel span calculations used by
`WiFiLensCore`. `ChannelSpanCalculator.swift` preserves the Swift-facing API and
calls the Rust implementation through the `WiFiLensCoreRust` Clang module.

The Rust library exposes both native Rust functions and a small C ABI. The ABI
uses fixed-width integers and a `repr(C)` result structure declared in
`rust-core/include/wifi_lens_core.h`; `module.modulemap` exposes that header to
Swift. The crate builds as both an `rlib` and a static library. Its Cargo lock
file contains no third-party Rust packages, and the crate declares Apache-2.0.

## Xcode integration

The `WiFiLensCore` target runs `rust-core/build-rust-core.sh` in its
`Build Rust Core` phase. Xcode supplies the selected architectures,
configuration, macOS SDK, and deployment target. The script maps `arm64` to
`aarch64-apple-darwin` and `x86_64` to `x86_64-apple-darwin`, selects Cargo's
Debug or Release profile, and combines multiple static-library slices with
`lipo` when Xcode requests more than one architecture. The output stays under
Xcode's `DERIVED_FILE_DIR` and is linked into `WiFiLensCore.framework`.

The Xcode target adds `rust-core/include` to Swift's header search path. A
normal Xcode build therefore builds and links the Rust library as part of the
existing app workflow; no separate generated library or manual copy step is
needed.

## CI toolchain setup

`scripts/install-rust-toolchain.sh` reads the channel from
`rust-core/rust-toolchain.toml`, installs that toolchain and both macOS targets,
and adds Cargo's bin directory to `GITHUB_PATH` when used by GitHub Actions.
The Swift CI, Swift CodeQL build, and OSS release workflow call this helper
before invoking Xcode.

The public `ci_scripts/ci_post_clone.sh` calls the same helper for Xcode Cloud.
The Xcode build phase continues to use `build-rust-core.sh` for architecture,
configuration, SDK, and deployment-target selection.

## Toolchain and tests

`rust-core/rust-toolchain.toml` pins Rust 1.98.0, the `rustfmt` component, and
the two macOS targets. Install that toolchain and both targets with:

```sh
rustup toolchain install 1.98.0 --profile minimal --component rustfmt \
  --target aarch64-apple-darwin --target x86_64-apple-darwin
```

Run the native Rust API and C ABI tests from the crate directory:

```sh
cd rust-core
cargo fmt --check
cargo test --locked --target aarch64-apple-darwin
cargo test --locked --target x86_64-apple-darwin
```

The shared `WiFiLensCoreTests` target consumes the same TSV behavioral
fixtures. Run it through the native Xcode project:

```sh
xcodebuild -project WiFiLens.xcodeproj -scheme WiFiLensCore \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -skipPackageUpdates test
xcodebuild -project WiFiLens.xcodeproj -scheme WiFiLensCore \
  -configuration Debug -destination 'platform=macOS,arch=x86_64' \
  -skipPackageUpdates test
```
