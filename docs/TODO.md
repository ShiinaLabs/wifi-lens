# TODO

## Product

- [x] Keep MCP positioned as a minimal read-only local-data source: preserve the existing three-tool compatibility surface, document that AI clients perform the analysis, and consider `get_scan_metadata` only if it can expose authoritative scan context that cannot be inferred from the latest network array (done: kept three compatible raw-data tools, added factual get_scan_metadata, documented AI-side analysis boundary)
- [ ] Integrate SpectrumPanelView filter with `APFilterQueryParser` (support structured queries like `band:5G AND rssi:>-60`) — shelved: pending product decision (parser ready, strict comparators fixed)
- [ ] RSSI threshold alert (notify when a monitored network drops below a configurable threshold)
- [ ] Unify export into a single reporting flow: multi-band export, richer CSV schema, and session snapshots suitable for sharing/debugging
- [ ] Turn signal history into a first-class session model: persisted timelines, monitored SSIDs, threshold alerts, and historical comparisons

## Engineering

- [x] Complete Network Self-Check hardening: correct default-route gateway selection and interface-bound probing first, then partial reports, bounded reruns, proxy/stage assessment, evidence-based remediation, and bounded logs; local verification complete, with live dual-adapter and network-switch coverage still requiring manual hardware testing.
- [ ] UI / integration tests (9 UI test files exist in `WiFiLensUITests`; excluded from the default test plan per AGENTS.md and not yet wired into CI — pending decision: run in a dedicated CI job, or prune)
- [ ] Add a small verification matrix for UI regressions across light/dark mode, localization, and no-permission / no-data states
- [x] Before the next Mac App Store submission, update the app privacy description to disclose that Network Self-Check may connect to a configured local proxy, in addition to the existing MCP server use case (done: both editions disclose MCP server + Network Self-Check proxy use)

## Out of Scope (for now)

- iOS / iPad support (CoreWLAN is macOS-only)
- LAN device discovery
