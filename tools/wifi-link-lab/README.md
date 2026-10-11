# Wi-Fi Link Lab

Wi-Fi Link Lab is an independent, operator-led experiment tool. It is separate from the WiFi Lens app and does not run inside the app sandbox; CLI and app permission checks therefore run in distinct process contexts. The tool records time-correlated observations and operator markers. It does not infer that the device is connected or disconnected.

## Run

The single user-facing command is:

```sh
./tools/wifi-link-lab/run.sh
```

The experiment driver accepts the compiled collector binary as its required argument, launches that binary directly (never recursively launching `run.sh`), and waits for a valid schema v1 sample before showing scenario instructions. It calls `analyze.py` after collection; the analyzer writes the final sanitized `report.zip`. No outer archive of the raw evidence directory is created. The default output directory is `~/Desktop/WiFiLens-LinkProbe-<timestamp>`; `run.sh` falls back to `~/Library/Logs/WiFiLens-LinkProbe-<timestamp>` if the Desktop output location cannot be used.

The collector and driver require macOS 14 or later, Xcode Command Line Tools, and Python 3. All radio, access-point, network, and permission changes are manual. The tool makes no network calls and does not change Wi-Fi or system settings itself.

## Evidence and privacy

The collector writes `observations.jsonl`, `events.jsonl`, and non-identifying runtime metadata. Samples use `schemaVersion: 1` and contain UTC timestamps, monotonic timing, Wi-Fi/system observation fields, and per-field errors. The driver writes `markers.jsonl` with scenario/action start and completion markers, skip reasons, and interruptions. A skipped, incomplete, interrupted, or unrun scenario is not a pass.

Do not record SSIDs, BSSIDs, IP or MAC addresses, router addresses, hostnames, serial numbers, location, credentials, or raw network names. The analyzer sanitizes its report bundle and includes only allowlisted report inputs. Preserve the evidence directory for local investigation; share only `report.zip` after reviewing it.

## Guided scenarios

Every manual action is bracketed by start/completion markers. The prescribed observation interval begins after the operator confirms the action. Scenarios can be skipped at the start; an action-level skip stops the remainder of that scenario and records a reason. Optional scenarios may be skipped. Scenarios not run are not passes.

- **A — Normal connection:** establish a normal Wi-Fi connection and observe for 20 seconds.
- **B — Radio off and recovery:** turn Wi-Fi off and observe for at least 15 seconds; turn it on and observe recovery for 20 seconds.
- **C — Access point disappears and returns:** keep the device radio on, make the test access point unavailable and observe for 20 seconds; restore it and observe for 20 seconds.
- **D — Manual disassociation (optional):** if the system provides a manual disassociate action, use it without turning Wi-Fi off and observe for 20 seconds; restore the connection and observe for 20 seconds. Skip if unavailable.
- **E — Network A-to-B switch:** connect to test network A and observe for 20 seconds, then switch to network B and observe for 20 seconds.
- **F — CLI permission context (optional):** record and, if identifiable, change only the permission relevant to the command-line runtime; observe each state for 20 seconds.
- **G — App permission context (optional):** separately record and, if identifiable, change only the app permission; observe each state for 20 seconds.

CLI and app permission contexts are intentionally separate: the CLI collector runs outside the app sandbox and cannot establish what the app can observe. Do not change unrelated permissions; skip a permission scenario if its scope cannot be identified. For any interrupted run, Ctrl+C records an interrupted/incomplete marker, stops only the collector child started by the driver, preserves existing evidence, and still attempts analysis and report ZIP creation.

## Interpretation limits

The report is descriptive and based on the evidence collected in a real-device run. It does not prove causation, establish an app's observation capability, or conclude that Wi-Fi disconnected. Until an operator completes and reviews a real experiment, results remain pending user-run validation.
