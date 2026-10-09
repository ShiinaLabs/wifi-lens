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
no-mode, reported-on radio, and inactive system link evidence agree. A real
access-point-loss experiment observed this combination while CoreWLAN service
activity, `IFF_UP`, and `IFF_RUNNING` remained true. Those fields are retained
as auxiliary evidence; they are not required to be false and do not define link
association. `Link.Detaching` is also auxiliary context. Mode `none` remains
ambiguous because its API result alone does not prove that the read succeeded.

The center schedules an independent, one-shot review capture after a new
candidate. The interval is injectable and bounded from 100 ms to 10 s; the
current default is a provisional 1 s diagnostic interval, not a domain rule.
Notifications and periodic compensation sampling coalesce with this review.
Each capture has a distinct cycle ID and capture interval. A candidate remains
`unknown` by default: production disconnect confirmation is disabled because
the evidence has not been validated in the signed, sandboxed app. Repeated
candidate samples cannot generate disconnect events. Tests can explicitly
enable confirmation with synthetic evidence, but this does not enable it in
the application.

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

The center serializes collection and starts one compensation sampler. Every
capture is bound to its run session and lifecycle generation. Results that
return after stop, restart, sleep, or an interface change are discarded and
logged; they cannot update the new session. A failed capture invalidates the
current evidence but does not mean the radio or link is disconnected. Its
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

The normal public Debug app starts the shared center at process startup, even
when no window is open. Unit-test hosts, UI-test mode, and controlled demo
sessions do not start real system monitoring. The app termination coordinator
stops the scanner subscription and center.

To enable diagnostics in Xcode, open **Product > Scheme > Edit Scheme > Run >
Arguments > Environment Variables**, add `WIFILENS_LINK_DIAGNOSTICS` with value
`1`, then run the normal **WiFi Lens** scheme. The `environment.json` file has
`diagnosticsEnabled: true`; `events.jsonl` records `centerStarted` and the
SystemConfiguration/CoreWLAN registration outcomes. `observations.jsonl`
records capture start/end times, monotonic bounds, raw mode and interpretation,
candidate/review decisions, and failed or stale captures. The logger is
compiled only in Debug, writes asynchronously, caps each JSONL at 4 MiB, and
never writes SSID/BSSID values. It needs no network access and adds no product
UI.

The files are under the app's sandboxed
`~/Library/Containers/<bundle-id>/Data/Library/Application Support/WiFiLens/Diagnostics/`
directory. If the bundle ID is not known, locate it with:

```sh
find ~/Library/Containers -path '*/Library/Application Support/WiFiLens/Diagnostics' -type d -print
```

After launch, append scenario markers immediately before and after each manual
operation. This copy-paste command uses only Python's standard library and
writes the schema understood by the existing analyzer:

```sh
LOGDIR="$HOME/Library/Containers/<bundle-id>/Data/Library/Application Support/WiFiLens/Diagnostics"
python3 -c 'import datetime,json,sys,time; p,scenario,kind=sys.argv[1:]; row={"schemaVersion":1,"time":datetime.datetime.now(datetime.timezone.utc).isoformat(),"monotonicNanoseconds":time.monotonic_ns(),"scenarioName":scenario,"markerType":kind}; open(p,"a",encoding="utf-8").write(json.dumps(row)+"\n")' "$LOGDIR/markers.jsonl" "AP lost while Wi-Fi on" scenario_started
```

Use `scenario_completed` for the matching closing marker. Replace the scenario
with `Wi-Fi radio off` for the radio toggle, or `AP lost while Wi-Fi on` for
the access-point test. For each test, run the start marker, perform the action,
then run the completion marker. Manually toggle Wi-Fi off and on; with Wi-Fi
on, make a test access point unavailable and restore it (for example, turn off
a test router or phone hotspot). Wait for several samples after each action.
The log records SystemConfiguration and CoreWLAN registration success or
failure directly, so both outcomes can be checked.

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
