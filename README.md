# WiFi Lens

**The complete Mac Wi-Fi troubleshooting workflow.**

WiFi Lens Pro combines live Wi-Fi analysis, network diagnostics, continuous monitoring, Timeline history, Statistics, and Insights in one native macOS app.

**WiFi Lens Pro is the complete WiFi Lens product.**

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>Get WiFi Lens Pro</strong></a>
  &nbsp;·&nbsp;
  <a href="https://wifi-lens.shiinalabs.com">Official Website</a>
</p>

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="Download on the Mac App Store" width="190"></a>
</p>

<p align="center"><img alt="WiFi Lens showing Wi-Fi spectrum analysis on macOS" src="assets/screenshot-hero.webp" width="800"></p>

<p align="center">macOS 14+ &nbsp;·&nbsp; Apple Silicon &amp; Intel &nbsp;·&nbsp; No telemetry</p>

<p align="center">
  🔒 <strong>Local-first privacy</strong> — No accounts, no cloud, no telemetry<br>
  🩺 <strong>Evidence-based diagnostics</strong> — Explainable path, DNS, HTTPS, and proxy checks<br>
  🤖 <strong>MCP for AI workflows</strong> — Connect compatible clients to live Wi-Fi data on your Mac
</p>

<p align="center"><sub>This repository hosts the open-source edition of WiFi Lens for basic local analysis, development, source inspection, and community contributions.</sub></p>

---

<p align="center">
  🇺🇸 English · <a href="README.de.md">🇩🇪 Deutsch</a> · <a href="README.es-ES.md">🇪🇸 Español</a> · <a href="README.fr.md">🇫🇷 Français</a> · <a href="README.zh-Hans.md">🇨🇳 简体中文</a> · <a href="README.ja.md">🇯🇵 日本語</a>
</p>
<p align="center">
  <a href="#why-wifi-lens-pro">Why WiFi Lens Pro</a> · <a href="#core-capabilities">Core Capabilities</a> · <a href="#editions">Editions</a> · <a href="#ai--mcp-integration">AI / MCP</a> · <a href="#open-source-edition">Open-source edition</a> · <a href="#privacy">Privacy</a> · <a href="#get-wifi-lens">Get WiFi Lens</a> · <a href="#development">Development</a> · <a href="#contributing">Contributing</a> · <a href="#license">License</a>
</p>

---

## Why WiFi Lens Pro

Live diagnostics tell you what is happening now. WiFi Lens Pro keeps the story going when a problem is intermittent: it observes, records, preserves history, and helps you investigate what happened later.

| Workflow | What WiFi Lens Pro does |
|----------|--------------------------|
| Diagnose now | Live Wi-Fi analysis, channel analysis, and network diagnostics |
| Keep watching | Menu bar monitoring and continuous observation |
| Capture intermittent problems | Timeline and spectrum recording |
| Review what happened | Historical events and connection changes |
| Find patterns | Statistics across recorded periods |
| Understand the evidence | Insights based on recorded observations |

**WiFi Lens Pro is the complete edition.** It connects the live analyzer with monitoring, history, and investigation instead of treating them as separate tools.

<table>
<tr>
<td width="50%" align="center"><img alt="Network Self-Check diagnostics view" src="assets/screenshot-selfcheck.webp" width="100%"><sub>Network Self-Check</sub></td>
<td width="50%" align="center"><img alt="Event Timeline showing connection history" src="assets/screenshot-timeline.webp" width="100%"><sub>Event Timeline (Pro)</sub></td>
</tr>
</table>

### Diagnose now → investigate later

Wi-Fi problems often disappear before you can inspect them. WiFi Lens Pro helps you keep evidence across a drop, roam, or signal change so you can review the event and the surrounding network conditions later.

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>Get WiFi Lens Pro →</strong></a>
</p>

---

## Core Capabilities

WiFi Lens brings the essential tools for understanding a local Wi-Fi environment into one native Mac app.

| Capability | What it helps you do |
|------------|----------------------|
| 📡 Wi-Fi scanning | Scan nearby networks across 2.4, 5, and 6 GHz bands |
| 📊 Spectrum and channel quality | See occupancy, congestion scores, and regional channel recommendations |
| 🔍 Network details | Inspect PHY generation, channel width, 802.11k/r/v, WPA3, and connection details |
| 🚶 Roaming and heatmap | Validate AP handoffs and compare per-band occupancy |
| 🩺 Network Self-Check *(Preview)* | Run path, DNS, HTTPS, and configured proxy reachability checks |
| 📻 AP Radar *(Preview)* | Track a selected AP with RSSI-based guidance and optional audio feedback |
| 🤖 MCP and export | Connect local AI tools and save charts as PNG or CSV |
| 🔒 Local-first privacy | Keep scan data on your Mac with no usage telemetry |

---

## Editions

### WiFi Lens Pro

**WiFi Lens Pro is the complete edition.** It is a one-time purchase from the [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8) for users who need continuous observation, recording, history, and investigation.

### Open-source edition

The open-source edition provides a substantial subset of live analysis capabilities for users who prefer GitHub distribution or want to inspect and contribute to the codebase. Get it from [GitHub Releases](https://github.com/SHIINASAMA/wifi-lens/releases/latest).

| Capability | WiFi Lens Pro | Open-source edition |
|------------|---------------|---------------------|
| Live Wi-Fi analysis | ✅ | ✅ |
| Network diagnostics | ✅ | ✅ |
| Channel recommendations | ✅ | ✅ |
| Continuous monitoring | ✅ | — |
| Event history | ✅ | — |
| Historical statistics | ✅ | — |
| Insights | ✅ | — |
| Spectrum recording | ✅ | — |
| Menu bar monitoring | ✅ | — |

Both editions are local-first. The difference is the workflow around the live analyzer: Pro adds the context needed to monitor, preserve, and investigate problems over time.

---

## AI / MCP Integration

WiFi Lens includes an embedded MCP server that lets compatible AI assistants read your local Wi-Fi data. Enable it in Settings, choose **Copy AI setup prompt**, and paste the prompt into an MCP-compatible desktop client such as Codex Desktop or Claude Desktop.

```json
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840"
    }
  }
}
```

For manual setup, use the format your client expects:

```toml
# Codex: ~/.codex/config.toml
[mcp_servers.wifi-lens]
url = "http://127.0.0.1:19840/"
```

```json
// Claude Desktop and other JSON-based clients
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840/"
    }
  }
}
```

Once connected, ask your assistant things like *"What channels are congested near me?"* or *"Which nearby networks support WPA3?"*. The server binds to `127.0.0.1` only — nothing leaves your machine unless you deliberately route it elsewhere.

See the [AI Workflows guide](https://wifi-lens.shiinalabs.com/ai-mcp/) for more examples.

---

## Open-source edition

The open-source edition is available for local analysis, development, source inspection, and community contributions.

- **GitHub Releases** — [Download the latest release](https://github.com/SHIINASAMA/wifi-lens/releases/latest)
- **Homebrew** — `brew tap ShiinaLabs/apps && brew install --cask ShiinaLabs/apps/wifi-lens`
- **Source code and documentation** — Browse the repository and [architecture docs](docs/)

<details>
<summary>Open-source edition capabilities</summary>

| Capability | Description | Status |
|------------|-------------|--------|
| 📡 Wi-Fi Scanning | Real-time scan across 2.4 / 5 / 6 GHz bands | Stable |
| 📊 Spectrum View | Gaussian channel occupancy charts | Stable |
| 🎯 Channel Quality | Congestion scores with regional recommendations | Stable |
| 🔍 Network Details | PHY generation, channel width, 802.11k/r/v, WPA3 | Stable |
| 📶 Connection Info | IP, gateway, DNS, MAC, Tx rate, security summary | Stable |
| 🚶 Roaming Test | AP handoff monitoring with session save/load | Stable |
| 🗺️ Channel Heatmap | Per-band occupancy heatmap | Stable |
| 🎧 BLE Scanner | Bluetooth LE discovery, RSSI analysis, tracking | Stable |
| 🎨 Smart Coloring | Deterministic SSID-based color assignment | Stable |
| 🌐 MCP Server | Embedded HTTP API for AI tool integration | Stable |
| 📤 Export | Save charts as PNG or CSV | Stable |
| 🔒 Privacy First | No telemetry; scan data stays on your Mac | Stable |
| ⬆️ Auto-Updates | Sparkle for the GitHub edition | Stable |
| 🌍 Localized | English, German, Spanish, Japanese, Chinese | Stable |
| 🩺 Network Self-Check | One-click path, DNS, HTTPS, and proxy diagnostics | Preview |
| 📻 AP Radar | Track a selected AP with audio pulse feedback | Preview |

</details>

[![Downloads](https://img.shields.io/github/downloads/SHIINASAMA/wifi-lens/WiFiLens.dmg?label=Downloads&displayAssetName=false&color=2563eb)](https://github.com/SHIINASAMA/wifi-lens/releases/latest)
[![Latest release](https://img.shields.io/github/v/release/SHIINASAMA/wifi-lens?label=Latest&color=2563eb)](https://github.com/SHIINASAMA/wifi-lens/releases/latest)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

---

## Privacy

WiFi Lens does not collect usage analytics, crash telemetry, or Wi-Fi scan data.

- **Location Services:** macOS requires this permission to expose Wi-Fi SSID names. WiFi Lens does not read GPS position.
- **Region detection:** Uses system locale, hardware-reported channel list, and nearby AP country codes on-device.
- **Network Self-Check:** Resolves public endpoints (`www.apple.com`, `www.msftconnecttest.com`) and may test reachability of configured proxy endpoints.
- **MCP server:** Binds to `127.0.0.1` only. Local tools access data only after you enable it.
- **Update checks:** The GitHub edition contacts GitHub when you request an update check or enable automatic checks.

📋 [Security Policy](SECURITY.md) · 📝 [Changelog](https://github.com/SHIINASAMA/wifi-lens/releases) · ❓ [FAQ](https://wifi-lens.shiinalabs.com/faq/) · 🌐 [Full privacy policy](https://wifi-lens.shiinalabs.com/privacy/)

---

## Get WiFi Lens

Requires **macOS 14 (Sonoma) or later**. Works on both Intel and Apple Silicon. 6 GHz scanning requires Wi-Fi 6E/7 hardware.

### WiFi Lens Pro

The complete edition for continuous monitoring, recording, history, and investigation. Get it from the [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8).

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="Download on the Mac App Store" width="190"></a>
</p>

### Open-source edition

For GitHub distribution and community development:

- [GitHub Releases](https://github.com/SHIINASAMA/wifi-lens/releases/latest)
- Homebrew: `brew tap ShiinaLabs/apps && brew install --cask ShiinaLabs/apps/wifi-lens`
- Source code: this repository

> [!IMPORTANT]
> On macOS 14+, **Location Services** must be enabled for the app to read Wi-Fi SSID names. Go to **System Settings → Privacy & Security → Location Services** and enable WiFi Lens when prompted.

---

## Development

```sh
git clone https://github.com/SHIINASAMA/wifi-lens
cd wifi-lens
git submodule update --init ChartLens
cd WiFiLens

# Build
xcodebuild -project WiFiLens.xcodeproj -scheme "WiFi Lens" \
  -configuration Debug -destination 'platform=macOS' build

# Run unit tests
xcodebuild -project WiFiLens.xcodeproj -scheme "WiFi Lens" \
  -configuration Debug -destination 'platform=macOS' \
  -skipPackageUpdates test -only-testing:WiFiLensTests
```

Architecture docs live in [docs/](docs/).

---

## Contributing

Questions, bug reports, and feature ideas are welcome. See [Contributing Guidelines](.github/CONTRIBUTING.md) for setup, pull request conventions, and localization requirements.

Join **[Rabbit Hole](https://discord.gg/gH6sTCYaJ7)**, a small community for WiFi Lens and other projects.

**Contact:** [@WiFiLens on X](https://x.com/WiFiLens) · [wifi-lens@shiinalabs.com](mailto:wifi-lens@shiinalabs.com)

---

## License

Forked from [tiny-wifi-analyzer](https://github.com/nolze/tiny-wifi-analyzer). MAC vendor data from the [IEEE Registration Authority](https://standards.ieee.org/products-programs/regauth/) — see [Third-Party Notices](docs/THIRD-PARTY-NOTICES.md).

Apache License 2.0 © 2020 nolze, 2026 SHIINASAMA — see [LICENSE](LICENSE).
