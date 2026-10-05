# Public Project Boundary

`WiFiLens.xcodeproj` is the public build entry point. Its native project graph,
shared schemes, source references, and direct package references are limited to
public-owned components.

## Approved targets

- `WiFiLens`
- `WiFiLensCore`
- `WiFiLensTests`
- `WiFiLensCoreTests`
- `WiFiLensUITests`

## Approved shared schemes

- `WiFi Lens`
- `WiFiLensCore`
- `WiFiLensTests`
- `WiFiLensUITests`

## Rules

- The project owns only the approved targets and schemes above.
- Source and project references stay inside the public checkout or use an
  explicit SDK or declared remote package reference. Absolute and parent-path
  source references are not allowed.
- The public project does not reference another Xcode project or fetch another
  repository as a source dependency.
- Every direct remote package reference must be consumed by an approved public
  target. Resolved transitive package pins are allowed when they come from that
  public package graph.
- Public code can use edition-neutral composition contracts and public product
  language. It must not name concrete implementations owned elsewhere.

## Automated guard

Run the structural check with:

```sh
python3 scripts/check-public-project-boundary.py
```

The guard checks native target and scheme allowlists, project and source path
shape, direct package ownership, and repository submodule state. It complements
manual review; it does not replace review of source ownership and composition
edges.
