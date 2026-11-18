# WiFi Lens

**Verstehe, was mit deinem WLAN passiert.**

Finde heraus, an welcher Stelle deine Verbindung Probleme macht, analysiere WLANs in der Nähe und untersuche wiederkehrende Störungen – in einer nativen macOS-App.

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>WiFi Lens Pro holen</strong></a> · <a href="https://github.com/ShiinaLabs/wifi-lens/releases/latest"><strong>OSS kostenlos laden</strong></a> · <a href="https://wifi-lens.shiinalabs.com/de/?utm_source=github&amp;utm_medium=readme&amp;utm_campaign=github_readme">Offizielle Website</a>
</p>
<p align="center"><a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="Im Mac App Store laden" width="190"></a></p>
<p align="center"><img alt="Network Check zeigt den Verbindungspfad von diesem Mac über den Router bis ins Internet" src="assets/screenshot-selfcheck.webp" width="800"></p>
<p align="center">macOS 14.6+ &nbsp;·&nbsp; Apple Silicon &amp; Intel &nbsp;·&nbsp; Lokal-first</p>
<p align="center">🩺 <strong>Network Check</strong> — Prüfe deinen Mac, das lokale Netzwerk und die Internetverbindung<br>📡 <strong>Wi-Fi-Analyse</strong> — Entdecke WLANs in der Nähe, Kanalnutzung, Signal und Sicherheit<br>🔒 <strong>Lokal-first</strong> — Scanaufzeichnungen bleiben auf deinem Mac; keine Nutzungs-Telemetrie</p>
<p align="center"><sub>Dieses Repository bietet die kostenlose Open-Source-Edition von WiFi Lens für Live-Analyse, Netzwerkdiagnose, Entwicklung und Beiträge aus der Community.</sub></p>

---

<p align="center">
  <a href="README.md">🇺🇸 English</a> · 🇩🇪 Deutsch · <a href="README.es-ES.md">🇪🇸 Español</a> · <a href="README.fr.md">🇫🇷 Français</a> · <a href="README.zh-Hans.md">🇨🇳 简体中文</a> · <a href="README.ja.md">🇯🇵 日本語</a> · <a href="README.zh-Hant.md">🇭🇰 繁體中文</a>
</p>

<p align="center">
  <a href="#zentrale-funktionen">Zentrale Funktionen</a> · <a href="#warum-wifi-lens-pro">Warum WiFi Lens Pro</a> · <a href="#editionen">Editionen</a> · <a href="#ki--mcp-integration">KI / MCP</a> · <a href="#open-source-edition">Open-Source-Edition</a> · <a href="#datenschutz">Datenschutz</a> · <a href="#wifi-lens-erhalten">WiFi Lens erhalten</a> · <a href="#entwicklung">Entwicklung</a> · <a href="#mitwirken">Mitwirken</a> · <a href="#lizenz">Lizenz</a>
</p>

---

## Zentrale Funktionen

WiFi Lens bündelt Live-Werkzeuge, um nahe Netzwerke, Kanalnutzung und die Verbindung deines Macs zu verstehen.

### Verbindungsprobleme eingrenzen

Wenn du ein Verbindungsproblem eingrenzen möchtest, starte **Network Check** und prüfe den Weg von deinem Mac über das lokale Netzwerk bis ins Internet. Die Prüfung umfasst den Netzwerkpfad, die Erreichbarkeit des Gateways, DNS-Auflösung, HTTP/HTTPS-Zugriff, eine optionale IPv6-Prüfung und das Routing über konfigurierte Proxys. Die Ergebnisse sind in **This Mac**, **LAN** und **Internet** gruppiert und zeigen, an welcher Stelle das Problem liegen könnte.

| Funktion | Wofür sie hilft |
|----------|-----------------|
| 📡 Wi-Fi-Scanning | Netzwerke in den Bändern 2,4, 5 und 6 GHz scannen |
| 📊 Spektrum und Kanalqualität | Belegung, Überlastung und regionale Kanalempfehlungen sehen |
| 🔍 Netzwerkdetails | PHY-Generation, Kanalbreite, 802.11k/r/v, WPA3 und Verbindungsdetails prüfen |
| 🚶 Roaming und Heatmap | AP-Übergaben prüfen und die Belegung pro Band vergleichen |
| 🩺 Network Self-Check | Verbindung, DNS, HTTPS, IPv6 und konfigurierte Proxys prüfen |
| 📻 AP Radar *(Preview)* | Einen AP mit RSSI-basierter Orientierung und optionalem Audio-Feedback verfolgen |
| 🤖 MCP und Export | Lokale KI-Tools verbinden und Diagramme als PNG oder CSV speichern |
| 🔒 Lokaler Datenschutz | Scan-Daten auf dem Mac behalten, ohne Nutzungs-Telemetrie |

<p align="center"><img alt="WiFi Lens Übersicht mit WLANs in der Nähe, Signal, Kanalqualität und Kanalempfehlung" src="assets/screenshot-hero.webp" width="800"></p>

---

## Warum WiFi Lens Pro

WiFi Lens Pro ergänzt die Live-Wi-Fi-Analyse um Verlaufs- und Folgefunktionen, mit denen du wiederkehrende Probleme untersuchen, Beobachtungen vergleichen und bei Bedarf weiter beobachten kannst.

| Workflow | Was WiFi Lens Pro ergänzt |
|----------|---------------------------|
| Status im Blick | Aktuelle Verbindungsinformationen in der Menüleiste ansehen |
| Zuverlässigkeit beurteilen | Beobachtete Netzwerkqualität für einen ausgewählten Zeitraum prüfen |
| Mit einer Referenz vergleichen | Gespeicherte Gateway-Latenz mit einer passenden historischen Referenz vergleichen |
| Probleme untersuchen | Gespeicherte Findings, Belege und spätere Beobachtungen prüfen |
| Bei geschlossener App beobachten | Optionale Hintergrundbeobachtung, standardmäßig deaktiviert; pausiert, wenn dein Mac schläft |

Pro verbindet Live-Analyse mit historischen Ansichten zur Bewertung der beobachteten Zuverlässigkeit und zur Untersuchung aufgezeichneter Probleme. Dazu kommt ein spezieller Wi-Fi Calling Test für Mobilfunkanbieter.

<table>
<tr>
<td width="50%" align="center"><img alt="Network Experience mit Zuverlässigkeitsbewertung und Abdeckungsangaben" src="assets/screenshot-network-experience.webp" width="100%"><sub>Network Experience</sub></td>
<td width="50%" align="center"><img alt="Historical Baseline mit dem Vergleich von Gateway-Latenz und historischen Messungen" src="assets/screenshot-historical-baseline.webp" width="100%"><sub>Historical Baseline</sub></td>
</tr>
<tr>
<td colspan="2" align="center"><img alt="Problem History mit aufgezeichneten Problemen und Belegen" src="assets/screenshot-problem-history.webp" width="80%"><sub>Problem History</sub></td>
</tr>
</table>

### Von der Live-Analyse zum historischen Kontext

Bei einem sporadischen Problem zeigt Network Experience, was über einen Zeitraum beobachtet wurde. Problem History fasst gespeicherte Findings und ihre Belege für die weitere Untersuchung zusammen.

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>WiFi Lens Pro holen →</strong></a>
</p>

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
