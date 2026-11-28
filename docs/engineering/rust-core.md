# Rust Core

## Ownership and interface

The public `rust-core/` crate is the portable analysis layer used by
`WiFiLensCore`. Its internal modules own channel block geometry, 802.11
information-element parsing, and observed/counterfactual channel-quality
analysis. The crate remains one Apache-2.0 Rust library with no third-party Rust
dependencies.

Swift-facing adapters preserve existing product APIs:

- `ChannelSpanCalculator` delegates channel block calculations to Rust.
- `IEParser` delegates byte parsing and protocol interpretation to Rust, then
  maps bounded suite codes and scalar fields into the existing `IEData` model.
  Swift keeps the existing security summary and display labels.
- `ChannelQualityCalculator` delegates overlap, observed RF scoring, target AP
  exclusion, recommendation thresholds, and result ordering to Rust. Swift
  maps those results into `ChannelQuality` and supplies localized band labels.

The migration boundary follows the input and output dependencies. CoreWLAN
acquisition and `WiFiChannel` remain native. Regulatory inference, device
compatibility, user overrides, and recommendation filtering remain native
because they consume system and product inputs beyond the portable score.
`ChannelSeriesDataBuilder`, chart series, heatmap layout, Gaussian sampling,
and chart rendering remain native because they produce ChartLens/SwiftUI
presentation data. No second Rust crate or public repository is required.

The Rust library exposes both native Rust functions and a small C ABI. The ABI
uses fixed-width integers and `repr(C)` records declared in
`rust-core/include/wifi_lens_core.h`; `module.modulemap` exposes that header to
Swift.

### C ABI ownership and errors

All variable-sized input and output data stays caller-owned:

- The IE parser borrows input bytes for one call. It writes scalar results to a
  caller-owned record, canonical suite labels to a caller-owned UTF-8 buffer,
  and byte ranges for each label to caller-owned arrays.
- Channel-quality input records refer to UTF-8 identity values by offset and
  length in one caller-owned byte buffer. Output records are written into a
  caller-provided array.
- No Rust-owned pointer escapes the call. Counts report required capacity; an
  undersized output buffer returns status `7` and receives no partial result.
- Statuses distinguish invalid band/direction/width, invalid pointers or input
  slices, invalid UTF-8, insufficient output capacity, and a caught Rust panic.
  Panic handling prevents unwinding across C; callers still must provide valid
  memory for every non-null pointer.

Band and width values use the integer codes documented in the public header.
Optional values use explicit presence bits instead of magic input sentinels.
The result records use documented enum codes for HT/VHT operation and
counterfactual recommendation state.

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
needed. The `Build Rust Core` phase lists each Rust module as an input so edits
to parser or scoring code retrigger the static-library build.

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
