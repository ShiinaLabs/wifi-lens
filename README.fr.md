# WiFi Lens

**Le workflow complet de dépannage Wi-Fi sur Mac.**

WiFi Lens Pro réunit l’analyse Wi-Fi en direct, le diagnostic réseau, la surveillance continue, l’historique Timeline, Statistics et Insights dans une app macOS native.

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>Obtenir WiFi Lens Pro</strong></a>
  &nbsp;·&nbsp;
  <a href="https://wifi-lens.shiinalabs.com">Site officiel</a>
</p>

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="Télécharger sur le Mac App Store" width="190"></a>
</p>

<p align="center"><img alt="WiFi Lens Pro affichant l’historique Event Timeline sur macOS" src="assets/screenshot-timeline.webp" width="800"></p>

<p align="center">macOS 14+ &nbsp;·&nbsp; Apple Silicon &amp; Intel &nbsp;·&nbsp; Sans télémétrie</p>

<p align="center">
  🔒 <strong>Confidentialité locale</strong> — Pas de compte, pas de cloud, pas de télémétrie<br>
  🩺 <strong>Diagnostic fondé sur des preuves</strong> — Vérifications explicables du chemin, DNS, HTTPS et proxy<br>
  🤖 <strong>MCP pour les workflows IA</strong> — Connectez les clients compatibles aux données Wi-Fi en direct de votre Mac
</p>

<p align="center"><sub>Ce dépôt héberge l’édition open source de WiFi Lens pour l’analyse locale en direct, le développement, l’inspection du code source et les contributions de la communauté.</sub></p>

---

<p align="center">
  <a href="README.md">🇺🇸 English</a> · <a href="README.de.md">🇩🇪 Deutsch</a> · <a href="README.es-ES.md">🇪🇸 Español</a> · 🇫🇷 Français · <a href="README.zh-Hans.md">🇨🇳 简体中文</a> · <a href="README.ja.md">🇯🇵 日本語</a>
</p>
<p align="center">
  <a href="#pourquoi-wifi-lens-pro">Pourquoi WiFi Lens Pro</a> · <a href="#capacités-principales">Capacités principales</a> · <a href="#éditions">Éditions</a> · <a href="#intégration-ia--mcp">IA / MCP</a> · <a href="#édition-open-source">Édition open source</a> · <a href="#confidentialité">Confidentialité</a> · <a href="#obtenir-wifi-lens">Obtenir WiFi Lens</a> · <a href="#développement">Développement</a> · <a href="#contribuer">Contribuer</a> · <a href="#licence">Licence</a>
</p>

---

## Pourquoi WiFi Lens Pro

Le diagnostic en direct indique ce qui se passe maintenant. WiFi Lens Pro prolonge l’histoire lorsque le problème est intermittent : il observe, enregistre, conserve l’historique et vous aide à comprendre ce qui s’est passé plus tard.

| Workflow | Ce que fait WiFi Lens Pro |
|----------|---------------------------|
| Diagnostiquer maintenant | Analyse Wi-Fi en direct, analyse des canaux et diagnostic réseau |
| Continuer à surveiller | Surveillance depuis la barre des menus et observation continue |
| Capturer les problèmes intermittents | Timeline et enregistrement du spectre |
| Revoir ce qui s’est passé | Événements historiques et changements de connexion |
| Trouver des tendances | Statistics sur les périodes enregistrées |
| Comprendre les preuves | Insights fondées sur les observations enregistrées |

**WiFi Lens Pro est l’édition complète.** Elle relie l’analyseur en direct à la surveillance, à l’historique et à l’investigation au lieu de les traiter comme des outils séparés.

<table>
<tr>
<td width="50%" align="center"><img alt="Vue de l’auto-diagnostic réseau" src="assets/screenshot-selfcheck.webp" width="100%"><sub>Network Self-Check</sub></td>
<td width="50%" align="center"><img alt="Event Timeline affichant l’historique de connexion" src="assets/screenshot-timeline.webp" width="100%"><sub>Event Timeline (Pro)</sub></td>
</tr>
</table>

### Diagnostiquer maintenant → enquêter plus tard

Les problèmes Wi-Fi disparaissent souvent avant que vous puissiez les inspecter. WiFi Lens Pro conserve les preuves autour d’une coupure, d’un roaming ou d’un changement de signal afin que vous puissiez revoir l’événement et les conditions réseau plus tard.

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>Obtenir WiFi Lens Pro →</strong></a>
</p>

---

## Capacités principales

WiFi Lens réunit les outils essentiels pour comprendre un environnement Wi-Fi local dans une app Mac native.

| Capacité | Utilité |
|----------|---------|
| 📡 Scan Wi-Fi | Scanner les réseaux voisins sur les bandes 2,4, 5 et 6 GHz |
| 📊 Spectre et qualité des canaux | Voir l’occupation, la congestion et les recommandations régionales |
| 🔍 Détails réseau | Examiner la génération PHY, la largeur de canal, 802.11k/r/v, WPA3 et la connexion |
| 🚶 Roaming et carte de chaleur | Valider les transitions entre AP et comparer l’occupation par bande |
| 🩺 Network Self-Check *(Aperçu)* | Vérifier le chemin, le DNS, HTTPS et l’accessibilité des proxys configurés |
| 📻 AP Radar *(Aperçu)* | Suivre un AP avec des indications fondées sur le RSSI et un retour audio optionnel |
| 🤖 MCP et export | Connecter des outils IA locaux et enregistrer les graphiques en PNG ou CSV |
| 🔒 Confidentialité locale | Conserver les données de scan sur le Mac sans télémétrie d’utilisation |

---

## Éditions

### WiFi Lens Pro

**WiFi Lens Pro est l’édition complète.** Il s’agit d’un achat unique sur le [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8), pour les personnes qui ont besoin d’observation continue, d’enregistrement, d’historique et d’investigation.

### Édition open source

L’édition open source fournit un ensemble substantiel de capacités d’analyse en direct pour les personnes qui préfèrent la distribution GitHub ou souhaitent inspecter et contribuer au code. Elle est disponible via [GitHub Releases](https://github.com/SHIINASAMA/wifi-lens/releases/latest).

| Capacité | WiFi Lens Pro | Édition open source |
|----------|---------------|---------------------|
| Analyse Wi-Fi en direct | ✅ | ✅ |
| Diagnostic réseau | ✅ | ✅ |
| Recommandations de canaux | ✅ | ✅ |
| Surveillance continue | ✅ | — |
| Historique des événements | ✅ | — |
| Statistiques historiques | ✅ | — |
| Insights | ✅ | — |
| Enregistrement du spectre | ✅ | — |
| Surveillance dans la barre des menus | ✅ | — |

Les deux éditions traitent les données localement. La différence réside dans le workflow autour de l’analyseur en direct : Pro ajoute le contexte nécessaire pour observer, conserver et étudier les problèmes dans le temps.

---

## Intégration IA / MCP

WiFi Lens inclut un serveur MCP intégré qui permet aux assistants IA compatibles de lire vos données Wi-Fi locales. Activez-le dans les réglages, choisissez **Copier le prompt de configuration IA**, puis collez le prompt dans un client de bureau compatible MCP tel que Codex Desktop ou Claude Desktop.

```json
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840"
    }
  }
}
```

Pour une configuration manuelle, utilisez le format attendu par votre client :

```toml
# Codex : ~/.codex/config.toml
[mcp_servers.wifi-lens]
url = "http://127.0.0.1:19840/"
```

```json
// Claude Desktop et autres clients JSON
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840/"
    }
  }
}
```

Une fois connecté, demandez à votre assistant : _« Quels canaux sont congestionnés près de moi ? »_ ou _« Quels réseaux voisins prennent en charge WPA3 ? »_. Le serveur se lie uniquement à `127.0.0.1` — rien ne quitte votre machine sauf si vous l’acheminez délibérément ailleurs.

Consultez le [guide des workflows IA](https://wifi-lens.shiinalabs.com/ai-mcp/) pour plus d’exemples.

---

## Édition open source

L’édition open source est disponible pour l’analyse locale, le développement, l’inspection du code source et les contributions de la communauté.

- **GitHub Releases** — [Télécharger la dernière version](https://github.com/SHIINASAMA/wifi-lens/releases/latest)
- **Homebrew** — `brew tap ShiinaLabs/apps && brew install --cask ShiinaLabs/apps/wifi-lens`
- **Code source et documentation** — Parcourir le dépôt et la [documentation d’architecture](docs/)

<details>
<summary>Capacités de l’édition open source</summary>

| Capacité | Description | État |
|----------|-------------|------|
| 📡 Scan Wi-Fi | Scan en temps réel des bandes 2,4 / 5 / 6 GHz | Stable |
| 📊 Vue Spectre | Courbes gaussiennes d’occupation des canaux | Stable |
| 🎯 Qualité du canal | Scores de congestion avec recommandations régionales | Stable |
| 🔍 Détails du réseau | Génération PHY, largeur de canal, 802.11k/r/v, WPA3 | Stable |
| 📶 Informations de connexion | IP, passerelle, DNS, MAC, débit Tx et résumé de sécurité | Stable |
| 🚶 Test de roaming | Suivi des transitions AP avec sauvegarde et chargement des sessions | Stable |
| 🗺️ Carte de chaleur des canaux | Carte de chaleur de l’occupation par bande | Stable |
| 🎧 Scanner BLE | Découverte Bluetooth LE, analyse RSSI et suivi | Stable |
| 🎨 Coloration intelligente | Attribution déterministe basée sur le SSID | Stable |
| 🌐 Serveur MCP | API HTTP intégrée pour les outils IA | Stable |
| 📤 Export | Enregistrer les graphiques en PNG ou CSV | Stable |
| 🔒 Confidentialité d’abord | Pas de télémétrie ; données conservées sur le Mac | Stable |
| ⬆️ Mises à jour automatiques | Sparkle pour l’édition GitHub | Stable |
| 🌍 Localisé | Anglais, allemand, espagnol, japonais, chinois | Stable |
| 🩺 Network Self-Check | Diagnostic du chemin, DNS, HTTPS et proxy en un clic | Aperçu |
| 📻 AP Radar | Suivre un AP sélectionné avec des impulsions audio | Aperçu |

</details>

[![Downloads](https://img.shields.io/github/downloads/SHIINASAMA/wifi-lens/WiFiLens.dmg?label=Downloads&displayAssetName=false&color=2563eb)](https://github.com/SHIINASAMA/wifi-lens/releases/latest)
[![Latest release](https://img.shields.io/github/v/release/SHIINASAMA/wifi-lens?label=Latest&color=2563eb)](https://github.com/SHIINASAMA/wifi-lens/releases/latest)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

---

## Confidentialité

WiFi Lens ne collecte aucune analytique d’utilisation, télémétrie de plantage ni donnée de scan Wi-Fi.

- **Services de localisation :** macOS exige cette autorisation pour exposer les noms SSID Wi-Fi. WiFi Lens ne lit pas la position GPS.
- **Détection de région :** Utilise la langue du système, la liste des canaux du matériel et les codes pays des AP voisins sur l’appareil.
- **Network Self-Check :** Résout des endpoints publics (`www.apple.com`, `www.msftconnecttest.com`) et peut tester l’accessibilité des proxys configurés.
- **Serveur MCP :** Se lie uniquement à `127.0.0.1`. Les outils locaux accèdent aux données après activation.
- **Vérifications de mises à jour :** L’édition GitHub contacte GitHub lors d’une vérification demandée ou si les vérifications automatiques sont activées.

📋 [Politique de sécurité](SECURITY.md) · 📝 [Changelog](https://github.com/SHIINASAMA/wifi-lens/releases) · ❓ [FAQ](https://wifi-lens.shiinalabs.com/faq/) · 🌐 [Politique de confidentialité complète](https://wifi-lens.shiinalabs.com/privacy/)

---

## Obtenir WiFi Lens

Nécessite **macOS 14 (Sonoma) ou ultérieur**. Fonctionne sur Mac Intel et Apple Silicon. Le scan 6 GHz nécessite un matériel Wi-Fi 6E/7.

### WiFi Lens Pro

L’édition complète pour la surveillance continue, l’enregistrement, l’historique et l’investigation. Disponible sur le [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8).

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="Télécharger sur le Mac App Store" width="190"></a>
</p>

### Édition open source

Pour la distribution GitHub et le développement communautaire :

- [GitHub Releases](https://github.com/SHIINASAMA/wifi-lens/releases/latest)
- Homebrew : `brew tap ShiinaLabs/apps && brew install --cask ShiinaLabs/apps/wifi-lens`
- Code source : ce dépôt

> [!IMPORTANT]
> Sur macOS 14+, les **Services de localisation** doivent être activés pour que l’app puisse lire les noms SSID Wi-Fi. Ouvrez **Réglages Système → Confidentialité et sécurité → Service de localisation** et activez WiFi Lens lorsque le système le demande.

---

## Développement

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

La documentation d’architecture se trouve dans [docs/](docs/).

---

## Contribuer

Les questions, rapports de bugs et idées de fonctionnalités sont les bienvenus. Consultez les [directives de contribution](.github/CONTRIBUTING.md) pour la configuration, les conventions de pull request et les exigences de localisation.

Rejoignez **[Rabbit Hole](https://discord.gg/gH6sTCYaJ7)**, une petite communauté pour WiFi Lens et d’autres projets.

**Contact :** [@WiFiLens sur X](https://x.com/WiFiLens) · [wifi-lens@shiinalabs.com](mailto:wifi-lens@shiinalabs.com)

---

## Licence

Forké de [tiny-wifi-analyzer](https://github.com/nolze/tiny-wifi-analyzer). Les données de fabricants MAC proviennent de l’[IEEE Registration Authority](https://standards.ieee.org/products-programs/regauth/) — voir les [mentions tierces](docs/THIRD-PARTY-NOTICES.md).

Apache License 2.0 © 2020 nolze, 2026 SHIINASAMA — voir [LICENSE](LICENSE).
