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

The center schedules one independent review capture for the first candidate in
a continuous candidate cycle. Its interval is injectable and bounded from
100 ms to 10 s; the current default is a provisional 1 s diagnostic interval,
not a domain rule. Notifications and periodic compensation sampling coalesce
with this review. Each capture has a distinct cycle ID and capture interval.
After the review completes, ordinary compensation samples continue updating
evidence but cannot restart active review for the same continuous candidate
cycle. Trusted association, conflicting evidence, failed sampling, interface
change, sleep/wake, or a session restart ends or invalidates that cycle.

**Production disconnect confirmation remains disabled.** A public Debug app
run verified the sampler, both listener registrations, and the observed
access-point-loss signature. The provided run summary does not include a
truth-labeled negative-control interval demonstrating that the same pattern
never occurs during normal operation, roaming, or lifecycle changes. In
addition, CoreWLAN mode `none` still has no independent read-success bit.
Accordingly, production candidates remain `unknown` and do not emit disconnect
or recovery events. Tests can inject the strict confirmation policy with
synthetic evidence. The first observed association or non-association remains
a baseline and does not create a transition event.

The public `WiFiLinkEvidenceValidator.assessment(for:)` is the shared consumer
boundary for a current status. It checks cycle, timestamp, interface name,
available interface indices, exact optional SSID/BSSID agreement, and then
re-evaluates the raw evidence with `WiFiLinkInterpreter`. Timeline and Pro
analysis must use this result rather than maintaining separate trust checks.
Both identity values may be absent while association is still verified; a
one-sided or conflicting value invalidates the status. Status generation also
derives `isConnected` from this verified assessment, so a mid-snapshot identity
change cannot leave a contradictory connected flag.

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
and epoch together identify one continuity segment. Sleep/wake samples on the
far side establish a new baseline rather than being joined into a synthetic
transition. Ordinary app activation only requests fresh evidence.

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
Consumers that need a current connection status, including the roaming probe,
project this snapshot through `WiFiCurrentConnectionProvider` and the shared
`WiFiLinkInterpreter`. SSID and BSSID remain identity attributes and cannot
establish association on their own.

## Scan execution readiness

Link evidence and scan execution readiness are separate. `WiFiPowerMonitor`
maps only reported-on radio evidence to `poweredOn`; ambiguous `powerOn() ==
false` stays `unknown`. Scanner startup permits one authorized probe while the
evidence is unknown. One or two consecutive unknown samples do not stop an
active scan. Three consecutive unknown samples pause frequent scanning and
schedule a probe after 30 seconds; a reported-on sample resumes scanning
immediately. The compatibility stream carries the center snapshot ID. Its
cached initial value has no sample ID, and repeated delivery of a snapshot is
ignored, so window activation or a simultaneous refresh cannot inflate the
unknown count. An access-point loss while the radio remains on does not stop
spectral scanning and does not change the verified link state by itself.

The scanner treats a missing CoreWLAN interface as an explicit
`interfaceUnavailable` failure, never as a successful empty network list. A
successful scan with zero nearby networks remains a normal empty result. Failed
scans retain the existing three-attempt retry sequence; repeated exhausted
failures then increase the delay between probes from 1 second to a 30-second
cap. A successful scan resets that delay. This bounds work while continuing to
probe for automatic recovery. Scan failures update scanner access state only;
they are not disconnect evidence and do not create link events. Location
authorization remains controlled by the existing authorization manager.

## Observation validity and consumer behavior

Each immutable `WiFiObservation` has one `sourceObservationID`, generated once
when it is constructed. Value copies, accepted Store history, and all Runtime
consumer deliveries preserve that identity. Distinct observations remain
distinct even when timestamps and cycle IDs happen to match. `sourceCycleID`
continues to identify the paired interface snapshot; it is not the observation
identity. Link-evidence and gateway-probe cycle IDs retain their own evidence
boundaries. The scan outcome is explicit on its environment
snapshot: `error == nil` means the network list is a successful result (including
a valid empty list); an error means the list cannot be used to infer presence or
absence. A scan failure can still carry a separately captured current link
assessment. It does not turn that assessment into a disconnect or radio-off
fact.

Runtime suppresses exact replay for a retained source identity and rejects
changed content that reuses that identity before the Store or consumers receive
it. Timeline event IDs remain independent from source observation IDs.

`WiFiObservationStore.apply` replaces every current projection on each accepted
cycle, including clearing values the cycle did not measure. Per-domain
validity distinguishes current, failed, not tested, and age-expired data. The
latest 120 full cycles remain available in chronological history; history is
not used as a current value. Late observations are retained in history but
cannot replace a newer current projection. RSSI/network history remains in its
existing history store.

Current validity expires after 15 seconds. The store publishes the expiry at
that boundary so views update even when no later observation arrives. Scan
derived validity is also scoped to the active scan lifecycle; a prior cycle
cannot become current merely because a new scan starts. MCP network data is
current only while scanning is active and the latest complete environment
result is successful and within the same age bound; stopped, failed, or expired
scans return no current network list while full-cycle history remains available.

The scanner's current network list and channel results clear on a failed scan;
signal-history queries remain available. Gateway probing, environment analysis,
quality, and diagnosis are not produced from a failed environment scan. A fresh
link status from that cycle remains independently available. Overview and
Interfaces use a fresh `WiFiCurrentStatus.linkAssessment` to label association;
SSID/BSSID are display identity only, and interface type comes from explicit
interface discovery. Connection quality, gateway latency in quality evaluation,
and current-network/current-channel markers require the shared validator to
confirm association for that exact status cycle. Missing RSSI remains unknown;
environmental channel analysis still runs without an associated network. The
public roaming test uses the same validator and records an AP transition only
between confirmed samples with matching interface and known logical-network
identity and an uninterrupted sampling interval. Unknown samples reset its
roaming baseline.

AP Radar changes target presence only after a successful
environment scan. On failure or scan lifecycle pause it stops pulse/audio,
invalidates the live RSSI display, and waits for a new successful sample before
tracking resumes. A failed scan never means the tracked AP disappeared. A
one-shot freshness deadline also invalidates RSSI when the scan source stalls
without reporting success or failure; this suppresses stale audio and display
values but does not report the target as lost. A fresh successful sample is
required to resume tracking.

Window or app-focus activation only requests a new center sample. It does not
reset continuity or increment `linkEpoch`; actual sleep/wake and interface
changes retain their continuity-reset behavior. The app owns one shared center
and terminates it through the existing process termination coordinator.

## Formal app validation

The public Debug app has been exercised in its sandbox. The independent
`tools/wifi-link-lab/` collector does not establish app capability and must not
be used as a substitute. The Debug run recorded 97 valid samples (32
associated and 60 candidate samples), successful SystemConfiguration and
CoreWLAN event registration, 44 active-review schedules, and 40 review
executions. During access-point loss it observed raw mode 0, radio on,
`Link.Active == false`, service active, and both interface flags true. This
validates the real app sampling and candidate path for that scenario; it does
not establish the false-positive rate under negative controls or the release
signing/runtime environment.

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
failure directly, so both outcomes can be checked. Another full access-point
loss run is not required to reproduce the already observed signature. To
consider enabling production confirmation later, the logs must also establish
a marked normal-operation control (including an associated baseline and
recovery) and show no candidate during an interface or sleep/wake continuity
reset. If the existing run's markers and complete local JSONL files do not
contain that negative-control window, the smallest additional experiment is a
short marked control interval during normal connected operation plus one
sleep/wake or interface-change cycle; the prior access-point-loss evidence can
be reused.

```sh
python3 tools/wifi-link-lab/analyze.py --input-dir "/path/to/Diagnostics"
```

Review the local source logs before sharing them. Final confirmation remains
pending until Debug app behavior and the actual release signing/sandbox
conditions are validated on the intended macOS environment.

## Known limits

- The release signing/runtime environment has not been validated.
- CoreWLAN `none` and power-off values are intentionally treated as ambiguous.
- Production disconnect confirmation remains off until negative-control
  evidence validates that the candidate signature is specific to lost
  association.
- Link state, scan readiness, scan outcome, current observation validity, and
  retained historical observations are separate contracts. Scan failure or an
  unavailable interface must not be interpreted as loss of Wi-Fi association.
