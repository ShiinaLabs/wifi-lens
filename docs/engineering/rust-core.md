# Rust Core

## Ownership and interface

The public `rust-core/` crate is the portable analysis layer used by
`WiFiLensCore`. Its internal modules own channel block geometry, 802.11
information-element parsing, observed/counterfactual channel-quality analysis,
interpretation of collected Wi-Fi link evidence, connection-quality bands and
diagnosis categories, regulatory region inference and channel recommendation
rules, and network-diagnostic stage aggregation. The crate remains one
Apache-2.0 Rust library with no third-party Rust dependencies.

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
- `NetworkDiagnosticAssessmentResolver` maps completed check results to
  normalized status, proxy-availability, and evidence facts in Rust, then maps
  the returned stage statuses, qualification codes, and shared success/neutrality
  facts back to the existing Swift models. The overall conclusion, primary-issue
  ordering, boundary-failure enrichment, probe execution, and presentation stay
  in Swift.
- `WiFiQualityEvaluator` validates link and gateway-probe provenance in Swift,
  then sends verified RSSI and an optional attributed latency to Rust for the
  quality level and signal/latency bands. `DiagnosticEvaluator` normalizes
  verified connection, channel, security, and PHY facts for Rust category
  selection; Swift retains severity, localization, and context-rich messages.

The Rust link interpreter receives normalized mode, radio, link-active, and
capture-consistency facts. It does not call CoreWLAN or SystemConfiguration,
read identifiers, or own event and polling lifecycle. Acquisition, UUID/time
comparisons, raw evidence retention, and source-identity validation remain in
Swift.

## Public capability inventory

This inventory follows production entry points, their immediate consumers, and
the tests in this public checkout. It separates portable decisions over
normalized facts from Swift adapters that collect facts or build user-facing
models. `cargo test --locked` can run on macOS, Linux, and Windows; the Swift/C
module bridge and Xcode framework tests require macOS. A successful Rust host
test does not verify CoreWLAN or other macOS acquisition behavior.

### Wireless analysis and channel recommendations

| Capability | Files and production consumer | Dependencies and data semantics | Destination and verification |
|---|---|---|---|
| Channel geometry | `rust-core/src/lib.rs` (`channel_half_span`, `channel_block`); `WiFiLensCore/Spectrum/ChannelSpanCalculator.swift`; consumed by `SnapshotToChartAdapter`, `ChannelSeriesDataBuilder`, and `SpectrumHeatmapActivity`. | Takes channel, width, band, and span direction as integers/enums; returns an inclusive channel-number block. It does not read scan or UI state. | Rust. The Rust unit/ABI tests and Swift `ChannelSpanCalculatorTests` run on the native Rust host and macOS/Xcode respectively. The Swift adapter keeps existing models and output mapping. |
| Observed RF scoring and counterfactual channel scoring | `rust-core/src/channel_quality.rs`; `WiFiLensCore/Channels/ChannelQualityCalculator.swift`; production entry is `ChannelOccupancyAnalyzer` in `WiFiObservationPipeline`, then `ChannelRecommendationEngine` and the channel UI consume results. | Rust owns frequency overlap, observed scores, target-AP exclusion for counterfactual scoring, selection thresholds, and stable ordering. Swift models preserve observed score/AP counts separately from recommendation score and localized band labels. | Rust. Existing channel-span/channel-quality Rust tests and Swift `ChannelQualityCalculatorTests` cover the core and adapter paths. Swift `ChannelQuality` and UI presentation stay native. |
| Scan normalization before RF scoring | `WiFiLensCore/Observation/Analyzers/ChannelOccupancyAnalyzer.swift`; called by `WiFiObservationPipeline`. | Deduplicates exact BSSID-plus-band records by strongest RSSI and uses the operating channel width, not advertised capability width. Inputs are already normalized scan observations; no API call occurs in this analyzer. | Rust candidate, not migrated here. The identity grouping and tie behavior should be made explicit in the portable input contract and kept separate from the already-portable scoring algorithm. Existing `AnalyzerTests` exercise the production Swift path; a Rust move can use host tests once the input semantics are fixed. |
| 802.11 information elements | `rust-core/src/information_elements.rs`; `WiFiLensCore/Scanner/IEParser.swift`; production callers include `NetworkObservationAdapter`, `ScannerViewModel`, `ChannelSeriesDataBuilder`, and interface detail projections. | Parses caller-provided bytes and returns bounded fields, suite codes, and ranges; it does not acquire beacon data. Swift preserves `IEData`, security summaries, and display labels. | Rust. Rust ABI tests cover parsing and buffer boundaries; Swift `IEParserTests` and adapter consumers are macOS/Xcode tests. |
| Regulatory inference and recommendation filtering | `rust-core/src/regulatory.rs`; `RegionInferenceEngine`, `RegulatoryDatabase`, `DeviceCompatibilityFilter`, `RegulatoryFilter`, and `RecommendationReasonCalculator`; production entry is `WiFiObservationPipeline`, with the regulatory lookup also used by the spectrum heatmap. | Rust owns country mapping, static channel rules, inference confidence, device compatibility, overrides, classification, ordering, and stable reason identifiers. Locale, CoreWLAN-supported channels, AP country IEs, scan results, and user overrides arrive as normalized facts. | Rust. Existing Rust API/ABI tests and the Swift regulatory suites exercise both sides. Swift retains locale/hardware acquisition, pipeline state, model construction, and localized restriction text. |
| AP query filtering | `WiFiLensCore/Filter/APFilterQueryParser.swift`, `APFilterService.swift`, `FilterCondition.swift`; used by `BandChartViewModel` for spectrum AP filtering. | The parser creates a deterministic query AST. SSID matching uses Foundation `localizedCaseInsensitiveContains`, so behavior follows the current platform's localized case-folding; the filter also selects presentation rows. | Retain native for now. A Rust evaluator would need a fixed, cross-platform case-folding contract to avoid changing user-visible search results. Grammar and filter tests run in the macOS Swift test targets. |
| AP Radar signal trend | `WiFiLensCore/APRadarSignalProcessor.swift`; `APRadarViewModel` consumes scan RSSI samples and feeds the radar presentation. | Validates RSSI, applies a bounded EMA/history window, and classifies trend from timestamps and smoothed values. It does not call a system API, but its output drives a live visual/audio interaction. | Rust candidate for a later analysis batch. The sample/trend rule is portable; the view model, pulse scheduling, and audio remain native. Existing processor tests are Swift-only today; the algorithm can use Rust host tests if moved. |
| Spectrum heatmap generation | `SpectrumHeatmapFieldGenerator.swift`, `SpectrumHeatmapLayout.swift`, `SpectrumHeatmapRasterizer.swift`, `SpectrumHeatmapMetalBackend.swift`, and `SpectrumHeatmap.metal`; consumed by `SpectrumHeatmapPanel`. | Converts Gaussian chart envelopes and view-space channel/RSSI coordinates into a normalized raster, with CPU and Metal implementations. It is render geometry and color intensity, not an RF or recommendation decision. | Retain native. Keeping the rasterizer beside SwiftUI/CoreGraphics layout and its Metal counterpart avoids duplicating presentation geometry in the portable business core. Its CPU/layout/Metal backend tests are macOS-only. |

### Network diagnostics, domain models, and evidence

| Capability | Files and production consumer | Dependencies and data semantics | Destination and verification |
|---|---|---|---|
| Diagnostic stage aggregation | `rust-core/src/network_diagnostic_stages.rs`; `NetworkDiagnosticAssessmentResolver.resolveStages`; consumed by `NetworkDiagnosticsViewModel` and the diagnostic workbench. | Rust receives normalized check statuses, proxy availability, and evidence flags. It distinguishes missing from indeterminate/skipped, applies stage precedence, and returns neutral gateway/direct-proxy qualifications. | Rust. `network_diagnostic_stages` Rust tests and the shared stage fixture cover the ABI; `NetworkDiagnosticsTests` and adapter tests run under Xcode on macOS. |
| Overall diagnostic conclusion and primary issue | `WiFiLensCore/NetworkDiagnosticAssessment.swift`; called by `NetworkDiagnosticsViewModel` after native check execution. | Consumes completed check results, proxy facts, evidence codes, and optional IPv4 boundary-failure details. Some input codes originate in Foundation probe errors, and the result enriches a user-facing issue. | Rust candidate after explicit normalization of probe/error and evidence codes. Probe execution, route discovery, and localized remediation stay native because they use `NWPathMonitor`, Network/CFNetwork/SystemConfiguration, interface-bound pings, and UI copy. Current conclusion tests are macOS Swift tests; normalized decision tests can run in the Rust host suite. |
| Observation quality bands and diagnosis category | `rust-core/src/observation_analysis.rs`; the Rust-backed `WiFiQualityEvaluator` and `DiagnosticEvaluator` are called by `WiFiObservationPipeline`, which publishes the result to `WiFiObservationStore` for both app editions through the shared `WiFiLensCore` framework. | Rust consumes an eligibility bit, optional RSSI/latency, association/metric verification, optional current-channel score, known/WPA3 security facts, and normalized PHY code. Missing evidence remains unknown/unavailable; diagnostic precedence remains excellent, weak signal, congestion, mediocre channel, security, old PHY, then acceptable. The score is 0–100; present latency is finite and nonnegative. | Rust. Rust typed and C ABI tests run on macOS/Linux/Windows; `AnalyzerTests` exercises the real Swift bridge and localized result construction on macOS. Swift keeps link/gateway provenance checks, channel/AP/recommendation context, severity, and localized text. |
| Observation and scan models | `WiFiCurrentStatus.swift`, `WiFiEnvironmentSnapshot.swift`, `WiFiNetworkObservation.swift`, `WiFiObservation.swift`, `WiFiQualityResult.swift`, and `DiagnosticResult.swift`; consumed by `WiFiObservationPipeline`, `WiFiObservationStore`, and SwiftUI pages. `NetworkObservationAdapter` maps `WiFiNetwork` records into the analysis shape. | Models carry captured values, `Date`/`UUID` provenance, optional facts, error states, and presentation-ready Swift types. The adapter receives scan results produced by CoreWLAN and parses their IE bytes through Rust. | Keep Swift models/adapters as the Swift framework contract. Rust APIs receive normalized scalar/record inputs rather than maintaining a duplicate copy of `WiFiObservation`; acquisition-to-model conversion remains adjacent to its CoreWLAN source. Public Rust behavior is host-testable, while Swift contract tests require macOS/Xcode. |
| Link-state evidence interpretation | `rust-core/src/link_evidence.rs`; `WiFiLinkInterpreter` in `WiFiCurrentStatus.swift`, used by `WiFiCurrentConnectionProvider` and `WiFiLinkStateCenter`. | Rust interprets normalized mode, radio, same-snapshot link-active, capture-window, and interface-presence facts. Ambiguous API values and contradictory/missing evidence produce unknown or an unconfirmed disconnect candidate rather than a false connected/disconnected claim. | Rust. Rust typed/ABI cases and `WiFiLinkInterpreter` adapter fixtures cover the portable decision; Swift tests cover record/provenance assembly. CoreWLAN/SystemConfiguration acquisition stays native. |
| Link and gateway provenance validation | `WiFiLinkEvidenceValidator` in `WiFiCurrentStatus.swift`; `WiFiGatewayEvidenceValidator` in `GatewayLatencyProvider.swift`; consumed by quality, diagnostics, interfaces, and roaming paths. | Verifies status/evidence cycle and timestamp agreement, interface identity, router target, attempt identity, bound-probe outcome, and finite/nonnegative reported latency before a fact is trusted. | Retain the provenance adapters in Swift. They validate native acquisition identity before the Rust evaluators receive normalized eligibility and values; Rust separately rejects invalid numeric ABI encodings. Tests exercise missing, mismatched, ambiguous, and malformed evidence on macOS. |

### Real-time analysis and shared foundations

| Capability | Files and production consumer | Dependencies and data semantics | Destination and verification |
|---|---|---|---|
| Observation and link event runtime | `WiFiObservationRuntime.swift`, `WiFiLinkStateCenter.swift`, provider/source files under `Observation/Providers` and `Observation/Runtime`; `ScannerViewModel` owns the public commands. | Coordinates CoreWLAN scans, system snapshots, event callbacks, timers, cancellation, ordered publication, and backpressure. Rust receives admitted normalized observations only. | Keep acquisition, callbacks, clocks, lifecycle, and publication native because they are OS-backed runtime responsibilities. The portable stateless evidence decision remains Rust. Runtime tests use fakes but still execute in the macOS Swift test host. |
| Roaming event classification | `RoamingTestViewModel.swift` and `RoamingRecord.swift`; the roaming view model consumes verified current-status probes, records segments/transitions, and writes session data; the view renders `RoamingChartScene`. | Continuity depends on ordered timestamps, interface/SSID/BSSID identity, verified association, gap limits, and metric attribution. Probes and session persistence are separate from the transition decision. | Rust candidate for normalized transition events and statistics; not migrated here because the temporal input/state contract is larger than the selected stateless observation assessment. Keep probe scheduling, evidence validation, persistence, and chart geometry native. Current behavior is covered by roaming view-model and model tests on macOS. |
| Network-change classification | `NetworkFingerprint.swift`; `NetworkDiagnosticsViewModel` compares collected fingerprints to decide which checks to rerun. | `restartReason` is deterministic over normalized route/address/DNS/proxy values; the same file also collects facts using Network, CFNetwork, and SystemConfiguration and classifies macOS tunnel-interface names. | Keep the compact restart selector in Swift with the diagnostics scheduler. Moving this small workflow decision across the ABI would add codes without creating a reusable network-analysis capability; system-derived route/tunnel facts remain native. Its behavioral tests require macOS/Xcode. |
| MAC vendor data | `MACVendorCSVParser.swift` parses registry files; `MACVendorResolver.swift` performs MAC normalization and longest-prefix lookup; the update service/manager/download/store path supplies bundled and downloaded data. | Parsing and prefix matching operate on bytes/strings and normalized records. Import validation includes registry completeness, duplicate/ambiguous assignment handling, size limits, and cancellation checkpoints. Download, resource loading, cache, logging, and observable refresh are native. | Rust candidate for parsing/normalization/lookup after specifying the import/error/cancellation contract. Not moved in this batch because the importer has a separate multi-file and cancellation contract from Wi-Fi observation analysis. Parser, resolver, and update-flow tests currently run in macOS Swift targets. |
| SSID colors and table/chart projections | `SSIDColorHasher.swift`, `NetworkTableRowSorter.swift`, `ChannelRecommendationAvailability`, `ChannelSeriesDataBuilder.swift`, `BandChartViewModel.swift`, and chart/heatmap views. | Produces SwiftUI colors, render series, row ordering, UI availability, and viewport geometry. These values drive presentation and preserve current palette/sort behavior. | Retain native. The concrete outputs are presentation types and UI state rather than portable Wi-Fi conclusions; their tests run on macOS/Xcode. |
| Signal smoothing helpers | `SignalProcessing/ExponentialMovingAverage.swift`, `HysteresisEMA.swift`, `KalmanFilter1D.swift`, and `SignalSmoothing.swift`. | `ExponentialMovingAverage` is used by `BLEDeviceTracker`; no production references were found for `HysteresisEMA` or `KalmanFilter1D` in the inspected Wi-Fi paths. | No Wi-Fi-core migration decision for the BLE consumer. Do not add unconsumed algorithms to Rust; the BLE tracker and its time/history contract were outside this inventory. The unused filters have tests but no traced production consumer. |

### Native-only acquisition and unreviewed modules

CoreWLAN scan/start/stop, SystemConfiguration and interface enumeration,
`NWPathMonitor`, CoreBluetooth advertisements, route/DNS/proxy/ping execution,
permissions, filesystem access, and app lifecycle remain native. They gather or
own platform facts; the portable core receives normalized values and performs
decisions without calling those APIs.

This inventory did not assess Rust suitability for the BLE product path beyond
the EMA reference, guidance/onboarding, storage, windowing, MCP server behavior,
or the full MAC-vendor download/update lifecycle. They are outside the Wi-Fi
analysis, recommendation, diagnostic, evidence, and roaming units above. The
public Xcode project still builds the public app and shared framework; its Rust
crate remains a single dependency-free library. Native Rust host tests can run
on macOS, Linux, and Windows, while Swift adapter and acquisition tests require
macOS/Xcode.

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
- Diagnostic stage aggregation takes one fixed-size normalized record with
  explicit missing/code values and flag bits, then writes one fixed-size stage
  and context result. Unknown codes or flags return status `12` without a
  partial result.
- Observation quality and diagnosis each take one fixed-size normalized record.
  Presence bits distinguish missing RSSI, latency, and channel score; a present
  latency must be finite and nonnegative, a present channel score must be in
  `0...100`, and diagnostic metric/security facts require verified metrics.
  Unknown codes, flags, or contradictory facts return status `13` without
  writing partial output.
- No Rust-owned pointer escapes the call. Counts report required capacity; an
  undersized output buffer returns status `7` and receives no partial records.
- Statuses distinguish invalid band/direction/width, invalid pointers or input
  slices, invalid UTF-8, invalid link-evidence codes, invalid regulatory codes
  and flags (`11`), invalid network-diagnostic codes and flags (`12`),
  invalid observation-analysis codes and flags (`13`), insufficient output
  capacity, and a caught Rust panic.
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
to parsing, scoring, link evidence, observation analysis, diagnostics, or
regulatory code retrigger the static-library build.

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
link-evidence cases exercise the existing Swift `WiFiLinkInterpreter` API.
`rust-core/tests/fixtures/network-diagnostic-stage-cases.tsv` is shared by the
Rust typed/C ABI tests and the Swift diagnostic adapter test, covering every
stage status and qualification boundary. `observation_analysis.rs` Rust tests
exercise quality/diagnosis thresholds, missing facts, category precedence,
invalid flag/code encodings, non-finite/negative latency, score range, pointer
errors, and no-partial-output behavior. `AnalyzerTests` exercises the real
Swift-to-Rust production bridge, localized result mapping, and provenance gates.
Swift adapter tests require macOS; Linux and Windows CI validate Rust and the C
ABI on their native hosts. Run the suite through the native Xcode project:

```sh
xcodebuild -project WiFiLens.xcodeproj -scheme WiFiLensCore \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -skipPackageUpdates test
xcodebuild -project WiFiLens.xcodeproj -scheme WiFiLensCore \
  -configuration Debug -destination 'platform=macOS,arch=x86_64' \
  -skipPackageUpdates test
```
