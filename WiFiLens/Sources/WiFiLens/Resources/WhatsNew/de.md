# Neu in Version 2.0.1

## Dieses Update

Diese Aktualisierung sorgt dafür, dass WiFi Lens nur noch Informationen anzeigt, die sich bestätigen lassen. Verbindungszustände und einzelne Messwerte, die nicht bestätigt werden können, werden jetzt als „Unbekannt“ angezeigt, veraltete Messwerte gelten nicht mehr als aktueller Wert, bei einem fehlgeschlagenen Scan wird die Netzwerkliste geleert, und wenn der Wi-Fi-Status unbekannt ist, wird der Scan pausiert und der Grund dafür erklärt.

Der Roaming-Test folgt demselben Prinzip: Wechsel werden nur zwischen aufeinanderfolgenden verbundenen Messungen erfasst, die Signalkurve wird in Zeiträumen ohne Messung unterbrochen, und beim Überfahren mit dem Zeiger siehst du gleichzeitig die Messwerte aller APs zu diesem Zeitpunkt.

In der Oberfläche wurden bei AP-Radar und Netzwerktest die Titel entfernt, die den Fenstertitel wiederholt haben, die Gruppe Analyse wurde zu Netzwerkerlebnis und Problemverlauf aktualisiert, und die Titel-Badges in der Symbolleiste unterstützen jetzt VoiceOver.

## Rückblick auf WiFi Lens 2.0

WiFi Lens 2.0 ist eine umfassende Grundlage für präzisere, zuverlässigere und konsistentere Wi-Fi-Analysen.

### Detailliertere Wi-Fi-Protokollanalyse

* WiFi Lens wertet jetzt die von nahegelegenen Access Points angekündigten 802.11-Informationselemente robuster auf niedriger Ebene aus.
* Die Erkennung der verwendeten Kanalbreite wurde verbessert, einschließlich 20, 40, 80, 160 und 80+80 MHz.
* WPA3-Sicherheit, Verschlüsselungssuiten, 802.11k/r/v/w-Funktionen, Wi-Fi-Generationen, MCS und Spatial Streams werden zuverlässiger erkannt.
* Fehlerhafte oder unvollständige Funkmetadaten werden jetzt vorsichtiger behandelt, anstatt Werte zu erraten. Das verringert irreführende Angaben zu Funktionen.

### Eine stärkere Grundlage für die Fehlerbehebung

* Network Self-Check wurde mit klareren, evidenzbasierten Diagnosen für Konnektivität, DNS, HTTPS, IPv6 und konfigurierte Proxys neu aufgebaut.
* Die Wi-Fi-Analysefunktionen nutzen jetzt eine klarere gemeinsame Architektur. Das verbessert die Konsistenz von Spectrum, Channels, Interfaces, AP Radar und Diagnosen.
* Laufzeit- und Speicherverwaltung wurden neu gestaltet, um Nutzerdaten besser zu schützen und die Zuverlässigkeit in verschiedenen App-Umgebungen zu erhöhen.

### WiFi Lens Pro

* Timeline-Speicherung und der Umgang mit Verlaufsdaten sind zuverlässiger, einschließlich einer sichereren Migration bestehender Installationen.
* Die Infrastruktur für Langzeitbeobachtungen wurde gestärkt und bildet eine verlässlichere Grundlage für Verlauf, Statistics, Insights und Untersuchungsabläufe.
* Produktions- und Entwicklungsumgebungen verwenden jetzt getrennte Identitäten, Speicherorte und MCP-Endpunkte.

### AI und MCP

* Der integrierte MCP-Server ist sauberer in die App-Laufzeit eingebunden.
* Kompatible KI-Clients können weiterhin lokal über den in den Einstellungen aktivierten MCP-Endpunkt auf Live-Wi-Fi-Daten zugreifen.
* MCP-Umgebungen sind zwischen Entwicklungs- und Produktions-Builds jetzt besser voneinander getrennt.

### Zuverlässigkeit

* Verbesserte Grenzen für persistente Daten, Startvalidierung, Protokollierung, Absturzdiagnose und MetricKit-Speicherung.
* Zahlreiche Korrekturen und Tests für Netzwerke, Diagnosen, Lokalisierung, Barrierefreiheit und Laufzeitverhalten.

WiFi Lens 2.0 schafft eine vertrauenswürdigere Grundlage, um zu verstehen, welche Fähigkeiten deine WLAN-Umgebung tatsächlich ankündigt – und um Probleme zu untersuchen, wenn sie auftreten.

## Der Community beitreten

Fragen, Feedback oder einfach Lust, über WiFi Lens zu sprechen?

**Auf Discord mitmachen:** https://discord.gg/gH6sTCYaJ7
