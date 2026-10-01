# Windowing

This document records the main-window sizing and restoration policy for the shipping macOS app.

## P0 Incident: Main Window Off-Screen and Broken Full Screen

- Severity: `P0`
- Report source: App Store Review for `WiFi Lens` `1.4.2 (149)`
- Review date: June 26, 2026
- Review device: `MacBook Pro (14-inch, Nov 2024)` on `macOS 26.5.1`

### User-visible symptoms

- The main window opened behind the Dock and was visibly cut off.
- Clicking the green title-bar button did not enter full screen correctly and the content disappeared.

### Core buggy code

The original scene-level configuration allowed page content to drive the main `NSWindow` size:

```swift
WindowGroup {
    AppRootView(...)
}
.windowResizability(.contentSize)
.defaultSize(width: 900, height: 700)
```

At the same time, the app restored its previous frame through window autosave:

```swift
window?.setFrameAutosaveName("WiFiLensMainWindow")
```

Several mounted pages also advertised large ideal sizes:

```swift
.frame(minWidth: 700, idealWidth: 1000, minHeight: 600)
.frame(minWidth: 700, idealWidth: 1000, minHeight: 600, idealHeight: 700)
```

### Root cause

The bug was not a single bad height constant. It was the interaction of three behaviors:

1. Scene-level `.windowResizability(.contentSize)` made the main app window content-driven instead of behaving like a standard resizable macOS window.
2. The detail area kept multiple pages alive in a `ZStack` to preserve page-local state. Hidden pages could still contribute ideal-size pressure.
3. Autosaved frames were restored without normalizing them against the current screen's `visibleFrame`.

On a smaller review device with the Dock visible, that combination allowed the restored main window to exceed the visible screen area and produced unstable full-screen transitions.

That fix removed scene-level content sizing and added frame normalization, but it did not
eliminate the failure mode. The same user-visible symptoms returned; see the incident below
for the mechanism that actually drives the window frame.

Private edition windowing documentation is indexed at
[WiFiLensPro/docs/WINDOWING.md](../../../WiFiLensPro/docs/WINDOWING.md) and must be read only for
work explicitly scoped to Pro.

## P0 Incident: Hidden Page Minimum Height Drives the Window

- Severity: `P0`
- Report source: Developer report
- Report date: July 29, 2026
- Environment: `macOS 26.5.1`, built-in display, `visibleFrame` 1470x864

### User-visible symptoms

- The main window opened 1497pt tall on an 864pt-tall `visibleFrame`.
- The title bar sat pinned under the menu bar and the bottom of the window ran off the desktop.
- The window could not be dragged lower and could not be resized to fit the screen.
- Behavior differed between launches: sometimes the bottom clipped, sometimes it stopped at the Dock.

### Core buggy code

`BLEDisabledView` in `WiFiLensCore/Sources/WiFiLensCore/BLE/BLEScannerView.swift`:

```swift
Text(String(localized: "ble.disabled.description", comment: "..."))
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
```

### Root cause

`.fixedSize(horizontal: false, vertical: true)` means the text is never vertically
truncated, so when SwiftUI measures the view's *minimum* height it proposes the *minimum*
width, at which the string wraps into a roughly 1400pt column.

Because every page stays mounted in the detail `ZStack` to preserve page-local state, that
minimum propagates upward even while the page is invisible and its feature is disabled:

1. Detail `ZStack` minimum height = the maximum over all mounted children.
2. SwiftUI installs `NSHostingView.minHeight >= 1444.5 priority:999.9` on the
   `NavigationSplitView` detail column.
3. SwiftUI applies that minimum to the `NSWindow` itself through
   `NSHostingView.windowDidLayout` -> `NSHostingView.updateAnimatedWindowSize` ->
   `NSWindow._setFrameCommon`. With the 52pt title bar this yields a 1497pt window.
4. AppKit keeps the title bar below the menu bar, so the excess height hangs off the bottom.

The window then had two competing owners of its frame. `WindowAccessor.configure()` runs on
every `updateNSView` and normalizes the frame back into `visibleFrame`; SwiftUI re-applies
its own frame on the next layout pass. Logged frames alternated between `{900, 1497}` and
`{900, 864}`, which is why no user-chosen position or size survived and why the result
varied between launches.

Note that scene-level resizability was already `.automatic` here. Removing
`.windowResizability(.contentSize)` does not prevent SwiftUI from imposing a content-derived
minimum on the window.

### Fix

- Remove `.fixedSize(horizontal: false, vertical: true)` from the BLE description text.
- Wrap the state-preserving page `ZStack` in a `GeometryReader`, which severs layout-minimum
  propagation from hidden pages to the window.
- Declare the window's minimum size in SwiftUI as well; see the follow-up below.

## Follow-up: The Window Lost Its Lower Bound

- Report source: Pull request review
- Report date: July 30, 2026
- Environment: `macOS 27 beta 4`

### User-visible symptoms

- The main window could be dragged down to a few hundred points in either direction.
- The detail column collapsed until only the sidebar was left.

### Root cause

Severing the pages' layout minimums removed *every* content-derived minimum, and the app has no
other floor that survives. `WindowAccessor` did assign `NSWindow.minSize` and `contentMinSize`,
but SwiftUI's hosting controller recomputes both from the hosted content on each layout pass:
with the detail column reporting no minimum, `minSize` was rewritten to roughly `{148, 48}`.
The 820x620 policy was therefore never in force during interaction.

`NSWindow.minSize` only constrains interactive resizing. `setFrame` and `setContentSize` ignore
it, which is why a test has to resize through the accessibility frame setter to observe the clamp.

### Fix

- Declare the minimum in SwiftUI as a fixed constant (`View.mainWindowMinimumSize()`), so the
  minimum SwiftUI hands to the window is the policy value rather than whatever the pages report.
  It is a constant, so page content still cannot become a sizing policy.
- Keep the AppKit assignment (`MainWindowSizing.applyMinimumSize(to:)`) as the floor that applies
  before SwiftUI's first layout pass.

## Shipping Policy

The shipping app now follows these rules:

1. The main window is a standard macOS resizable window.
2. The app may provide a default launch size and minimum size, but page content does not control the real `NSWindow` size.
3. Both bounds hold: hidden pages must not expand the window past the screen, and the user must not be able to shrink it below `MainWindowSizing.minSize` (820x620).
4. Every restored frame is normalized against the current screen's `visibleFrame` before being shown.
5. If a restored frame is obviously invalid, the app falls back to a centered default size.
6. Page-level `idealWidth` / `idealHeight` values are allowed only as local layout hints.

## Current Implementation

- Scene-level sizing guardrails live in `WiFiLens/Sources/WiFiLens/WiFiLensApp.swift`.
- The default size and the minimum size live in `MainWindowSizing` in the same file. The minimum
  is applied twice: `applyMinimumSize(to:)` from `WindowAccessor`, and `mainWindowMinimumSize()`
  on the root view so SwiftUI's layout pass cannot lower it.
- The state-preserving page `ZStack` is wrapped in a `GeometryReader` in the same file so
  hidden pages cannot impose layout minimums on the window.
- Frame normalization logic lives in `WiFiLensCore/Sources/WiFiLensCore/Windowing/WindowFramePolicy.swift`.
- Regression tests live in `WiFiLens/Tests/WiFiLensTests/WindowFramePolicyTests.swift`,
  `DetailPageMinimumHeightTests.swift` (upper bound), and `MainWindowMinimumSizeTests.swift`
  (lower bound).

## Audit Results

Audit date: June 27, 2026

### Shipping app

- `WiFiLensApp.swift`
  - `WindowGroup` is the only shipping scene entry point for the main app window.
  - No remaining `.windowResizability(.contentSize)` usage exists in the shipping app.
  - `NSWindow` autosave remains in use, but all restored frames are now normalized.
- `Spectrum/ContentView.swift`
  - Still contains `idealWidth` / `minWidth` page hints.
  - Safe under the current standard-window policy.
- `Channels/ChannelQualityView.swift`
  - Still contains `idealWidth` / `idealHeight` page hints.
  - Safe under the current standard-window policy.

### Non-shipping/demo code

- `ChartLens` demo targets have their own window/layout code.
- No shipping-risk scene-level content-size windowing was found in the main app during this audit.

## Rules for Future Changes

- Do not add `.windowResizability(.contentSize)` to the shipping app window.
- Do not trust autosaved frames without checking the current screen's `visibleFrame`.
- If a page needs a large layout, keep that requirement local to the page. Do not let it resize the top-level `NSWindow`.
- If another state-preservation `ZStack` is introduced, wrap it in a `GeometryReader` so hidden pages do not become a sizing policy. A `.frame(maxWidth:maxHeight:)` on the container is not sufficient: it bounds maximums and still propagates the children's minimums to the window. `.frame(idealWidth:idealHeight:)` does not work either.
- Do not apply `.fixedSize(horizontal: false, vertical: true)` to text on an always-mounted page. It reports the height needed at the minimum proposed width, which SwiftUI can turn into an `NSHostingView.minHeight` constraint on the `NSWindow`. Bound the text instead (`.lineLimit`, or a `maxWidth` frame).
- Any content-derived minimum can reach the window regardless of `windowResizability`. When a window sizing bug appears, check the live `NSHostingView.minHeight` constraints on the split-view columns before suspecting autosave or scene modifiers.
- Do not rely on `NSWindow.minSize` alone. SwiftUI's hosting controller rewrites it from the hosted content on every layout pass, and it constrains only interactive resizing — `setFrame` and `setContentSize` ignore it. Any window minimum must also be declared in SwiftUI.
- When testing window minimums, host the view with `NSHostingController` as the window's `contentViewController`, the way `WindowGroup` does. An `NSHostingView` assigned directly to `contentView` leaves an already-assigned `minSize` alone and hides the defect.
- Keep the `openWindow` adapter and pending route in the app-owned lifecycle coordinator. A `MainWindowSceneState` must not be the sole owner of the action required to create its replacement after the final window closes.
