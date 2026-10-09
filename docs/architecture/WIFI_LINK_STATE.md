# Wi-Fi Link State Center

`WiFiLinkStateCenter` is the process-wide owner of lightweight Wi-Fi link
sampling, notification registration, state interpretation, continuity tracking,
and public state transitions. It is independent of scan scheduling, window
count, location authorization, and SSID visibility. The application uses the
shared center; existing scanner code reaches it through `WiFiPowerMonitor`, a
compatibility subscription that does not own a system listener.

## Evidence and interpretation

`WiFiLinkEvidenceCollector` captures one Wi-Fi interface's CoreWLAN mode and
radio result, the raw `powerOn()` boolean when returned, SystemConfiguration
Link state, CoreWLAN service state, interface index/flags, optional SSID/BSSID,
a cycle ID, capture bounds, and per-field
missing/read-failure reasons. SSID and BSSID are identity attributes only.
Their absence does not weaken positive association evidence. A current
snapshot never carries identity forward from a previous sample.

Association is confirmed only by a same-cycle station mode, reported-on radio,
and `Link.Active == true` for a named Wi-Fi interface. Missing or contradictory
evidence is unknown. CoreWLAN mode `none` and `powerOn() == false` remain
ambiguous because the APIs can also return those values on read failure.
The raw `powerOn()` value is retained separately; a raw false is not a confirmed
radio-off fault.

The interpreter can identify a disconnect candidate when explicit or ambiguous
no-mode, reported-on radio, and inactive system link evidence agree.
Confirmation also requires two distinct sampling cycles with strictly
increasing capture times, the same interface and run session, independent
reads, no intervening positive association, and at least one supporting
negative from CoreWLAN service activity or independent `getifaddrs` running
flags. `Link.Detaching` is recorded as additional context, not used as the sole
cross-check. No fixed polling interval is a domain rule.

**Disconnect confirmation is disabled by default.** The specific negative
evidence combination has not yet been validated in the signed, sandboxed app.
Until that validation is complete, candidate samples publish `unknown` with a
disconnect-candidate reason; they do not create a disconnected state or event.
Tests can explicitly enable the candidate-confirmation policy with synthetic
evidence. First observed association or non-association establishes a baseline
and does not create a reconnect or disconnect event.

## Snapshots, events, and continuity

`WiFiLinkStateSnapshot` independently reports radio evidence, verified link
state, and optional current network identity. It includes a snapshot ID, run
session ID, session sequence, interface identity, `linkEpoch`, evidence source
IDs, sample time, and publication time. Consumers determine freshness from the
sample time and their maximum-age policy; no persistent valid flag is used.

`WiFiLinkStateEvent` has its own stable UUID, ordered session sequence,
interface identity, connection generation, prior/current evidence, the last
confirmed prior-state time, first confirmed current-state sample time, and
confirmation time. Confirmation time is not a claim about the exact physical
disconnect time. Repeated disconnected samples do not repeat the transition.
Event subscriptions use unbounded ordered streams so slow consumers do not
silently lose transition history. Current-state streams use a latest-value
buffer. Cancelling either subscription does not stop the center.

The center increments `linkEpoch` after confirmed disconnect/reassociation,
interface change, or continuity reset. A run session ID, interface identity,
and epoch together identify one continuity segment. Sleep/wake and app resume
reset continuity; samples on the far side establish a new baseline rather than
being joined into a synthetic transition.

## Listener ownership and lifecycle

The center serializes collection and starts one compensation sampler. Its
trigger registers `SCDynamicStore` notifications for the current interface's
Link key and service IPv4 changes, plus CoreWLAN power events when the shared
delegate is available. Notifications only request a fresh sample. Registration
errors are retained; SystemConfiguration and compensation sampling continue
if CoreWLAN event registration fails. The trigger removes its registrations on
stop. Repeated start/stop and multiple scanner consumers are idempotent; stopping
one `WiFiPowerMonitor` subscription does not stop the center.

The existing `NetworkInterfaceSnapshot` full scan remains unchanged in shape.
Its Wi-Fi link fields now use the same field capture helper as the lightweight
collector, while lightweight sampling avoids DNS, gateway, and full interface
enumeration. Both retain their caller-provided cycle ID and capture timestamp.

## Formal app validation

The real signed/sandboxed application has not yet been exercised on a device.
The independent `tools/wifi-link-lab/` collector does not establish app
capability and must not be used as a substitute.

For a local Debug run, set `WIFILENS_LINK_DIAGNOSTICS=1` in the app's launch
environment. The app writes `observations.jsonl`, `events.jsonl`, an empty
`markers.jsonl`, and `environment.json` under its sandboxed
`Library/Application Support/WiFiLens/Diagnostics/` directory. The logger is
compiled only in Debug and does not write SSID/BSSID values. It requires no
network access and adds no product UI. For example, launch the built app with:

```sh
WIFILENS_LINK_DIAGNOSTICS=1 open "/path/to/WiFi Lens.app"
```

After the app is running, manually turn Wi-Fi off and on, then keep Wi-Fi on
while making a test access point unavailable and restoring it (for example by
turning off a test router or phone hotspot). Allow several samples after each
operation. Copy the app's Diagnostics directory locally for review. The
existing offline analyzer can read the same JSONL filenames:

```sh
python3 tools/wifi-link-lab/analyze.py --input-dir "/path/to/Diagnostics"
```

Review the local source logs before sharing them. Final confirmation remains
pending until Debug app behavior and the actual release signing/sandbox
conditions are validated on the intended macOS environment.

## Known limits

- The signed and sandboxed production capability is unverified.
- CoreWLAN `none` and power-off values are intentionally treated as ambiguous.
- Negative link evidence cannot produce a confirmed disconnect under the
  default policy until the formal app experiment validates the complete rule.
- Existing scan and historical observation invalidation remains outside this
  center and is a later migration step.
