# Product Modularization

## Why the product was modularized

The original app targets compiled a large amount of product code directly.
That made shared source ownership depend on duplicated Xcode target membership,
blurred the boundary between the public and paid editions, and made development
instrumentation difficult to keep out of the shipped product. Adding another
edition or host would have repeated those problems.

The modularization moves shared product capability behind a package boundary,
leaves each edition responsible for its app assembly, and separates development
instrumentation from production dependencies.

## Repository topology

The public repository keeps the components that it owns at the root:

```text
WiFiLens/
WiFiLensCore/
WiFiLens.xcodeproj
WiFiLensPro/                 # private Pro repository submodule
```

`WiFiLensCore` is the shared product package. `WiFiLens/` contains the public
macOS app shell and its resources and tests. `WiFiLensPro/` is a separate
private repository; public documentation identifies that boundary without
describing its implementation.

## Composition and dependency rules

The public app depends on `WiFiLensCore`. The private edition assembles its
additional product capability at its own boundary and consumes shared
capability through `WiFiLensCore`. App targets remain thin: they own process
entry, scenes, edition composition, resources, and distribution-specific
integrations, while reusable product behavior belongs in a package.

Development capture is a separate tooling boundary. AppStage and synthetic
scenario support are available to the capture host, while production app
dependency graphs do not include capture tooling. This is enforced by module
and target dependencies, then checked against the built production artifact.

```text
Public app shell ───────────────► WiFiLensCore
Private edition shell ─────────► private edition capability boundary
                                      │
                                      └────────► WiFiLensCore

Capture host ──────────────────► development capture boundary
                                      ├────────► product capabilities
                                      └────────► AppStage tooling
```

Edition composition is an explicit seam between shared product code and each
app shell. Shared code depends on the composition contract; the public and
private apps provide their own adapters without making the public repository
depend on private implementation types.

## Ownership principles

- Share product capability through modules instead of compiling the same
  implementation into multiple app targets.
- Keep edition assembly and distribution behavior in the relevant app shell.
- Keep the public/private repository boundary explicit. Public code and docs
  must not depend on or describe private implementation details.
- Keep capture and other development instrumentation outside the production
  dependency graph.
- Treat the dependency graph as an enforceable product boundary. Source layout
  alone does not prove that a capability is absent from a shipped app.

## Approaches not used

The architecture does not use a broad `APPSTAGE_CAPTURE` compilation switch or
a large tree of conditional compilation to change product behavior. Those
approaches leave production and capture concerns interleaved in the same
targets and make the effective product graph harder to inspect.

It also avoids maintaining duplicated production and capture app targets with
copied source membership, and avoids splitting the shared product into many
micro-packages without independent ownership or a useful dependency boundary.

## Future product lessons

Product capability and distribution shell are separate extension points. A
future edition can reuse product modules while supplying its own shell and
composition. Development tooling can add host-specific behavior without
changing the production graph. The same model can support a future CLI or
platform edition when it has a concrete host and dependency boundary; it does
not require creating a new module in advance.
