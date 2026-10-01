# Architecture

Native macOS network diagnostics application with Wi-Fi analysis, BLE diagnostics, and local integrations (SwiftUI + CoreWLAN + CoreBluetooth + AppKit interop). Targets macOS 14+, Swift 6.0.

## Data Flow

```
WiFi — CoreWLAN scan source → WiFiObservationRuntime
                               ├── scan lifecycle + one in-flight / one latest-pending raw-cycle gate
                               ├── one immutable NetworkInterfaceSnapshot per admitted cycle
                               ├── WiFiObservationPipeline.produceCycle(...)
                               │     ├── current connection + same-cycle gateway latency
                               │     ├── normalized environment + channel analysis
                               │     ├── regulatory inference + recommendation
                               │     └── quality + diagnosis → immutable WiFiObservation
                               └── publication gate
                                     ├── WiFiObservationStore UI projection
                                     └── target-selected edition integration

Runtime output → ScannerViewModel presentation projection
                  ├── WiFiNetwork → ChannelSpanCalculator → ChartSeriesData (Gaussian curves)
                  │                 → BandChartViewModel (per-band state → BandChartRenderModel)
                                       ├── combinedTableRows → SpectrumTablePanel → NativeTableView (AppKit NSTableView)
                                       ├── SpectrumPanelView (primary/secondary/tertiary, 1:1:1)
                                       │     ├── SpectrumBandPanel → WiFiBandChart
                                       │     ├── SpectrumTrendPanel → TrendChartView
                                       │     └── SpectrumTablePanel → NativeTableView
                                       ├── channelQualities → ChannelQualityCalculator → ChannelQualityView
                                       ├── bandViewModels → WiFiBandChart → Chart (universal renderer)
                                       ├── networkInfo → InterfacesView (throughput, gateway, DNS)
                                       ├── roamingSamples → RoamingTestViewModel → RoamingTestView
                                       ├── mcpServer → MCPServer → HTTP API (127.0.0.1:19840)
                                       └── regulatoryData → RegulatoryPipeline → ChannelRecommendation

BLE — CoreBluetooth scan → BLEAdvertisementEvent → BLEDeviceTracker → BLEViewModel
                                                                       ├── BLEScannerView
                                                                       └── BLETrendChartView (via Chart engine)

Chart Engine (ChartLens package):
  Caller builds [ChartSeries] + ChartAxisConfig + ChartStyle
      → Chart<Overlay> → GeometryReader → ChartGeometry
      → Canvas: grid, axes, clip, draw series by interpolation mode
      → overlay(geo, series)

  DetailOverviewChart wraps two Charts + RangeSelector for linked zoom/overview.
  See the [ChartLens package](https://github.com/ShiinaLabs/chart-lens) and [CHARTS.md](CHARTS.md) for rendering architecture.
  See [BLE.md](BLE.md) for BLE scan architecture.
  See [REGULATORY.md](REGULATORY.md) for regulatory pipeline.
  Private edition documentation is indexed at
  [WiFiLensPro/docs/ARCHITECTURE.md](../../../WiFiLensPro/docs/ARCHITECTURE.md) and must be read
  only for work explicitly scoped to Pro.
```

## Source Layout

| Path | Responsibility |
|---------------|---------------|
| `WiFiLens.xcodeproj/project.pbxproj` | Source of truth for app and test target membership, build settings, resources, schemes, native Framework dependencies, and remote package references |
| `WiFiLensCore` Xcode Framework target | Shared OSS/Pro product module, configured in `project.pbxproj` |
| `WiFiLensCore/Sources/WiFiLensCore/` | Shared OSS/Pro product kernel: domain and observation runtime, shared ViewModels and SwiftUI pages, diagnostics, and platform adapters |
| `WiFiLensCore/Tests/WiFiLensCoreTests/` | Sources for the native `WiFiLensCoreTests` unit-test target |
| `WiFiLens/Sources/WiFiLens/WiFiLensApp.swift` | App entry point, scenes, menu commands, and root window assembly |
| `WiFiLens/Sources/WiFiLens/App/` | App-shell integrations such as public edition composition, build configuration, logging, crash reporting, and update handling |
| `WiFiLens/Configs/` | Shared, OSS, and Pro Xcode configuration files |
| `WiFiLens/Sources/WiFiLens/Resources/` | App assets, icon, privacy manifest, and localized resources |
| `WiFiLens/Tests/` | App-hosted unit tests, UI test sources, and test plans |
| `WiFiLensPro/` | Private Pro submodule. Public references may identify this repository and link to its private documentation, but must not describe private implementation. |

The repository root keeps each component at its physical ownership boundary:
`WiFiLens/` for the app shell, `WiFiLensCore/` for the shared Framework,
`WiFiLensPro/` for the private submodule, and `WiFiLens.xcodeproj` as the
project entry point. Shared product capabilities belong to `WiFiLensCore`;
the private edition owns its product extension. App targets contain shell,
edition assembly, and distribution-specific integrations. Development capture
instrumentation belongs to a private support boundary and stays outside the
production app dependency graph.

## Key Patterns

- `ScannerViewModel` is `@Observable`, passed via `@Bindable` through the view tree
- **Single production observation runtime**: `WiFiObservationRuntime` owns the CoreWLAN scan source, serialized start/restart/stop lifecycle, per-start device capability cache, publication eligibility gate, and the sole raw-cycle admission buffer. The buffer permits one in-flight cycle and one replaceable latest pending cycle; replacing an older pending cycle increments `rawCycleReplacementCount`. No `AsyncStream` adds a second raw backlog.
- **Single interface snapshot**: every admitted runtime cycle awaits one value-semantic `NetworkInterfaceSnapshot` with a cycle ID and capture timestamp from the serial `SystemNetworkInterfaceSnapshotSource` actor. SystemConfiguration and `getifaddrs` enumeration therefore runs off the main actor. `WiFiCurrentConnectionProvider` derives status from that snapshot, `WiFiObservationScanOutput` carries the same value, and `ScannerViewModel.networkInfo` projects its interfaces. Current status and the Interfaces page share exact provenance without a second `NetworkInfoService.fetchAll()` call.
- **Immutable ordered publication**: after producing a cycle, the runtime applies the exact accepted `WiFiObservation` to `WiFiObservationStore`, updates `ScannerViewModel` presentation, and then crosses the target-selected edition boundary. The runtime is a Wi-Fi observation boundary, not a general application event bus.
- **Stop barrier**: `WiFiObservationRuntime.stopScanning()` invalidates the scan generation, clears pending raw work, cancels and joins the in-flight raw task, stops the source, and drains admitted edition-boundary work before returning. The final raw diagnostics have neither an in-flight nor a pending cycle.
- **Application termination barrier**: AppKit termination requests return `.terminateLater` through one process-scoped delegate coordinator. Repeated Command-Q and menu-bar quit requests share one operation and receive one reply. A three-second deadline covers scanner/runtime stop plus a target-selected edition hook. `ScannerViewModel.stopForTermination()` enters a permanent gate, stops monitoring, supersedes suspended startup, and rejects later lifecycle work.
- **Scanner presentation boundary**: `ScannerViewModel` forwards lifecycle and configuration commands to the runtime and projects runtime output into public presentation state. It does not scan directly, construct production observations, run production analyzers, or publish to the Store.
- **Edition composition**: shared code defines a narrow target-selected contract. Each app target supplies its edition assembly while shared product capabilities stay in Frameworks. Public source must not name or describe private concrete types.
- **App-owned main-window opening**: `MainWindowLifecycleCoordinator` owns the `openWindow` adapter and pending shared route independently of any `MainWindowSceneState`. Closing the final main window therefore releases all per-window state without removing the process-level ability to create the next `WindowGroup` scene and deliver its route.
- **Shared route-resource leases**: each main window registers its current route under a stable scene ID. A process-scoped coordinator aggregates those leases for the process-shared Spectrum charts and BLE scanner; resources start on the first matching route and stop only after the final lease is released by a route change or real window close. BLE starts return generation-bound sessions whose stop operation cannot terminate a newer session, and stopping always finishes that session's event stream.
- Selection flows bidirectionally: table row → `selectedNetworkID` → chart highlight; chart curve click → `selectedNetworkID` → table row highlight
- `NativeTableView` uses `Coordinator` as `NSTableViewDelegate` + `NSTableViewDataSource`
- **Spectrum panel composition**: `ContentView` lays out three `SpectrumPanelView` instances at equal height (`primary` / `secondary` / `tertiary`). Each panel owns a View-type switcher (`SpectrumPanelViewType`: `2.4G / 5G / 6G / Trend / Table`) and renders the matching content object: `SpectrumBandPanel`, `SpectrumTrendPanel`, or `SpectrumTablePanel`. The panel toolbar shows the View switcher and the active content's own controls on the same row; filtering belongs to the band views, the hidden-SSID toggle belongs to the table view, and Trend has no dedicated controls. `SpectrumTablePanel` sorts rows through `NetworkTableRowSorter` and preserves the shared `sortOrder` / `hiddenColumns` bindings.
- **Chart Engine** — All chart views build `[ChartSeries]` arrays and delegate rendering to the universal `Chart<Overlay>` component. Domain-specific overlays (tooltips, heatmaps, data labels, transition markers) are injected via a `ViewBuilder` closure. See [CHARTS.md](CHARTS.md).
- `WiFiBandChart` is decoupled from `BandChartViewModel` via `BandChartRenderModel` — a value-type snapshot created each render pass, so the view never holds a reference to the ViewModel
- **ChartSeriesData split**: `ChartSeriesDomainData` (immutable network identity) + `ChartSeriesRenderState` (mutable visual state: animated `displayRSSI`, `color`, filter/visibility flags, trend indicators). `ChartSeriesData` wraps both with computed passthrough properties
- `displayRSSI` animates toward `rssi` each tick for smooth Gaussian curve transitions
- AP roaming transitions share a single timestamp between old and new segments, eliminating gaps on the timeline
- Signal history (`SignalHistoryStore`) keeps 20 snapshots per BSSID in memory
- Cross-edition contract (DD-5): `SignalHistoryStore.allSnapshots` is consumed by the
  Pro recording feature as its per-tick snapshot source — it is not reserved/dead API.
  Changes to `SignalHistoryStore` must be verified against both the OSS and Pro schemes
  (`verify.sh` builds both).
- Private edition behavior must remain behind the shared edition contract and
  inside the `WiFiLensPro/` submodule. Public navigation or preview surfaces must not
  import private domain code.
- `ScannerViewModel.scanIntervalSeconds` supports temporary external overrides
  and restores the UserDefaults-configured value when the final override ends.
  Its `didSet` forwards a serialized runtime restart when scanning.
- `StableScore` provides hysteresis for quality level boundaries (upgrade margin 2, downgrade margin 5)
- **Manual network diagnostics**: `NetworkDiagnosticsViewModel` starts only after user action and owns one ordered `DiagnosticRunner`. The runner performs six checks in sequence: path state, gateway reachability, sampled DNS, base HTTP/HTTPS reachability with captive-portal evidence, forced IPv6 reachability, and system proxy routing. The runner owns execution only; stage status is derived on demand by `NetworkDiagnosticStageResolver` from the check results. Three stages — This Mac, LAN, and Internet — structure the workbench: a pipeline diagram at the top shows the This Mac → Router → Internet chain with connectivity status emphasized on the LAN/Internet connecting lines, and the native table groups its rows under collapsible stage headers without per-group status badges, with the proxy and DNS checks grouped under This Mac and the IPv6 check under Additional Checks. A gateway-reachability failure never blocks the downstream DNS, internet, or IPv6 probes. IPv6 is an optional probe that never downgrades the Internet stage or the overall conclusion, while the proxy check still participates in the overall conclusion. Proxy and PAC resolution produce ordered candidates; each HTTP and HTTPS target is routed and evaluated independently, using the first working candidate for its egress check. When no explicit proxy is configured but the default route uses a virtual network interface (utun/ipsec/ppp), the proxy check reports the tunneled route instead of direct. Tunnel detection covers both the routed tunnel interface on the active path and any active IPv4 tunnel interface, which also recognizes rule-based virtual network adapters (for example a split-tunnel utun) that never appear on the NWPath. The NWPath probe is time-boxed to one second so tunnel metadata cannot stall the proxy check, and the active-interface fallback reports a softer result because interface presence does not prove every target route traverses it. Network changes rerun only the network-sensitive checks. The page is a full-width desktop workbench: a compact command bar remains top-aligned, an inline strip reports progress or the final conclusion, and a native table owns the remaining workspace and scrolling. The table reveals completed and active checks while running, then shows every result inline after completion; regular, condensed, and compact column modes adapt its information density to the available width without a separate report surface. Populated rows use a comfortable 54-point minimum height and primary-contrast summaries, while alternating row backgrounds remain disabled so unused table space does not resemble placeholder results. Each check depends on a narrow injected system adapter, returns Normal, Abnormal, Indeterminate, Blocked, or Skipped, and compiles into both OSS and Pro without an edition seam or Wi-Fi/location requirement.
- `ChannelBand(id:)` failable initializer maps String band IDs ("24"/"5"/"6") to enum cases, used by `SnapshotToChartAdapter` for history playback
- **Channel recommendation priority**: `ChannelRecommendationAvailability.from()` checks `.currentGoodEnough` and `.targetUnknown` before `.isRecommended`. When the current channel is already good enough, no switching recommendation is shown — even if other channels score higher. This prevents contradictory UI messages (status banner says "good enough" while channel cards show "★ Recommended")
- Page-internal secondary navigation is hosted in the real window toolbar principal area, while the sidebar remains the primary top-level navigator
- `AppRootView` owns the active `SecondaryToolbarDescriptor` and per-page selection state for shared business-page mode switching
- Pages that participate in the shared secondary toolbar consume root-owned mode state instead of rendering their own local segmented controls
- **Toolbar selection state**: `SecondaryToolbarSelections` is a concrete `Equatable` struct with typed per-page properties (not a `[SidebarPage: ID]` dictionary). Each page's `SecondaryToolbarCapsule` binds directly to its typed property via `@ToolbarContentBuilder`. This lets SwiftUI compare old/new structs and skip `updateNSView` when nothing changed — critical because `WiFiLensApp.body` re-renders frequently due to `ScannerViewModel` observation
- **@Observable observation chain**: `BandChartViewModel` animation timer modifies `displayedSeriesData` at 60fps. If any parent view reads these properties (e.g. `allSeriesData.count`), the observation chain propagates up to `WiFiLensApp.body`, causing unnecessary re-renders of the entire view hierarchy including the toolbar. Cache frequently-changing derived values (e.g. `cachedTotalNetworks`, `cachedBandSummary`) in `ScannerViewModel` and have child views read the cached values instead
- **Main window policy**: The shipping app uses a standard resizable macOS main window. Do not use scene-level `.windowResizability(.contentSize)` on the app `WindowGroup`; page `idealWidth` / `idealHeight` values must stay local layout hints. Restored frames are normalized against the current screen `visibleFrame`. See [WINDOWING.md](WINDOWING.md).

## Localization

- All user-facing strings use `String(localized: "domain.component.element", comment: "Context for translators")` in source
- Keys use hierarchical dot-notation: `<domain>.<component>.<element>` with lowercase and underscores
- Domains: `common` (shared UI), `nav` (sidebar), `settings`, `overview`, `spectrum`, `channels`, `interfaces`, `roaming`, `ble`, `permission`, `wifi` (terminology), `format` (parameterized)
- Example: `"overview.diagnosis.congested.title"` for "Channel is congested" diagnosis heading
- Parameterized strings use `String(format: String(localized: "format.key"), args...)` — never interpolate values into the key string
- Translations in `Resources/Localizable.xcstrings` (Xcode String Catalog, `en`, `de`, `es`, `ja`, `zh-Hans`)
- New strings must be manually added to `.xcstrings` with `"extractionState": "manual"` and an explicit `en` localization with `"state": "translated"`
- Xcode auto-extraction is disabled (`SWIFT_EMIT_LOC_STRINGS = NO`)

## Testing

- Framework: Swift Testing (`import Testing`, `@Test`, `#expect()`)
- Tests cover pure-logic modules: `ChannelSpanCalculator`, `IEParser`, `SSIDColorHasher`, `ChannelQualityCalculator`, `NetworkTableRow`, `BandChartViewModel`, `BandChartLayout`, `SnapshotToChartAdapter`
- Test target uses `@testable import WiFiLens`

## Design Conventions

- Cards: `.regularMaterial` + `RoundedRectangle(cornerRadius: 12)`, 16pt padding
- Sub-cards: `.thinMaterial` + `RoundedRectangle(cornerRadius: 10)`
- Font: 9pt labels, 11-13pt body, 15pt semibold hero
- RSSI colors: green ≥ -55, yellow ≥ -70, orange ≥ -85, red below
- Quality colors: hex strings from `QualityLevel.color`
- Overlap badge on channel cards includes trailing "overlap" label for context
- **Target and package ownership**: Shared product capability belongs in the `WiFiLensCore` Framework; do not duplicate it in both app Sources phases. Pro product implementation belongs inside the private Pro boundary. Capture and AppStage integration belongs in private development tooling. App targets compile shell, edition assembly, and distribution-specific sources. Keep Xcode target membership explicit and verify each target's Compile Sources phase after project changes.
