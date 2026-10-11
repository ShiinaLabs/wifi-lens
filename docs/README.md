# Project Documentation Index

This directory contains project documentation for human maintainers and agents.

## Project tracking

| File | Purpose |
|------|---------|
| [TODO.md](TODO.md) | Planned features, engineering work, and product directions |
| [ISSUES.md](ISSUES.md) | Current known defects, regressions, and deferred items |

`TODO.md` records work that has not been done yet. Completed items are removed
rather than archived. `ISSUES.md` records active problems and explicitly
deferred items — resolved issues are removed unless they carry long-term
context.

## Agent-oriented technical references

Agent-optimized technical knowledge (architecture, testing, accessibility,
BLE, charts, MCP, regulatory, windowing) lives under
[`.agents/references/`](../.agents/references/README.md). These references are
organized for on-demand loading by task type and are not duplicated here.

## Architecture

| File | Purpose |
|------|---------|
| [architecture/product-modularization.md](architecture/product-modularization.md) | Human-maintainer record of public module ownership and edition-neutral composition |
| [architecture/xcode-framework-migration.md](architecture/xcode-framework-migration.md) | Migration of repository-owned local packages to native Framework and test targets |
| [architecture/public-project-boundary.md](architecture/public-project-boundary.md) | Public Xcode target, scheme, source, and package ownership policy |
| [architecture/WIFI_LINK_STATE.md](architecture/WIFI_LINK_STATE.md) | Shared Wi-Fi link evidence, state, event, listener, and app-validation contracts |

## Research

| File | Purpose |
|------|---------|
| [research/wifi-link-state-source-audit.md](research/wifi-link-state-source-audit.md) | Source-level comparison of Wi-Fi link-state observations, consumers, authorization gates, and signing configuration |

## Contribution and policy documents

| File | Purpose |
|------|---------|
| [`.github/CONTRIBUTING.md`](../.github/CONTRIBUTING.md) | Contribution guide for human contributors |
| [`SECURITY.md`](../SECURITY.md) | Security policy and vulnerability reporting |
| [`LICENSE`](../LICENSE) | Apache License 2.0 |
