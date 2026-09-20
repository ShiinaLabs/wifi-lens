# MCP Server

The app runs an embedded MCP Streamable HTTP server on `127.0.0.1:19840`, exposing live Wi‑Fi scan data via JSON‑RPC 2.0 tools. No external network access — only processes on the same machine can reach it.

MCP is a minimal read-only data source, not a diagnostic engine. Tools return facts from the latest scan snapshot; the connected AI client performs filtering, ranking, explanation, and recommendations. MCP does not trigger scans or expose historical, BLE, automation, or control functionality.

## Protocol

- **Transport**: MCP Streamable HTTP (`StatelessHTTPServerTransport` from `swift-mcp-server`)
- **Encoding**: JSON‑RPC 2.0 over HTTP/1.1 `POST`, `Content‑Type: application/json`
- **Server identity**: `WiFi Lens` v1.0.0, capabilities: `tools` with `listChanged`
- **Startup**: Runs when `ScannerViewModel` starts scanning (Wi-Fi on) and stops
  when scanning stops.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/` | JSON‑RPC requests (`initialize`, `tools/list`, `tools/call`, `ping`) |
| `GET`  | `/` | SSE stream (notifications, session ID) |

## Tools

### `scan_networks`

List nearby Wi‑Fi networks. Returns an array of network objects.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `band` | `"24"` \| `"5"` \| `"6"` | No | Filter by frequency band |

**Response** — array of `NetworkEntry` objects:

```json
[
  {
    "ssid": "MyWiFi",
    "bssid": "aa:bb:cc:dd:ee:ff",
    "rssi": -48,
    "channel": 6,
    "band": "24",
    "channelWidthMHz": 20,
    "phyMode": "ax",
    "channelWidth": "80",
    "supports80211k": true,
    "supports80211r": false,
    "supports80211v": true,
    "supports80211w": true,
    "supportsWPA3": true,
    "isHiddenSSID": false,
    "security": "WPA3-Personal",
    "mcs": "0-11",
    "nss": "2",
    "country": "US"
  }
]
```

Fields are derived from the latest scan and parsed Information Elements (IE). `phyMode` labels are `ax` (Wi‑Fi 6/6E), `ac`, `n`, or empty. `channelWidth` is the IE-derived current operating width: `160`, `80`, `80+80`, `40`, `20`, or empty when the width is unknown, with VHT Operation values taking precedence over HT Operation. VHT Operation `0` defers to HT Operation; `1` is 80 MHz unless center-frequency segments identify the interop form of 160 or 80+80, while direct values `2` and `3` retain their 160 and 80+80 meanings. An HT Operation secondary-channel offset of `0` produces a known `20`; offsets `1` and `3` produce `40` only when the STA Channel Width bit is set, otherwise the operation is treated as explicit `20`; a reserved offset or missing/malformed HT Operation remains empty. HT Capabilities support alone does not produce a `40` result. Scalar observation storage and Spectrum geometry continue to use their existing CoreWLAN width fallback for non-contiguous `80+80` because segment-aware geometry is not modeled yet.

### `get_network_detail`

Get detailed information for a single network by BSSID.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `bssid` | string | Yes | MAC address, e.g. `"aa:bb:cc:dd:ee:ff"` |

Same response shape as `scan_networks` entries, plus `isIBSS: bool`.

Returns error `{"error":"network not found"}` when the BSSID isn't in the current scan set, and `{"error":"missing required parameter: bssid"}` when the parameter is absent.

### `get_channel_occupancy`

Channel occupancy counts grouped by band. No parameters.

```json
{
  "24": { "1": 3, "6": 5, "11": 2 },
  "5": { "36": 1, "149": 4 },
  "6": {}
}
```

### `get_scan_metadata`

Return factual context for the latest scan snapshot. Takes no parameters and triggers no scan.

Fields are omitted when unavailable:

```json
{
  "capturedAt": "2026-08-26T04:00:00Z",
  "interfaceName": "en0",
  "isScanning": true,
  "powerState": "poweredOn",
  "accessState": "scanning",
  "supportedBands": ["24", "5", "6"],
  "scanIntervalSeconds": 3
}
```

`capturedAt` is the observation pipeline timestamp, not the time the MCP request arrived. When Wi-Fi power is off or the interface is unavailable, stale network and capture context is suppressed.

Field semantics: `isScanning` indicates whether the scanner is currently executing a scan loop (true while a scan cycle is in flight, false between cycles or when scanning is stopped). `accessState` represents the Wi-Fi authorization and availability stage (`waitingForAuthorization`, `denied`, `scanning`, `grantedButSSIDUnavailable`, or `scanFailed`). Both can be true simultaneously, but they describe different things: `isScanning` is runtime activity, `accessState` is permission/state.

## Integration

Clients that speak MCP Streamable HTTP can connect directly:

```json
// → {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18",...}}
// → {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"scan_networks"}}
```

For ad‑hoc scripting, any HTTP client works:

```sh
# List tools
curl -s -X POST http://127.0.0.1:19840/ \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'

# Scan networks
curl -s -X POST http://127.0.0.1:19840/ \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"scan_networks"}}'
```

### Assisted client setup

Settings provides **Copy AI setup prompt**. The prompt is client-neutral: it asks an MCP-compatible coding assistant to add or update only the `wifi-lens` entry, preserve unrelated configuration, use the client's native format, keep the server on `127.0.0.1`, and verify the tool list afterward.

Codex-style clients use Streamable HTTP entries in TOML:

```toml
[mcp_servers.wifi-lens]
url = "http://127.0.0.1:19840/"
```

Claude Desktop and other JSON-based MCP clients merge a Streamable HTTP entry:

```json
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840/"
    }
  }
}
```

If the user changed the app's MCP port, replace `19840` with the configured port. Do not document command-based stdio launches or remote/tunneled URLs; this server is local-only.

## Architecture

```
ScannerViewModel.makeMCPSnapshot()
  └── MCPServer.snapshotProvider (closure, lock-protected, MainActor-read)
        └── handleCallTool(name:arguments:snapshot:)
              └── Tool dispatch (scan_networks / get_network_detail / get_channel_occupancy / get_scan_metadata)
                    └── JSON serialization → CallTool.Result
```

`ScannerViewModel.makeMCPSnapshot()` returns a `MCPSnapshot` (Sendable) through `MCPServer.snapshotProvider` (lock-protected, MainActor-read) so every tool invocation reads the most recent scan without extra copies.

## Non-goals

- Rescan, connect, forget-network, settings-change, or other control actions
- Network Self-Check or LAN/Internet probes
- Signal history, persistence, trend computation, or before/after comparison data
- Bluetooth discovery or coexistence data
- Channel scores, recommendations, interference labels, or diagnostic conclusions
- Automation workflows
- LAN, tunnel, or public-network exposure
- New permissions, entitlements, or external network dependencies
