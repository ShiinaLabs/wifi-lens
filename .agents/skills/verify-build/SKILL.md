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
`swift build/test` only applies to the standalone `ChartLens` package. Running
`swift build` in the repo root or the app tree will not reflect the real target
configuration and gives misleading results.

**Silence is not success.** A green exit code on the wrong scheme or the wrong
test subset does not mean the change is verified. Match the command to what
changed (table below).

## What changed → what to run

| Change | Verify with |
|--------|-------------|
| Any Swift source under `WiFiLens/Sources/WiFiLens/` (shared OSS+Pro code) | Build **both** schemes + unit tests → `scripts/verify.sh` |
| App source that is OSS-only or Pro-only | Build the matching scheme + unit tests |
| New/edited unit test file | Build + `-only-testing:WiFiLensTests` (see below) |
| `ChartLens/` package code | `cd ChartLens && swift build && swift test` |
| `.xcstrings` only | Localization JSON validity + completeness scan (see i18n-completer) |
| Docs / `.agents/` / other non-product changes | No build checks required |

Default verification for an app source change = **build + `-only-testing:WiFiLensTests`.**

## Quick path (recommended)

```sh
# From repo root. Builds "WiFi Lens" + "WiFi Lens Pro" (Debug) and runs the
# WiFiLensTests unit bundle. This is the default "is my change good?" check.
.agents/skills/verify-build/scripts/verify.sh

# Only touched OSS-side or want a faster loop — build+test just "WiFi Lens":
.agents/skills/verify-build/scripts/verify.sh --quick
```

## Exact commands (when running by hand)

Build (OSS):
```sh
xcodebuild -project WiFiLens.xcodeproj -scheme "WiFi Lens" \
  -configuration Debug -destination 'platform=macOS' build
```

Build (Pro) — always run this too when the change touches shared source, because
`WiFiLensPro` has its own independent Sources build phase:
```sh
xcodebuild -project WiFiLens.xcodeproj -scheme "WiFi Lens Pro" \
  -configuration Debug -destination 'platform=macOS' build
```

Unit tests (the only tests run by default):
```sh
xcodebuild -project WiFiLens.xcodeproj -scheme "WiFi Lens" \
  -configuration Debug -destination 'platform=macOS' \
  -skipPackageUpdates test -only-testing:WiFiLensTests
```

## Hard rules

- **Never** run `swift build` / `swift test` to verify the app. `xcodebuild` only.
- **Do not** run UI test bundles (`WiFiLensUITests`, `WiFiLensProUITests`) or a
  full scheme `test` (which pulls in UI tests) unless the user explicitly asks
  for UI tests. Default = `-only-testing:WiFiLensTests`.
- When shared source changed, a passing **OSS build alone is not enough** — the
  Pro scheme must build too (it maintains a separate Sources phase; a file added
  only to WiFiLens compiles OSS but fails Pro with "cannot find type in scope").
- Use `-skipPackageUpdates` on `test` runs to avoid needless package resolution.
- `-destination 'platform=macOS'` — this is a macOS 14+ app, no simulator.

## Reporting

State what was actually run and its result. "Build passed" is insufficient — say
which schemes built and whether unit tests ran, e.g.:
> OSS + Pro Debug builds succeeded; WiFiLensTests passed (N tests).
