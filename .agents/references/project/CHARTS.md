# Chart Engine

Universal, data-driven chart rendering engine. Available as the remote **[ChartLens](https://github.com/ShiinaLabs/chart-lens)** Swift Package dependency of WiFiLensCore. All chart views build `[ChartSeries]` arrays and delegate rendering to the shared `Chart` component instead of drawing their own `Canvas`.

## Architecture

```
Caller builds [ChartSeries] + ChartAxisConfig + ChartStyle
    → Chart<Overlay> (SwiftUI View)
        → GeometryReader → computeGeo → ChartGeometry
        → Canvas: Y-grid, X-ticks, axes, clip, draw series
        → overlay(geo, series)
```

All domain-specific rendering (tooltips, data labels, heatmaps, transition markers) is injected via an overlay `ViewBuilder` that receives the computed `ChartGeometry`.

## Geometry Regions

The chart engine separates plot geometry from annotation geometry.

| Region | Owner | Purpose |
|--------|-------|---------|
| `frameRect` | `Chart` | Full local coordinate space owned by the chart view |
| `plotRect` | `ChartStyle` / `Chart` | Grid, axis lines, series curves, and fills |
| `chartRect` | Compatibility alias | Alias of `plotRect` for existing callers |
| `axisLabelRects` | `Chart` | Reserved areas for X and Y tick labels |
| `annotationRect` | `Chart` | Legal placement area for chart-owned labels and annotations |

Business overlays should use `annotationRect` for persistent labels and callouts. They should not infer label bounds from `plotRect` or duplicate axis-margin calculations. Domain-specific layout code remains responsible for collision resolution, but it must solve placement inside the annotation bounds supplied by `ChartGeometry`.

## Core Types

| Type | File | Purpose |
|------|------|---------|
| `ChartPoint` | `ChartTypes.swift` | Single (x, y) in data-space coordinates |
| `ChartSeries` | `ChartTypes.swift` | Array of points + rendering style + interpolation mode |
| `ChartSeriesStyle` | `ChartTypes.swift` | Color, lineWidth, areaOpacity, pointRadius, strokeOpacity, baseline |
| `ChartAxisConfig` | `ChartTypes.swift` | Axis bounds, grid step, tick labels/formatters, colors, fonts |
| `ChartStyle` | `ChartTypes.swift` | Layout margins → `chartRect(size:)` |
| `ChartInteraction` | `ChartTypes.swift` | Hover/tap/zoom callbacks + gesture toggles |
| `ChartGeometry` | `ChartGeometry.swift` | Maps data-space ↔ pixel-space via `dataToPoint`/`pointToData` |
| `SplineInterpolation` | `SplineInterpolation.swift` | Catmull-Rom and clamped cubic spline path generators |
| `ChartTimeFormatting` | `ChartTimeFormatting.swift` | `chartDurationLabel()` — seconds → "30s"/"2m"/"1h" |

### Interpolation Modes (`ChartSeries.Interpolation`)

| Mode | Behavior |
|------|----------|
| `.linear` | Straight polyline between points |
| `.catmullRom` | Smooth curve through all points |
| `.clampedCubic` | Monotonic cubic spline (no overshoot) |
| `.step` | Right-angle steps (horizontal then vertical) |
| `.gaussian(sigma:baseline:)` | Gaussian bell curve between two points — used for WiFi channel occupancy |

## Chart View (`ChartView.swift`)

Generic `Chart<Overlay: View>` component. Three initializers:

1. **No overlay**: `Chart(series:axis:style:interaction:)` — bare chart, overlay is `EmptyView`
2. **With overlay**: `Chart(series:axis:style:interaction:overlay:)` — overlay closure receives `(ChartGeometry, [ChartSeries])`

### Rendering Pipeline

1. `computeGeo(size:)` — calculates `ChartGeometry` from data range + axis config
2. `computeYRange()` — snaps `yMin`/`yMax` to multiples of `yStep`; guards against zero step
3. `computeXMin()`/`computeXMax()` — uses axis config or auto-computes from data
4. `drawContent(context:geo:)`:
   - Y-axis grid lines at step intervals + tick labels (uses `yTickLabel` formatter)
   - X-axis tick labels with overlap prevention (`minXTickSpacing`)
   - Axis lines (X at bottom, Y at left)
   - Optional clip rect
   - Series drawing by interpolation mode

### Hit Testing & Gestures

- `hitTest(location:geo:)` — finds nearest data point within 20px radius across all series
- `zoomGesture(geo:)` — `DragGesture` mapping pixel range → data-space `(lo, hi)` → `onZoom` callback
- `.onContinuousHover` triggers `onHover` callback with data-space point
- `.simultaneousGesture` allows parent views to add their own gestures without conflict

### Key Design Decisions

- No empty `.onTapGesture` — the Chart does not consume taps, allowing parent views to handle tap-to-select
- `ChartGeometry.scaleX`/`scaleY` denominators clamped to `max(1e-6, ...)` to prevent division by zero
- Y-grid loop uses index-based iteration (`yMin + i * step`) instead of `Int(step)` stride to avoid truncation
- `ChartStyle.chartRect` clamps width/height to `max(0, ...)` for safety in narrow containers

## Detail + Overview Chart (`DetailOverviewChart.swift`)

A linked pair: a detail chart showing a zoomed window, and an overview strip with a `RangeSelector` for panning/resizing.

```
DetailOverviewChart<DetailOverlay, OverviewOverlay>
    ├── detailChart: Chart (series filtered to windowStart...windowEnd)
    └── overviewStrip
        ├── RangeSelector (draggable window)
        │   └── overview: Chart (full series, compressed)
        └── overviewTimeAxis (domain labels)
```

- Domain-agnostic — works with time, frequency, channel numbers, or any continuous `Double` domain
- `domainLabel` closure formats domain values into axis labels
- `followMax: true` auto-scrolls the window to stay at the trailing edge (for live data)
- `minWindowSpan` / `defaultWindowSpan` control the zoom window
- Convenience init (no overlays) sets `overviewAxis` with all decorations disabled for a clean navigational thumbnail

## Range Selector (`RangeSelectorView.swift`)

Horizontal overview strip with a draggable, resizable selection window.

- Three drag modes: `resizeLeft`, `panWindow`, `resizeRight`
- `InvertedRoundedSelectionShape` masks the area outside the selection
- `SelectorHandle` views on left/right edges with hover cursor changes
- Edge badges show the current window bounds formatted via `edgeLabel`
- `followMax` auto-snaps the window to the domain's max edge (e.g., live data)
- Snap tolerance: when dragged within 8px of the max edge, snaps to follow mode

## WiFi Spectrum Integration

### ChartSeriesData Split (`ChartSeriesData.swift`)

The original flat `ChartSeriesData` was split into immutable domain data and mutable render state:

- **`ChartSeriesDomainData`** — immutable per-network identity: `id`, `ssid`, `bssid`, `channel`, `left`, `apex`, `right`, `rssi`, `phyMode`, `channelWidth`, protocol support flags, security info
- **`ChartSeriesRenderState`** — mutable visual state: `displayRSSI` (animated), `color`, `isFilteredOut`, `isVisible`, `qualityScore`, `trendArrow`, `trendDelta`
- **`ChartSeriesData`** — wraps both, exposing computed passthrough properties for backward compatibility

### BandChartRenderModel (`BandChartRenderModel.swift`)

Snapshot struct decoupling `BandChartViewModel` from `WiFiBandChart`. Contains pre-computed values: `xDataMin`, `xDataMax`, `yMin`, `visibleSeriesData`, `displayedSeriesData`, `strongestRSSI`, `isEmpty`, `zoomMin`, `zoomMax`, `isExpanded`, `axisTickStartChannel`.

Created fresh on each render pass via `BandChartViewModel.renderModel` — the view never holds a reference to the ViewModel.

### WiFiBandChart (`BandChartView.swift`)

Thin wrapper around `Chart` for WiFi spectrum visualization:
- Builds `[ChartSeries]` with `.gaussian` interpolation from `visibleSeriesData`
- Spectrum chart: Gaussian curves with data labels and selection/zoom overlays
- Data label overlay: SSID + trend arrows positioned above curves
- Tooltip overlay: SSID, RSSI, channel, BSSID on hover
- Tap-to-select, drag-to-zoom, expand to fullscreen
- `typealias BandChartView = WiFiBandChart` for backward compatibility

### BandChartLayout (`BandChartLayout.swift`)

Static layout utilities extracted from the old `DataLabelOverlay`:
- `axisTickValues()` — channel-number tick placement
- `placeLabels()` — collision-aware label placement with occupancy tracking
- `nearestSeries()` — hit-testing for hover/selection within curves

### SnapshotToChartAdapter (`SnapshotToChartAdapter.swift`)

Converts recorded `NetworkSnapshot` data into `ChartSeriesData` for history playback:
- `snapshotsNearest(to:in:)` — finds closest snapshot per BSSID at a given timestamp
- `toSeriesData(snapshotsByBSSID:band:colorHasher:trends:)` — mirrors `ChannelSpanCalculator.toSeriesData()` but operates on snapshots
- Supports optional `trends` parameter for trend arrows in history mode

## Ported Chart Views

All chart views now use the universal `Chart` component instead of custom `Canvas` drawing:

| View | Migration |
|------|-----------|
| `WiFiBandChart` | Gaussian curves via `Chart` + heatmap/label overlays |
| `TrendChartView` | Linear line + area fill + dot markers via `Chart` |
| `ThroughputChartView` | Clamped-cubic area fills (upload/download) via `Chart` |
| `BLETrendChartView` | Dual linear line series (smooth + raw) via `Chart` |
| `DebugChartView` | Same `WiFiBandChart` with debug-injected data |
| `DebugRoamingChartView` | Timeline → `DetailOverviewChart` + `RangeSelector` |

## Design Pitfalls

### Catmull-Rom Spline and Point Filtering

**Never** pre-filter data points to a visible window before passing them to `Chart` when using `.catmullRom` interpolation. Catmull-Rom splines use surrounding context points (p₀, p₃) to compute boundary tangents between p₁ and p₂. Filtering points at window edges destroys these context points, producing visibly distorted curves at the boundaries.

**Fix**: Send the complete `[ChartPoint]` array to `Chart` and rely on `axis.xMin`/`xMax` + `clipToRect` for visual windowing. The overview chart already does this — it always renders the full series with auto-computed x-range.

### SwiftUI @State Timing in followMax Mode

SwiftUI's `onChange(of:)` fires **after** `body` computation. When `DetailOverviewChart` uses `@State windowStart`/`windowEnd` updated via `RangeSelector.onWindowChange` callback, the detail chart's axis always lags one frame behind the overview chart's window position. This is especially visible with a live-updating domain whose upper bound advances every frame.

**Fix**: In `followMax` mode, derive the detail chart window from a **computed property** that reads `domain` directly (synchronous), bypassing the `@State → onChange → callback` chain. The `displayWindow` property handles this: when `followMax` is true, `span = min(defaultWindowSpan, max(minWindowSpan, domain.span))` and the window tracks `domain.upperBound` in the same frame.

### RangeSelector windowSpan Update Formula

`RangeSelectorView.onChange(of: domain.upperBound)` has two distinct update modes:

| Mode | Formula | Purpose |
|------|---------|---------|
| `followMax` | `min(defaultWindowSpan, max(minWindowSpan, domainSpan))` | Track domain span, growing up to `defaultWindowSpan` |
| Manual | `min(max(windowSpan, minWindowSpan), max(minWindowSpan, domainSpan))` | Preserve user's manual window size, clamp to valid range |

Using the manual-mode formula when `isFollowingMax` is true causes `windowSpan` to be locked at `minWindowSpan` forever — `max(windowSpan, minWindowSpan)` always returns `minWindowSpan` once it reaches that value. The detail chart's `displayWindow` span grows with the domain, but the RangeSelector handles stay at `minWindowSpan`, creating a visible mismatch between the blue selection rectangle and the detail chart's axis range.

### WiFiScanner Wall-Clock Scan Scheduling

The original `startScanning()` loop used "scan → sleep(interval)" which made the effective scan period = scan duration + interval. At 1 s interval with ~200 ms scan, data points arrived every ~1.2 s, causing the chart domain (real-time `Date()`) to pull ahead of the last data point by up to ~1 s.

**Fix**: Track wall-clock scan deadlines. Each scan N targets `startTime + N * intervalSec`. After yielding, sleep only for the *remaining* time until the next deadline. If a scan takes longer than the interval, the next scan starts immediately (no sleep backlog). This keeps data points aligned with the domain regardless of scan latency.

### overviewTimeAxis Duplicate First Tick

When `lowerBound` is a multiple of `step` (common case: `lowerBound = 0`, `step = 1`), both the initial `[domain.lowerBound]` and the first computed `ceil(lowerBound/step)*step` produce the same value. Fix: skip the first computed tick if it equals `lowerBound` (`if t == domain.lowerBound { t += step }`).

## Caller Quick Reference

```swift
// Minimal: line chart with auto-computed axes
Chart(series: [ChartSeries(id: "data", points: points, style: .line(color: .blue))])

// Full: with axis, style, overlay, and interactions
Chart(
    series: buildSeries(),
    axis: axisConfig,
    style: chartStyle
) { geo, series in
    // overlay views using geo for positioning
}
```
