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

## IPv4 network boundary

WiFiLensCore provides an IPv4 boundary observation for Network Self-Check. MiniFTR sends one bounded trace to a numeric IPv4 destination on the selected physical interface, concurrently with the existing checks. The trace uses at most eight hops and a 1.2-second probe wait, with reverse DNS disabled. It looks for the default gateway followed by a contiguous run of private addresses and then a shared carrier or public address. Missing hops before the transition prevent learning a new boundary.

A successful HTTPS check can seed the in-memory cache. It keeps one boundary for up to an hour, keyed by the selected route, interface addresses and subnet masks, and Wi-Fi BSSID where applicable. During a connectivity failure, the existing assessment can use that boundary to recommend checking an upstream local router, the local network outlet, or the carrier connection. The gateway check sends a separate interface-bound ping to each discovered upstream local gateway, using the cached LAN path when the current trace is incomplete. A probe that could not execute is shown separately from a gateway that did not reply. The assessment can identify the first unresponsive upstream gateway when the nearer gateways respond, external connectivity fails, and no later trace or gateway probe demonstrates forwarding past it. The underlying gateway, DNS, HTTPS and proxy checks retain their own results. Network Self-Check is the only consumer.
