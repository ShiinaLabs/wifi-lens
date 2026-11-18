# WiFi Lens Pro

**Understand what's happening with your Wi-Fi.**

Live Wi-Fi analysis, network diagnostics, and the history to investigate problems that come and go — together in a native macOS app.

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="Get WiFi Lens Pro" width="190"></a>
</p>

<p align="center"><a href="https://wifi-lens.shiinalabs.com/?utm_source=github&amp;utm_medium=readme&amp;utm_campaign=github_readme">Official Website</a></p>

<p align="center"><img src="assets/screenshot-network-experience.webp" alt="WiFi Lens Pro Network Experience showing observed connection reliability" width="800"></p>

<p align="center"><sub>macOS 14.6+ · Intel &amp; Apple Silicon · One-time purchase</sub></p>

---

<p align="center">
  🇺🇸 English · <a href="README.de.md">🇩🇪 Deutsch</a> · <a href="README.es-ES.md">🇪🇸 Español</a> · <a href="README.fr.md">🇫🇷 Français</a> · <a href="README.zh-Hans.md">🇨🇳 简体中文</a> · <a href="README.ja.md">🇯🇵 日本語</a> · <a href="README.zh-Hant.md">🇭🇰 繁體中文</a>
</p>

<p align="center">
  <a href="#why-wifi-lens-pro">Why Pro</a> · <a href="#core-capabilities">Live tools</a> · <a href="#editions">Editions</a>
</p>

---

## Why WiFi Lens Pro

Wi-Fi problems are not always there when you look for them. WiFi Lens Pro combines the tools to investigate your connection now with the observations you can review later.

### See what is happening now

Explore nearby Wi-Fi networks, check channel congestion, and run network checks when a connection behaves unexpectedly. These live tools are part of the complete Pro workflow.

### Keep an eye on your connection

Check connection information from the menu bar. When you need a longer view, optional background observation can continue after the Pro app closes. It is off by default and pauses when your Mac sleeps.

### Investigate what happened

Network Experience helps assess reliability across observed periods. Historical Baseline compares saved gateway-latency measurements with a compatible reference, while Problem History brings recorded findings and supporting evidence together for follow-up.

<table>
<tr>
<td width="50%" align="center"><img src="assets/screenshot-historical-baseline.webp" alt="Historical Baseline comparing saved gateway latency with an earlier reference" width="100%"><sub>Historical Baseline</sub></td>
<td width="50%" align="center"><img src="assets/screenshot-problem-history.webp" alt="Problem History with recorded findings and supporting evidence" width="100%"><sub>Problem History</sub></td>
</tr>
</table>

<p align="center"><a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>Get WiFi Lens Pro</strong></a></p>

---

## Core Capabilities

The live tools you use for everyday troubleshooting are built into Pro too:

- **Wi-Fi analysis** — Scan 2.4, 5, and 6 GHz networks; compare signal, channel activity, congestion, security, and regional channel recommendations.
- **Network Check** — Inspect the path from your Mac through the local network to the internet, including gateway reachability, DNS, HTTP/HTTPS, optional IPv6, and proxy routing.
- **More local tools** — Roaming and channel heatmap, AP Radar, local MCP integration, and chart exports. The repository also includes the free edition of these live tools.

<p align="center"><img src="assets/screenshot-hero.webp" alt="WiFi Lens Wi-Fi analysis overview with channel quality and recommendations" width="800"></p>
<p align="center"><img src="assets/screenshot-selfcheck.webp" alt="Network Check showing results across This Mac, LAN, and Internet" width="800"></p>

---

## Editions

### WiFi Lens Pro
WiFi Lens Pro is a one-time purchase from the [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8). It adds menu-bar status monitoring, Network Experience, Problem History, spectrum recording, optional background observation, and a carrier-specific Wi-Fi Calling Test. Historical Baseline is part of Network Experience.

### Open-source edition

The free open-source edition provides live Wi-Fi analysis and local network diagnostics. Download it from [GitHub Releases](https://github.com/ShiinaLabs/wifi-lens/releases/latest), install it with Homebrew, or inspect and contribute to the source.

| Capability | WiFi Lens Pro | Open-source edition |
|------------|---------------|---------------------|
| Live Wi-Fi analysis | ✅ | ✅ |
| Network diagnostics | ✅ | ✅ |
| Channel recommendations | ✅ | ✅ |
| MCP integration | ✅ | ✅ |
| Menu-bar status monitoring | ✅ | — |
| Network Experience and Historical Baseline | ✅ | — |
| Problem History | ✅ | — |
| Spectrum recording | ✅ | — |
| Optional background observation | ✅ | — |
| Wi-Fi Calling Test | ✅ | — |

Both editions process Wi-Fi scans on your Mac. Pro adds history-based analysis, recording, optional background observation, and the Wi-Fi Calling Test.

---

## AI / MCP Integration

WiFi Lens includes an optional local MCP server. When enabled, compatible clients can request live Wi-Fi scan data from this Mac. Add the server in an MCP-compatible client such as Codex Desktop or Claude Desktop.

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

Once connected, ask your assistant things like *"Which channels are congested near me?"* or *"Which nearby networks support WPA3?"*. The MCP server listens on `127.0.0.1`; a connected client or model provider may handle data it receives according to its own policies and settings.

See the [AI Workflows guide](https://wifi-lens.shiinalabs.com/ai-mcp/?utm_source=github&utm_medium=readme&utm_campaign=github_readme) for more examples.

---

## Open-source edition

WiFi Lens OSS is free and open source. Use it for live local analysis, development, source inspection, and community contributions.

- **GitHub Releases** — [Download the latest release](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
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
| 📻 AP Radar | Track a selected AP with RSSI-based guidance and optional audio feedback | Stable |
| 🎧 BLE Scanner | Bluetooth LE discovery, RSSI analysis, tracking | Stable |
| 🎨 Smart Coloring | Deterministic SSID-based color assignment | Stable |
| 🌐 MCP Server | Embedded HTTP API for AI tool integration | Stable |
| 📤 Export | Save charts as PNG or CSV | Stable |
| 🔒 Privacy First | No telemetry; scan data stays on your Mac | Stable |
| ⬆️ Auto-Updates | Sparkle for the GitHub edition | Stable |
| 🌍 Localized | English, French, German, Japanese, Russian, Simplified Chinese, Spanish, Traditional Chinese | Stable |
| 🩺 Network Self-Check | Connectivity, DNS, HTTPS, IPv6, and configured proxy checks | Stable |
| 📜 Open-source licenses | Review included components, licenses, and notices in the app | Stable |

</details>

[![Downloads](https://img.shields.io/github/downloads/ShiinaLabs/wifi-lens/WiFiLens.dmg?label=Downloads&displayAssetName=false&color=2563eb)](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
[![Latest release](https://img.shields.io/github/v/release/ShiinaLabs/wifi-lens?label=Latest&color=2563eb)](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

---

## Privacy

WiFi Lens does not upload Wi-Fi scan records to its application services and does not collect usage analytics or telemetry.

- **Location Services:** macOS requires this permission to expose Wi-Fi SSID names. WiFi Lens does not read GPS position.
- **Region detection:** Uses system locale, hardware-reported channel list, and nearby AP country codes on-device.
- **Network Self-Check:** Sends diagnostic probes to public endpoints and, when applicable, configured proxy endpoints. Evidence is stored locally.
- **MCP server:** Optional and bound to `127.0.0.1`. Connected clients and model providers handle received data under their own policies and settings.
- **Background observation:** Optional in Pro and off by default. Observations are stored locally; collection pauses while your Mac sleeps.
- **Update checks:** The GitHub edition contacts GitHub when you request an update check or enable automatic checks.

📋 [Security Policy](SECURITY.md) · 📝 [Changelog](https://github.com/ShiinaLabs/wifi-lens/releases) · ❓ [FAQ](https://wifi-lens.shiinalabs.com/faq/?utm_source=github&utm_medium=readme&utm_campaign=github_readme) · 🌐 [Full privacy policy](https://wifi-lens.shiinalabs.com/privacy/?utm_source=github&utm_medium=readme&utm_campaign=github_readme)

---

## Get WiFi Lens

Requires **macOS 14.6 (Sonoma) or later**. Works on both Intel and Apple Silicon. 6 GHz scanning requires Wi-Fi 6E/7 hardware.

### WiFi Lens Pro
WiFi Lens Pro adds menu-bar status monitoring, Network Experience, Problem History, spectrum recording, optional background observation, and a carrier-specific Wi-Fi Calling Test to the live Wi-Fi analyzer. Get it from the [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8).

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="Download on the Mac App Store" width="190"></a>
</p>

### Open-source edition

For GitHub distribution and community development:

- [GitHub Releases](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
- Homebrew: `brew tap ShiinaLabs/apps && brew install --cask ShiinaLabs/apps/wifi-lens`
- Source code: this repository

> [!IMPORTANT]
> On macOS 14.6+, **Location Services** must be enabled for the app to read Wi-Fi SSID names. Go to **System Settings → Privacy & Security → Location Services** and enable WiFi Lens when prompted.

---

## Development

```sh
git clone https://github.com/ShiinaLabs/wifi-lens
cd wifi-lens
git submodule update --init ChartLens
cd WiFiLens

# Build
xcodebuild -project WiFiLens.xcodeproj -scheme "WiFi Lens" \
  -configuration Debug -destination 'platform=macOS' build

# Run unit tests
xcodebuild -project WiFiLens.xcodeproj -scheme "WiFi Lens" \
  -configuration Debug -destination 'platform=macOS' \
  -skipPackageUpdates test -only-testing:WiFiLensTests -only-testing:WiFiLensCoreTests
```

Architecture docs live in [docs/](docs/).

---

## Contributing

Questions, bug reports, and feature ideas are welcome. See [Contributing Guidelines](.github/CONTRIBUTING.md) for setup, pull request conventions, and localization requirements.

Join **[Rabbit Hole](https://discord.gg/gH6sTCYaJ7)**, a small community for WiFi Lens and other projects.

**Contact:** [@WiFiLens on X](https://x.com/WiFiLens) · [contacts@shiinalabs.com](mailto:contacts@shiinalabs.com)

---

## License

Forked from [tiny-wifi-analyzer](https://github.com/nolze/tiny-wifi-analyzer). MAC vendor data from the [IEEE Registration Authority](https://standards.ieee.org/products-programs/regauth/) — see [Third-Party Notices](docs/THIRD-PARTY-NOTICES.md).

Apache License 2.0 © 2020 nolze, 2026 ShiinaLabs — see [LICENSE](LICENSE).
