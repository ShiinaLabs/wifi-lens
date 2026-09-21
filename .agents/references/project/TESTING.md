# Testing

## Frameworks

| Target | Framework | Purpose |
|--------|-----------|---------|
| WiFiLensTests | Swift Testing (`@Test`, `#expect()`) | Pure-logic unit tests with `@testable import WiFiLens` |
| WiFiLensUITests | XCTest (`XCTestCase`) | End-to-end UI tests for the OSS app |

Private Pro test documentation is indexed at
[Pro/docs/TESTING.md](../../../Pro/docs/TESTING.md) and must be read only for
work explicitly scoped to Pro.

## Running Tests

Default verification should use `xcodebuild build` plus unit-test-only runs. Do not run UI test bundles unless the user explicitly asks for UI tests.

```sh
# Build verification — OSS target
xcodebuild -project WiFiLens/WiFiLens.xcodeproj -scheme "WiFi Lens" -configuration Debug -destination 'platform=macOS' build

# Unit tests only — OSS target
xcodebuild -project WiFiLens/WiFiLens.xcodeproj -scheme "WiFi Lens" -configuration Debug -destination 'platform=macOS' -skipPackageUpdates test -only-testing:WiFiLensTests

# Build verification — Pro target
xcodebuild -project WiFiLens/WiFiLens.xcodeproj -scheme "WiFi Lens Pro" -configuration Debug -destination 'platform=macOS' build

# OSS UI tests — run only when explicitly requested by the user
xcodebuild -project WiFiLens/WiFiLens.xcodeproj -scheme "WiFi Lens" -configuration Debug -destination 'platform=macOS' -skipPackageUpdates test -only-testing:WiFiLensUITests
```

## Unit Tests (WiFiLensTests)

Swift Testing target injected into the app process via `TEST_HOST` for `@testable import` symbol resolution. All test `.swift` files must be registered in `project.pbxproj` under the WiFiLensTests target's Sources build phase and listed in the WiFiLensTests scheme's `<Testables>` / `<MacroExpansion>`.

Covered modules: `ChannelSpanCalculator`, `IEParser`, `SSIDColorHasher`, `ChannelQualityCalculator`, `NetworkTableRow`, `BandChartViewModel`, `BandChartLayout`, `SnapshotToChartAdapter`.

### Test Selection Policy

Automated tests should protect meaningful user-observable behavior, non-trivial logic, or stable contracts.

- Pure localization, copy, wording, or terminology changes generally do not require new unit tests.
- Do not assert the exact translated text of a localization key unless that exact text is itself a stable contract.
- Do not freeze incidental implementation details such as exact widths, padding values, font choices, layout priorities, or specific scroll-view configuration merely because they were involved in a previous bug.
- For UI regressions, test the observable result instead, such as overflow, clipping, inaccessible content, incorrect interaction behavior, or broken layout at supported window sizes.
- Fixing a bug does not automatically require a new regression test. Add one when the affected behavior contains meaningful logic, is reasonably likely to regress, or has sufficient product risk to justify long-term maintenance.
- If an existing behavior-level test already protects the same regression, do not add another implementation-specific test for the same issue.
- A test claiming to exercise a specific localization or locale must verify that the localization lookup mechanism uses that locale. Do not assume that setting a SwiftUI environment locale changes localization performed outside that environment.
- Prefer semantic assertions over implementation-mirroring assertions.

Before adding a test, use this decision rule:

```text
If this test fails, what user-visible behavior or stable contract is broken?
```

If the answer is only that an internal number changed, a translated sentence changed, or the implementation changed while behavior remained correct, the test usually should not exist.

### Edition Composition Registration

Edition-composition tests verify the shared-shell contract while each target
compiles exactly one edition adapter. Register shared tests in `WiFiLensTests`.
Public target tests must not import, name, or describe private implementation
types. For explicitly Pro-scoped test work, follow
[Pro/docs/TESTING.md](../../../Pro/docs/TESTING.md).

### Runtime Backpressure and Snapshot Coverage

`RuntimeTests` deterministically blocks raw cycle A, admits B, then replaces B with C. It must observe A then C, `replacementCount == 1`, and no occupied raw slots after stop. Snapshot tests use a counting interface source and assert one capture per admitted cycle plus identical cycle ID/timestamp provenance in current status and runtime output. A suspended fake source proves capture does not occupy the main actor; provider unit tests must use hand-built connected/disconnected snapshots and must never construct `SystemNetworkInterfaceSnapshotSource`, which is reserved for production integration. `ScannerRuntimeMigrationTests` verifies the Interfaces projection comes from that output snapshot, detects a mutation back to a live `NetworkInfoService.fetchAll()` call, and proves the permanent termination gate rejects powered-on reconcile/restart/start work, supersedes an already-suspended runtime start, stops CoreWLAN monitoring, and is idempotent.

## UI Tests (WiFiLensUITests)

### Launch Arguments

| Argument | Purpose |
|----------|---------|
| `-ApplePersistenceIgnoreState YES` | Suppress macOS window state restoration so WindowGroup always creates a fresh window |
| `-UITest` | Custom flag; app init skips BLEViewModel creation and logs "UI test mode" |

### macOS Window State Restoration

macOS persists window existence across launches via `NSWindowRestoration`. If a prior run ended with all windows closed, the system restores "0 windows" on the next launch, suppressing SwiftUI `WindowGroup`'s default window creation. This produces an accessibility tree with only `MenuBar` and `TouchBar` — no `Window` element.

The UI test `setUp` addresses this with two measures:

1. **Delete saved state** before launch: `~/Library/Saved Application State/io.github.kaoru.wifi-lens.savedState`
2. **Launch argument** `-ApplePersistenceIgnoreState YES` — standard Cocoa mechanism read by `NSApplication` at startup

### Debugging Missing Windows

If `app.windows.firstMatch.waitForExistence(timeout:)` fails, dump the accessibility tree:

```swift
print(app.debugDescription)
```

If the tree shows `Application → MenuBar / TouchBar` without a `Window`, window restoration is the likely cause. Also check:
- System console for SwiftUI errors: `log stream --predicate 'process == "WiFi Lens"' --level debug`
- Window menu items — if Close/Minimize/Zoom are all disabled, no window instance exists

### Accessibility Identifiers

All key UI elements carry `.accessibilityIdentifier()` for stable querying (see [ARCHITECTURE.md](ARCHITECTURE.md) for the full convention). Examples: `sidebar-overview`, `page-settings`, `location-permission-view`, `wifi-off-view`, `settings-theme-picker`.
