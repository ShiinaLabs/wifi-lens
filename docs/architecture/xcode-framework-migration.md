# Native Xcode Framework Migration

Status: implemented.

## Goal

A normal public checkout opens and builds `WiFiLens.xcodeproj` directly. The
project does not require a preparation script, generated project files, source
symlinks, local package manifests, or another repository.

Repository-owned shared product code uses native macOS Framework targets.
Remote Swift packages remain remote dependencies and are resolved through the
public project.

## Public module ownership

| Target | Responsibility |
|---|---|
| `WiFiLensCore` | Shared public product code, module API, and owned resources |
| `WiFiLensCoreTests` | Shared Framework behavior and algorithm tests |
| `WiFiLens` | Public app assembly, resources, signing, and distribution |
| `WiFiLensTests` | App-shell and public integration tests |

Keep the project root as the standard entry point and retain existing source
directories. Do not combine shared Framework sources into the app target.
Public target dependencies must remain within the public project and its
declared remote packages.

## Project and test rules

- Keep framework source and test membership explicit in the native project.
- Link and embed each required public Framework through native target
  dependencies.
- Keep the String Catalog and app-owned resources in their existing bundle.
- Preserve app-hosted tests and shared Framework tests as separate bundles.
- Use explicit unit-test selections by default; UI bundles are opt-in.

## Verification record

On 2026-10-01, a public source checkout passed direct Debug build, Release
archive, and the two explicit unit-test bundles. The archive embedded the shared
Framework once, loaded it through its runtime path, and loaded its Metal
resources. Project syntax, target membership, scheme/test-plan references, and
workflow syntax passed review. The checkout used the existing Xcode project
directly.
