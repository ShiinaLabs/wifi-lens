# Local Package to Xcode Framework Migration

Status: implemented and locally verified; remote CI has not run for this migration.

## Goal and acceptance contract

A normal public checkout must open and build `WiFiLens.xcodeproj` directly.
It must not require the private submodule, generated project files, source
symlinks, placeholder packages, private credentials, or a preparation script.
GitHub CI and public release automation build only the OSS product.

Replace all repository-owned local Swift packages with native Xcode framework
targets. Preserve existing module boundaries and edition assembly. External
remote Swift package dependencies remain remote package dependencies.
Private migration details are owned by
[the private migration plan](../../WiFiLensPro/docs/xcode-framework-migration.md).

## Public module ownership

| Former component | Native Xcode target | Responsibility |
| --- | --- | --- |
| `WiFiLensCore` local library package | `WiFiLensCore` macOS Framework | Shared product code, public module API, and owned resources |
| `WiFiLensCoreTests` package tests | `WiFiLensCoreTests` unit-test bundle | Existing shared behavior tests |
| `WiFiLens` app target | Existing app target | OSS assembly, app resources, signing, and distribution |
| `WiFiLensTests` app-hosted tests | Existing unit-test bundle | OSS assembly and app integration |

Keep the root project as the standard entry point and retain existing source
directories. Do not combine the shared module's sources into the app target.
The OSS target graph must depend only on public targets and remote packages.
Targets for other editions must not become implicit OSS build dependencies.

The project navigator mirrors each module's `Sources` and `Tests` directories,
including their existing subdirectories. File references use filenames relative
to their containing groups, preserving physical paths and target membership.

Use ordinary dynamic Framework targets, with the current module names and
public API unchanged. Configure explicit target dependencies, framework
linking, app embedding, and code signing. Apps embed their required frameworks
under `Contents/Frameworks`; frameworks do not carry nested copies of the
same shared framework. Retain the macOS 14 deployment target, Swift settings,
Debug testability, and appropriate archive installation settings.

## Implementation sequence

1. Remove the rejected temporary-project workaround from workflows and docs,
   and retire its new script. Keep unrelated working-tree changes intact.
   Retain independently justified OSS test fixes: direct public Logging
   linkage and campaign testing through the actual edition assembly.
2. Add the shared Framework and its unit-test target. Register all 180 existing
   Swift sources and 33 test files, retaining their ownership. Assign the Metal
   source to the shared target and verify its compiled resource ownership.
   Replace the local package product with the built Framework in consumers.
3. Convert the remaining repository-owned local packages and their tests at
   the private boundary, following the private plan. Complete this before
   declaring the public-checkout acceptance contract satisfied.
4. Remove all `XCLocalSwiftPackageReference` objects and their obsolete product
   and build-file references. Retire the three local package manifests and
   package-level lockfiles after their targets and tests are fully registered.
   Keep the Xcode project lockfile for external remote dependencies.
5. Restore direct root-project commands in Swift CI, Swift CodeQL, and Release.
   Add shared Framework tests to the OSS test plan and CI's explicit unit-test
   selections. Update verification scripts, architecture/testing references,
   contribution instructions, and private documentation for Xcode ownership.

These are implementation stages, not authorization to commit or push.

## Resource and test checks

- Preserve the app-owned String Catalog and current localization lookup.
  Verify lookup through app-hosted tests after linking the shared framework;
  do not move or rewrite translations as part of this migration.
- Preserve each former package's test suite as a dedicated Xcode test target.
  Register sources, dependencies, scheme Testables, and test-plan entries.
  App integration tests retain their app host; shared framework unit tests do
  not acquire a private application dependency.
- Replace package-generated resource lookup only where required by an actual
  resource consumer, using the owning framework or test bundle.
- Remove workaround-specific source-symlink assumptions. Project configuration
  tests must inspect the canonical project and retain their behavior checks.

## Validation

First validate a temporary public checkout with no private submodule or its
manifests. Run direct `xcodebuild` package resolution, OSS Debug/Release builds,
and the OSS plus shared-framework unit-test bundles against
`WiFiLens.xcodeproj`. No preparation step is permitted.

With the private submodule available, also validate the other app schemes,
their migrated framework tests, and production Release binary isolation as
defined by the private plan. Inspect archive embedding and runtime framework
resolution, not only compilation. Do not run UI bundles or repeat unrelated
scenario runs without an explicit request.

Validate workflow syntax and confirm that every formerly package-owned test
suite actually executes. A successful command with zero tests is insufficient.
Remote CI success remains unverified until the completed migration is pushed
with explicit user authorization and the checks finish.

## Verification result (2026-10-01)

A separate public source snapshot without `WiFiLensPro/` or local manifests
passed direct OSS Debug build, Release universal archive, and the two explicit
unit-test bundles: 628 app tests and 573 Core tests. It used the canonical root
project with no generated project, symlinks, or preparation script. The snapshot
used the committed String Catalog so unrelated local translation edits were
excluded from migration verification.

The archive embeds `WiFiLensCore.framework` once, with an `@rpath` install name.
Its runtime dependencies loaded without `DYLD` path overrides, and both Metal
kernels loaded from the framework resource bundle and created compute pipelines.
All 180 Core Swift sources and 33 test sources have explicit target membership.
Scheme/test-plan references, project syntax, workflow syntax, and diff whitespace
checks passed. Swift CI now explicitly runs both OSS and Core unit bundles;
CodeQL and Release already use the canonical root project directly.

Other edition build, native test, signing, and production-artifact checks are
recorded in [the private result](../../WiFiLensPro/docs/xcode-framework-migration.md).
No UI bundles or additional AppStage scenario runs were executed. Local checks
used Xcode 27.0 on macOS 27.0.1; the GitHub runner remains unverified. No
notarization or publishing was performed for this migration.

## References

- [Apple: Configuring a new target](https://developer.apple.com/documentation/xcode/configuring-a-new-target-in-your-project/)
- [Apple: Placing content in a bundle](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle)
