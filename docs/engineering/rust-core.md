# Rust Core

## Ownership and interface

The public `rust-core/` crate is the portable analysis layer used by
`WiFiLensCore`. Its internal modules own channel block geometry, 802.11
information-element parsing, observed/counterfactual channel-quality analysis,
interpretation of collected Wi-Fi link evidence, and regulatory region inference
and channel recommendation rules. The crate remains one Apache-2.0 Rust library
with no third-party Rust dependencies.

Swift-facing adapters preserve existing product APIs:

- `ChannelSpanCalculator` delegates channel block calculations to Rust.
- `IEParser` delegates byte parsing and protocol interpretation to Rust, then
  maps bounded suite codes and scalar fields into the existing `IEData` model.
  Swift keeps the existing security summary and display labels.
- `ChannelQualityCalculator` delegates overlap, observed RF scoring, target AP
  exclusion, recommendation thresholds, and result ordering to Rust. Swift
  maps those results into `ChannelQuality` and supplies localized band labels.
- `WiFiLinkInterpreter` maps collected link facts to the existing
  `WiFiLinkAssessment` contract through Rust. `WiFiLinkEvidenceValidator`
  remains a Swift provenance adapter that verifies the status and raw evidence
  refer to the same snapshot and source identity.
- `RegionInferenceEngine`, `RegulatoryDatabase`, `DeviceCompatibilityFilter`,
  `RegulatoryFilter`, and `RecommendationReasonCalculator` adapt normalized
  facts and existing Swift models to Rust. Rust owns country mapping, static
  channel rules, inference confidence, compatibility, overrides, classification,
  ordering, and stable reason identifiers. Swift retains locale and hardware
  fact collection, the observable pipeline, model construction, and reason text.

The Rust link interpreter receives normalized mode, radio, link-active, and
capture-consistency facts. It does not call CoreWLAN or SystemConfiguration,
read identifiers, or own event and polling lifecycle. Acquisition, UUID/time
comparisons, raw evidence retention, and source-identity validation remain in
Swift.

## Remaining Public Core Inventory

This inventory evaluates every non-presentation capability whose decision logic
can consume normalized facts. It records the actual production seam, existing
verification, and any platform-specific dependency that constrains a portable
boundary.

| Capability | Cross-platform assessment and destination |
|---|---|
| Regulatory inference and channel recommendations | **Moved in this R2 batch.** The production observation pipeline supplies locale/country codes, hardware channels, RF results, and PHY facts; Rust owns the country mapping, static rule table, inference, compatibility, overrides, classification, ordering, and reason identifiers. Swift's `RegulatoryDomainResolver` and `RegulatoryPipeline` remain fact/state adapters, while Swift owns model mapping and localized/display text. The rule query adapter also serves the spectrum heatmap. Existing region, database, compatibility, filter, and recommendation-reason tests exercise the Rust-backed Swift API. |
| Observation analysis | `ChannelOccupancyAnalyzer`, `WiFiQualityEvaluator`, and `DiagnosticEvaluator` consume normalized observation facts and are portable candidates used by the production observation pipeline. Their Swift boundary also applies link/gateway provenance validation and maps results to localized copy. A later batch can move the numeric/decision result while leaving provenance validation and localized presentation in Swift; channel deduplication should be evaluated alongside channel-quality input normalization. |
| Network diagnostic assessment | `NetworkDiagnosticAssessmentResolver` and `NetworkDiagnosticStageResolver` are pure over completed typed check results and evidence codes, with existing deterministic assessment tests. They are candidates for a separate core API after the evidence-code vocabulary is made an explicit boundary; current evidence includes a Foundation `URLError` code. `NetworkFingerprint.restartReason` is pure over normalized fingerprint values, but the file also owns `Network`, CFNetwork, and SystemConfiguration collectors. The collector stays native; value comparison can be split. Tunnel-name classification uses macOS interface prefixes (`utun`, `ipsec`, `ppp`), so its meaning remains in the platform adapter until other platforms supply normalized tunnel facts. Remediation key selection and status presentation stay in the Swift UI layer. |
| AP filtering | `APFilterQueryParser` produces a portable AST and has grammar tests. `APFilterService` also uses Foundation `localizedCaseInsensitiveContains` for SSID matching, so moving evaluation needs a deliberate case-folding contract to preserve current query behavior. The parser/filter are UI-facing query behavior and remain Swift pending that contract. |
| MAC vendor lookup | CSV/JSON parsing and longest-prefix matching operate on byte/string and entry values, so they are portable candidates. Download, bundled-resource loading, storage, observable refresh, and the current main-actor cache remain Swift. The available tests cover parser, resolver, store, downloader, and manager boundaries. |
| Link, roaming, and device tracking | `WiFiLinkStateCenter` combines AppKit/CoreWLAN/SystemConfiguration events, sampling clocks, and lifecycle; those adapters remain native, while a normalized transition core remains a candidate on top of the Rust link-evidence contract. Roaming probes perform CoreWLAN and interface-bound network acquisition; only classification over normalized samples is a candidate. `BLEDeviceTracker` consumes normalized advertisements without a system API, but its state uses implicit `Date()` and bounded history/eviction; an explicit time/state contract and direct behavior tests are prerequisites to a stable portable API. |
| Signal and presentation processing | `ChannelRecommendationAvailability`, signal smoothing used by chart projections, AP Radar presentation processing, chart/table projections, heatmap layout/rasterization, localization, and SwiftUI/AppKit rendering prepare visual state. They remain in Swift presentation modules. |
| Platform acquisition | CoreWLAN, SystemConfiguration, `NWPathMonitor`, CoreBluetooth, and interface-bound probes gather facts and remain native. Portable evaluators receive normalized values and do not call these APIs. |

`ChannelSeriesDataBuilder`, chart series, heatmap layout, Gaussian sampling, and
chart rendering continue to produce ChartLens/SwiftUI presentation data. The
crate remains one Apache-2.0 library; no second Rust crate or public repository
is required. The public Rust crate has no third-party dependencies. Swift/Xcode
adapter tests remain macOS-only; the public CI runs native Rust tests on Ubuntu,
Windows, and the macOS runner's Apple target. The documented local commands cover
both Apple targets. These host tests validate Rust and its C ABI, not the macOS
acquisition adapters.

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
- Link-evidence interpretation takes one fixed-size input record and writes one
  fixed-size result record. Optional facts use presence flags; state enums use
  documented integer codes, and invalid codes return status `10` without a
  partial result.
- Regulatory inference borrows one UTF-8 buffer plus caller-owned country-code
  ranges and supported-channel records. It returns the inferred domain,
  confidence, per-source domains, and conflict code without returning allocated
  pointers.
- Regulatory-rule lookup and recommendation filtering write records into
  caller-owned output arrays. Filter reason identifiers use a bit mask; the
  recommendation-reason call returns one reason mask per input recommendation.
- No Rust-owned pointer escapes the call. Counts report required capacity; an
  undersized output buffer returns status `7` and receives no partial records.
- Statuses distinguish invalid band/direction/width, invalid pointers or input
  slices, invalid UTF-8, invalid link-evidence codes, invalid regulatory codes
  and flags (`11`), insufficient output capacity, and a caught Rust panic.
  Panic handling prevents unwinding across C; callers still must provide valid
  memory for every non-null pointer.

Band, width, domain, confidence, classification, and reason values use the integer
codes documented in the public header. Optional values use explicit presence
bits instead of magic input sentinels. The result records use documented enum
codes for HT/VHT operation and counterfactual recommendation state.

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
to parsing, scoring, link-evidence, or regulatory code retrigger the static-library
build.

## CI toolchain setup

`scripts/install-rust-toolchain.sh` reads the channel from
`rust-core/rust-toolchain.toml`, installs that toolchain and both macOS targets,
and adds Cargo's bin directory to `GITHUB_PATH` when used by GitHub Actions.
The macOS Swift CI, Swift CodeQL build, and OSS release workflow call this helper
before invoking Xcode. Swift CI's Ubuntu and Windows Rust matrix uses the same
pinned-toolchain helper and runs `cargo test --locked` on each host. Its macOS job
tests the runner's Apple Rust target and builds/tests the Xcode product; the local
commands below cover both Apple targets.

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

The `WiFiLensCoreTests` target consumes the shared channel-span and
link-evidence TSV fixtures. Its regulatory inference, database, compatibility,
and filter suites exercise the existing Swift APIs through the Rust C ABI. The
link-evidence cases exercise the existing Swift `WiFiLinkInterpreter` API. Swift
adapter tests require macOS; Linux and Windows CI validate the Rust API and C ABI
on their native hosts. Run the suite through the native Xcode project:

```sh
xcodebuild -project WiFiLens.xcodeproj -scheme WiFiLensCore \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -skipPackageUpdates test
xcodebuild -project WiFiLens.xcodeproj -scheme WiFiLensCore \
  -configuration Debug -destination 'platform=macOS,arch=x86_64' \
  -skipPackageUpdates test
```
