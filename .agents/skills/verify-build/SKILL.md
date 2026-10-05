---
name: verify-build
description: >
  Use when a change touches the WiFi Lens product itself (Swift app source,
  unit tests) before claiming that work is complete, before
  committing such a change, or when asked to build, run tests, verify, or
  check compilation. Non-product changes (docs, agent assets, other
  repositories) do not trigger build verification.
---

# Verify Build

## Core Principle

**The app is verified with `xcodebuild`, never `swift build` / `swift test`.**
`swift build` in the repo root or app tree will not reflect the real target
configuration and gives misleading results. ChartLens is a remote Swift package
dependency, not a root-level checkout. Repository-owned modules are native
Framework targets; their tests are native unit-test bundles.

**Silence is not success.** A green exit code on the wrong scheme or the wrong
test subset does not mean the change is verified. Match the command to what
changed (table below).

## What changed → what to run

| Change | Verify with |
|--------|-------------|
| Shared source under `WiFiLensCore/` | Run Core Framework tests and build the public app scheme |
| Public app-shell source | Build the matching app scheme and relevant app-hosted tests |
| New/edited unit test file | Build and run the owning unit-test bundle with an explicit `-only-testing` selection |
| ChartLens integration | Verify through the owning WiFiLensCore Framework target or app scheme; ChartLens is a remote package dependency. |
| `.xcstrings` only | Localization JSON validity + completeness scan (see i18n-completer) |
| Docs / `.agents/` / other non-product changes | No build checks required |

Default verification for an app source change = **build + `-only-testing:WiFiLensTests -only-testing:WiFiLensCoreTests`.**

## Quick path (recommended)

```sh
# From repo root. Builds the public app (Debug) and runs the app and shared
# Framework unit bundles.
.agents/skills/verify-build/scripts/verify.sh

```

## Exact commands (when running by hand)

Build (OSS):
```sh
xcodebuild -project WiFiLens.xcodeproj -scheme "WiFi Lens" \
  -configuration Debug -destination 'platform=macOS' build
```

Unit tests (the only tests run by default):
```sh
xcodebuild -project WiFiLens.xcodeproj -scheme "WiFi Lens" \
  -configuration Debug -destination 'platform=macOS' \
  -skipPackageUpdates test -only-testing:WiFiLensTests -only-testing:WiFiLensCoreTests
```

## Hard rules

- **Never** run `swift build` / `swift test` to verify the app. `xcodebuild` only.
- **Do not** run UI test bundles (`WiFiLensUITests`) or a
  full scheme `test` (which pulls in UI tests) unless the user explicitly asks
  for UI tests. Default = `-only-testing:WiFiLensTests -only-testing:WiFiLensCoreTests`.
- When shared public product code changes, build the public app and Framework
  tests. Shared implementation is owned by WiFiLensCore, not duplicated in the
  app Sources phase.
- Use `-skipPackageUpdates` on `test` runs to avoid needless package resolution.
- `-destination 'platform=macOS'` — this is a macOS 14.6+ app, no simulator.

## Reporting

State what was actually run and its result. "Build passed" is insufficient — say
which schemes built and whether unit tests ran, e.g.:
> Public Debug build succeeded; WiFiLensTests + WiFiLensCoreTests passed (N tests).
