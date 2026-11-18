# WiFi Lens Pro

**Verstehe, was mit deinem WLAN passiert.**

Native macOS-App für Live-WLAN-Analyse, Netzwerkdiagnose, laufende Beobachtung und die spätere Untersuchung wiederkehrender Probleme.

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="WiFi Lens Pro holen" width="190"></a>
</p>

<p align="center"><a href="https://wifi-lens.shiinalabs.com/de/?utm_source=github&amp;utm_medium=readme&amp;utm_campaign=github_readme">Offizielle Website</a></p>

<p align="center"><img src="assets/screenshot-network-experience.webp" alt="Network Experience in WiFi Lens Pro mit beobachteter Verbindungszuverlässigkeit" width="800"></p>

<p align="center"><sub>macOS 14.6+ · Intel &amp; Apple Silicon · Einmalkauf</sub></p>

---

<p align="center">
  <a href="README.md">🇺🇸 English</a> · 🇩🇪 Deutsch · <a href="README.es-ES.md">🇪🇸 Español</a> · <a href="README.fr.md">🇫🇷 Français</a> · <a href="README.zh-Hans.md">🇨🇳 简体中文</a> · <a href="README.ja.md">🇯🇵 日本語</a> · <a href="README.zh-Hant.md">🇭🇰 繁體中文</a>
</p>

<p align="center">
  <a href="#warum-wifi-lens-pro">Warum Pro</a> · <a href="#zentrale-funktionen">Live-Werkzeuge</a> · <a href="#editionen">Editionen</a>
</p>

---

## Warum WiFi Lens Pro

WLAN-Probleme verschwinden oft, bevor du sie untersuchen kannst. WiFi Lens Pro verbindet Werkzeuge für die aktuelle Verbindung mit Aufzeichnungen, die du später wieder ansehen kannst.

### Die Verbindung jetzt verstehen

Untersuche WLANs in der Nähe und die Kanalauslastung. Wenn die Verbindung auffällig ist, hilft Network Check bei der Eingrenzung. Live-Analyse und Netzwerkdiagnose sind Teil des vollständigen Pro-Workflows.

### Bei Bedarf weiter beobachten

In der Menüleiste siehst du aktuelle Verbindungsinformationen. Die optionale Hintergrundbeobachtung kann nach dem Schließen der Pro-App weiterlaufen. Sie ist standardmäßig aus und pausiert im Ruhezustand des Macs.

### Später anhand von Belegen untersuchen

Network Experience bewertet die beobachtete Zuverlässigkeit. Historical Baseline vergleicht gespeicherte Gateway-Latenzmessungen mit einer passenden historischen Referenz. Problem History bündelt aufgezeichnete Probleme und Belege für weitere Untersuchungen.

<table>
<tr>
<td width="50%" align="center"><img src="assets/screenshot-historical-baseline.webp" alt="Historical Baseline: gespeicherte Gateway-Latenz im Vergleich zur Referenz" width="100%"><sub>Historical Baseline</sub></td>
<td width="50%" align="center"><img src="assets/screenshot-problem-history.webp" alt="Problem History mit aufgezeichneten Problemen und zugehörigen Belegen" width="100%"><sub>Problem History</sub></td>
</tr>
</table>

<p align="center"><a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>WiFi Lens Pro holen</strong></a></p>

---

## Zentrale Funktionen

Auch für die alltägliche Fehlersuche bietet Pro die Live-Werkzeuge:

- **WLAN-Analyse** — Scanne WLANs in den Bändern 2,4, 5 und 6 GHz und vergleiche Signal, Kanalauslastung, Überlastung, Sicherheit und regionale Empfehlungen.
- **Network Check** — Prüfe den Weg vom Mac über das lokale Netzwerk ins Internet: Gateway-Erreichbarkeit, DNS, HTTP/HTTPS, optionales IPv6 und Proxy-Routing.
- **Weitere lokale Werkzeuge** — Roaming und Kanal-Heatmap, AP Radar, lokale MCP-Integration und Diagrammexporte. Eine kostenlose Open-Source-Edition dieser Live-Werkzeuge ist ebenfalls verfügbar.

<p align="center"><img src="assets/screenshot-hero.webp" alt="WiFi Lens WLAN-Analyse mit Kanalqualität und Empfehlungen" width="800"></p>
<p align="center"><img src="assets/screenshot-selfcheck.webp" alt="Network Check mit Ergebnissen für This Mac, LAN und Internet" width="800"></p>

---

## Editionen

### WiFi Lens Pro
WiFi Lens Pro ist ein Einmalkauf im [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8). Es ergänzt Statusanzeigen in der Menüleiste, Network Experience, Problem History, Spektrumaufzeichnung, optionale Hintergrundbeobachtung und einen betreiberspezifischen Wi-Fi Calling Test. Historical Baseline ist Teil von Network Experience.

### Open-Source-Edition

WiFi Lens OSS ist kostenlos und quelloffen. Die Live-Wi-Fi-Analyse und Netzwerkdiagnose erhältst du über [GitHub Releases](https://github.com/ShiinaLabs/wifi-lens/releases/latest), Homebrew oder den Quellcode.

| Funktion | WiFi Lens Pro | Open-Source-Edition |
|----------|---------------|---------------------|
| Live-Wi-Fi-Analyse | ✅ | ✅ |
| Netzwerkdiagnose | ✅ | ✅ |
| Kanalempfehlungen | ✅ | ✅ |
| MCP-Integration | ✅ | ✅ |
| Status in der Menüleiste | ✅ | — |
| Network Experience und Historical Baseline | ✅ | — |
| Problem History | ✅ | — |
| Spektrumaufzeichnung | ✅ | — |
| Optionale Hintergrundbeobachtung | ✅ | — |
| Wi-Fi Calling Test | ✅ | — |

Beide Editionen verarbeiten Wi-Fi-Scans auf deinem Mac. Pro ergänzt historische Analysen, Aufzeichnungen, optionale Hintergrundbeobachtung und den Wi-Fi Calling Test.

---

## KI / MCP-Integration


WiFi Lens bietet einen optionalen lokalen MCP-Server. Nach der Aktivierung können kompatible Clients Live-Wi-Fi-Scandaten von diesem Mac abrufen. Richte den Server in einem MCP-kompatiblen Client wie Codex Desktop oder Claude Desktop ein.

```json
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840"
    }
  }
}
```

Für die manuelle Einrichtung verwendest du das Format deines Clients:

```toml
# Codex: ~/.codex/config.toml
[mcp_servers.wifi-lens]
url = "http://127.0.0.1:19840/"
```

```json
// Claude Desktop und andere JSON-basierte Clients
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840/"
    }
  }
}
```

Stelle deinem Assistenten nach der Verbindung zum Beispiel Fragen wie *„Welche Kanäle in meiner Nähe sind überlastet?“* oder *„Welche Netzwerke in der Nähe unterstützen WPA3?“*. Der MCP-Server lauscht nur auf `127.0.0.1`. Ein verbundener Client oder Modelldienst kann empfangene Daten gemäß den eigenen Richtlinien und Einstellungen verarbeiten.

Weitere Beispiele findest du im [Leitfaden für KI-Workflows](https://wifi-lens.shiinalabs.com/de/ai-mcp/?utm_source=github&utm_medium=readme&utm_campaign=github_readme).

---

## Open-Source-Edition
WiFi Lens OSS ist kostenlos und quelloffen. Nutze es für lokale Live-Analyse, Entwicklung, Quellcode-Inspektion und Beiträge aus der Community.

- **GitHub Releases** — [Neueste Version laden](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
- **Homebrew** — `brew tap ShiinaLabs/apps && brew install --cask ShiinaLabs/apps/wifi-lens`
- **Quellcode und Dokumentation** — Repository und [Architekturdokumentation](docs/) durchsuchen

<details>
<summary>Funktionen der Open-Source-Edition</summary>

| Funktion | Beschreibung | Status |
|----------|--------------|--------|
| 📡 Wi-Fi-Scanning | Echtzeit-Scan in den Bändern 2,4 / 5 / 6 GHz | Stabil |
| 📊 Spektrumansicht | Gaußsche Diagramme zur Kanalbelegung | Stabil |
| 🎯 Kanalqualität | Überlastungsscores mit regionalen Empfehlungen | Stabil |
| 🔍 Netzwerkdetails | PHY-Generation, Kanalbreite, 802.11k/r/v, WPA3 | Stabil |
| 📶 Verbindungsinformationen | IP, Gateway, DNS, MAC, Tx-Rate und Sicherheitsübersicht | Stabil |
| 🚶 Roaming-Test | Überwachung von AP-Übergaben mit Sitzungs-Speicherung und -Laden | Stabil |
| 🗺️ Kanal-Heatmap | Heatmap der Belegung pro Band | Stabil |
| 🎧 BLE-Scanner | Bluetooth-LE-Erkennung, RSSI-Analyse und Tracking | Stabil |
| 🎨 Intelligente Farben | Deterministische Farbzuordnung auf SSID-Basis | Stabil |
| 🌐 MCP-Server | Eingebettete HTTP-API für KI-Tool-Integration | Stabil |
| 📤 Export | Diagramme als PNG oder CSV speichern | Stabil |
| 🔒 Datenschutz zuerst | Keine Telemetrie; Scan-Daten bleiben auf deinem Mac | Stabil |
| ⬆️ Automatische Updates | Sparkle für die GitHub-Edition | Stabil |
| 🌍 Lokalisiert | Englisch, Französisch, Deutsch, Japanisch, Russisch, Spanisch, vereinfachtes und traditionelles Chinesisch | Stabil |
| 🩺 Network Self-Check | Prüfungen für Verbindung, DNS, HTTPS, IPv6 und konfigurierte Proxys | Stabil |
| 📻 AP Radar | Einen ausgewählten AP mit Audioimpulsen verfolgen | Preview |
| 📜 Open-Source-Lizenzen | Enthaltene Komponenten, Lizenzen und Hinweise unter Einstellungen → Info ansehen | Stabil |

</details>

[![Downloads](https://img.shields.io/github/downloads/ShiinaLabs/wifi-lens/WiFiLens.dmg?label=Downloads&displayAssetName=false&color=2563eb)](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
[![Latest release](https://img.shields.io/github/v/release/ShiinaLabs/wifi-lens?label=Latest&color=2563eb)](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

---

## Datenschutz
WiFi Lens lädt keine Wi-Fi-Scanaufzeichnungen zu seinen App-Diensten hoch und erhebt keine Nutzungsanalysen oder Telemetrie.

- **Ortungsdienste:** macOS benötigt diese Berechtigung, um Wi-Fi-SSID-Namen bereitzustellen. WiFi Lens liest keine GPS-Position.
- **Regionserkennung:** Verwendet Systemgebietsschema, die vom Gerät gemeldete Kanalliste und Ländercodes benachbarter APs auf dem Gerät.
- **Network Self-Check:** Sendet Diagnoseanfragen an öffentliche Endpunkte und gegebenenfalls an konfigurierte Proxys. Belege werden lokal gespeichert.
- **MCP-Server:** Optional und nur an `127.0.0.1` gebunden. Verbundene Clients und Modelldienste verarbeiten empfangene Daten gemäß ihren Richtlinien und Einstellungen.
- **Hintergrundbeobachtung:** In Pro optional und standardmäßig deaktiviert. Beobachtungen werden lokal gespeichert; während dein Mac schläft, pausiert die Erfassung.
- **Update-Prüfungen:** Die GitHub-Edition kontaktiert GitHub, wenn du eine Prüfung anforderst oder automatische Prüfungen aktivierst.

📋 [Sicherheitsrichtlinie](SECURITY.md) · 📝 [Changelog](https://github.com/ShiinaLabs/wifi-lens/releases) · ❓ [FAQ](https://wifi-lens.shiinalabs.com/de/faq/?utm_source=github&utm_medium=readme&utm_campaign=github_readme) · 🌐 [Vollständige Datenschutzrichtlinie](https://wifi-lens.shiinalabs.com/de/privacy/?utm_source=github&utm_medium=readme&utm_campaign=github_readme)

---

## WiFi Lens erhalten

Erfordert **macOS 14.6 (Sonoma) oder neuer**. Funktioniert mit Intel und Apple Silicon. Für 6-GHz-Scans ist Wi-Fi-6E/7-Hardware erforderlich.

### WiFi Lens Pro
WiFi Lens Pro ergänzt die Live-Wi-Fi-Analyse um Statusanzeigen in der Menüleiste, Network Experience, Problem History, Spektrumaufzeichnung, optionale Hintergrundbeobachtung und einen betreiberspezifischen Wi-Fi Calling Test. Erhältlich im [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8).

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="Im Mac App Store laden" width="190"></a>
</p>

### Open-Source-Edition

Für die Verteilung über GitHub und die Entwicklung in der Community:

- [GitHub Releases](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
- Homebrew: `brew tap ShiinaLabs/apps && brew install --cask ShiinaLabs/apps/wifi-lens`
- Quellcode: dieses Repository

> [!IMPORTANT]
> Unter macOS 14.6+ müssen die **Ortungsdienste** aktiviert sein, damit die App Wi-Fi-SSID-Namen lesen kann. Öffne **Systemeinstellungen → Datenschutz & Sicherheit → Ortungsdienste** und aktiviere WiFi Lens, wenn du dazu aufgefordert wirst.

---

## Entwicklung

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

Die Architekturdokumentation befindet sich in [docs/](docs/).

---

## Mitwirken

Fragen, Fehlerberichte und Funktionsideen sind willkommen. Siehe [Beitragsrichtlinien](.github/CONTRIBUTING.md) für Einrichtung, Pull-Request-Konventionen und Lokalisierungsanforderungen.

Tritt **[Rabbit Hole](https://discord.gg/gH6sTCYaJ7)** bei, einer kleinen Community für WiFi Lens und andere Projekte.

**Kontakt:** [@WiFiLens auf X](https://x.com/WiFiLens) · [contacts@shiinalabs.com](mailto:contacts@shiinalabs.com)

---

## Lizenz

Geforkt von [tiny-wifi-analyzer](https://github.com/nolze/tiny-wifi-analyzer). MAC-Herstellerdaten stammen von der [IEEE Registration Authority](https://standards.ieee.org/products-programs/regauth/) — siehe [Hinweise zu Drittanbietern](docs/THIRD-PARTY-NOTICES.md).

Apache License 2.0 © 2020 nolze, 2026 ShiinaLabs — siehe [LICENSE](LICENSE).
