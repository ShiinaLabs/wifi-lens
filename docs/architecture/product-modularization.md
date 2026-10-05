# Product Modularization

## Ownership

The public repository owns the OSS app shell, reusable `WiFiLensCore`
Framework, public resources, public tests, and the standalone
`WiFiLens.xcodeproj`. Its native target and scheme graph contains public
products only. A public clone can resolve its own package graph and build
without another repository, private checkout, or generated project.

Reusable public product behavior belongs in `WiFiLensCore`; the app target
owns process entry, scenes, public edition composition, and distribution
integration. The edition-neutral composition contract allows a downstream
edition to consume public APIs while the public app remains independent of
downstream implementation.

## Native project ownership

Repository-owned public modules use native Xcode Framework targets. Xcode owns
source membership, resources, target dependencies, app embedding, and unit-test
targets. Remote Swift packages are used only when a public target consumes
them. The public project does not reference a downstream project, checkout, or
source tree.

The public target set is intentionally explicit:

- `WiFiLens`
- `WiFiLensCore`
- `WiFiLensTests`
- `WiFiLensCoreTests`
- `WiFiLensUITests`

See [Public Project Boundary](public-project-boundary.md) for the structural
policy and automated guard.

## Composition and dependency rules

The public app depends on `WiFiLensCore`. Edition-specific behavior crosses
the shared composition contract; public source must not name concrete types
owned by another edition. Public Frameworks consume their own public modules
and do not source-include app implementation.

```text
Public app shell
      ↓
WiFiLensCore Framework
      ↓
Public platform adapters
```

## Ownership principles

- Share public product capability through Framework APIs rather than
  duplicating implementation in app targets.
- Keep app assembly and distribution behavior in the app shell.
- Keep public source, project metadata, schemes, and package resolution
  self-contained.
- Review target membership and dependency direction whenever the native
  project changes.

## Future product lessons

Product capability and distribution shell are separate extension points. A
downstream app can consume the public Framework and provide its own composition
without making the public repository depend on downstream implementation. New
modules should be added only when they have a concrete ownership boundary.
