# WiFi Lens Pro

**Comprenez ce qui se passe sur votre Wi-Fi.**

Une app macOS native réunissant analyse Wi-Fi en direct, diagnostic réseau, observation continue et historique pour enquêter sur les problèmes récurrents.

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="Obtenir WiFi Lens Pro" width="190"></a>
</p>

<p align="center"><a href="https://wifi-lens.shiinalabs.com/?utm_source=github&amp;utm_medium=readme&amp;utm_campaign=github_readme">Site officiel</a></p>

<p align="center"><img src="assets/screenshot-network-experience.webp" alt="Network Experience de WiFi Lens Pro affichant la fiabilité observée" width="800"></p>

<p align="center"><sub>macOS 14.6+ · Intel &amp; Apple Silicon · Achat unique</sub></p>

---

<p align="center">
  <a href="README.md">🇺🇸 English</a> · <a href="README.de.md">🇩🇪 Deutsch</a> · <a href="README.es-ES.md">🇪🇸 Español</a> · 🇫🇷 Français · <a href="README.zh-Hans.md">🇨🇳 简体中文</a> · <a href="README.ja.md">🇯🇵 日本語</a> · <a href="README.zh-Hant.md">🇭🇰 繁體中文</a>
</p>

<p align="center">
  <a href="#pourquoi-wifi-lens-pro">Pourquoi Pro</a> · <a href="#capacités-principales">Outils en direct</a> · <a href="#éditions">Éditions</a>
</p>

---

## Pourquoi WiFi Lens Pro

Les problèmes Wi-Fi ne se reproduisent pas toujours quand vous cherchez à les comprendre. WiFi Lens Pro associe les outils de diagnostic immédiat aux observations consultables plus tard.

### Comprendre la connexion actuelle

Explorez les réseaux Wi-Fi proches et l’encombrement des canaux. Lorsqu’une connexion se comporte mal, Network Check aide à localiser le problème. L’analyse en direct et le diagnostic font partie de l’expérience Pro.

### Continuer à observer si nécessaire

La barre des menus affiche les informations de connexion actuelles. L’observation facultative en arrière-plan peut continuer après la fermeture de Pro ; elle est désactivée par défaut et suspendue lorsque le Mac se met en veille.

### Enquêter à partir des observations

Network Experience aide à évaluer la fiabilité observée. Historical Baseline compare les mesures de latence de passerelle sauvegardées à une référence compatible, et Problem History réunit les problèmes enregistrés et leurs preuves.

<table>
<tr>
<td width="50%" align="center"><img src="assets/screenshot-historical-baseline.webp" alt="Historical Baseline comparant la latence de passerelle enregistrée à sa référence" width="100%"><sub>Historical Baseline</sub></td>
<td width="50%" align="center"><img src="assets/screenshot-problem-history.webp" alt="Problem History affichant les problèmes enregistrés et leurs preuves" width="100%"><sub>Problem History</sub></td>
</tr>
</table>

<p align="center"><a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>Obtenir WiFi Lens Pro</strong></a></p>

---

## Capacités principales

Pro comprend aussi les outils en direct nécessaires au dépannage quotidien :

- **Analyse Wi-Fi** — Analysez les réseaux 2,4, 5 et 6 GHz et comparez signal, occupation et encombrement des canaux, sécurité et recommandations régionales.
- **Network Check** — Examinez le chemin du Mac vers Internet via le réseau local : passerelle, DNS, HTTP/HTTPS, IPv6 facultatif et routage proxy.
- **Autres outils locaux** — Roaming et carte des canaux, AP Radar, intégration MCP locale et export de graphiques. Une édition open source gratuite propose également ces outils en direct.

<p align="center"><img src="assets/screenshot-hero.webp" alt="Vue Wi-Fi de WiFi Lens avec qualité des canaux et recommandations" width="800"></p>
<p align="center"><img src="assets/screenshot-selfcheck.webp" alt="Network Check avec les résultats This Mac, LAN et Internet" width="800"></p>

---

## Éditions

### WiFi Lens Pro
WiFi Lens Pro est disponible à l’achat unique sur le [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8). Il ajoute le suivi dans la barre des menus, Network Experience, Problem History, l’enregistrement du spectre, l’observation facultative en arrière-plan et un test Wi-Fi Calling propre à l’opérateur. Historical Baseline fait partie de Network Experience.

### Édition open source

WiFi Lens OSS est gratuite et open source. Téléchargez l’analyse Wi-Fi en direct et le diagnostic réseau local sur [GitHub Releases](https://github.com/ShiinaLabs/wifi-lens/releases/latest), via Homebrew ou depuis les sources.

| Capacité | WiFi Lens Pro | Édition open source |
|-----------|---------------|---------------------|
| Analyse Wi-Fi en direct | ✅ | ✅ |
| Diagnostic réseau | ✅ | ✅ |
| Recommandations de canaux | ✅ | ✅ |
| Intégration MCP | ✅ | ✅ |
| État dans la barre des menus | ✅ | — |
| Network Experience et Historical Baseline | ✅ | — |
| Problem History | ✅ | — |
| Enregistrement du spectre | ✅ | — |
| Observation facultative en arrière-plan | ✅ | — |
| Wi-Fi Calling Test | ✅ | — |

Les deux éditions traitent les relevés Wi-Fi sur votre Mac. Pro ajoute l’analyse historique, l’enregistrement, l’observation facultative en arrière-plan et le Wi-Fi Calling Test.

---

## Intégration IA / MCP


WiFi Lens inclut un serveur MCP local facultatif. Une fois activé, les clients compatibles peuvent demander les données Wi-Fi en direct de ce Mac. Configurez-le dans un client compatible MCP, comme Codex Desktop ou Claude Desktop.

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

Après la connexion, vous pouvez demander : _« Quels canaux sont encombrés près de moi ? »_ ou _« Quels réseaux proches prennent en charge WPA3 ? »_. Le serveur MCP écoute uniquement sur `127.0.0.1` ; les clients ou services de modèle connectés peuvent traiter les données reçues selon leurs propres politiques et paramètres.

Consultez le [guide des workflows IA](https://wifi-lens.shiinalabs.com/fr/ai-mcp/?utm_source=github&utm_medium=readme&utm_campaign=github_readme) pour plus d’exemples.

---

## Édition open source
WiFi Lens OSS est gratuite et open source. Utilisez-la pour l’analyse locale en direct, le développement, l’inspection du code et les contributions de la communauté.

- **GitHub Releases** — [Télécharger la dernière version](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
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
| 🌍 Localisé | Anglais, français, allemand, japonais, russe, espagnol, chinois simplifié et chinois traditionnel | Stable |
| 🩺 Network Self-Check | Vérifications de connectivité, DNS, HTTPS, IPv6 et proxys configurés | Stable |
| 📻 AP Radar | Suivre un AP sélectionné avec des impulsions audio | Aperçu |
| 📜 Licences open source | Consultez les composants, licences et notices dans Réglages → À propos | Stable |

</details>

[![Downloads](https://img.shields.io/github/downloads/ShiinaLabs/wifi-lens/WiFiLens.dmg?label=Downloads&displayAssetName=false&color=2563eb)](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
[![Latest release](https://img.shields.io/github/v/release/ShiinaLabs/wifi-lens?label=Latest&color=2563eb)](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

---

## Confidentialité
WiFi Lens ne téléverse pas les relevés Wi-Fi vers ses services applicatifs et ne collecte ni analytique d’utilisation ni télémétrie.

- **Services de localisation :** macOS exige cette autorisation pour exposer les noms SSID Wi-Fi. WiFi Lens ne lit pas la position GPS.
- **Détection de région :** Utilise la langue du système, la liste des canaux du matériel et les codes pays des AP voisins sur l’appareil.
- **Network Self-Check :** Envoie des sondes de diagnostic vers des destinations publiques et, le cas échéant, vers les proxys configurés. Les preuves sont stockées localement.
- **Serveur MCP :** Facultatif et limité à `127.0.0.1`. Les clients et services de modèle connectés traitent les données reçues selon leurs propres politiques et paramètres.
- **Observation en arrière-plan :** Facultative dans Pro et désactivée par défaut. Les observations sont stockées localement ; la collecte s’interrompt lorsque le Mac est en veille.
- **Vérifications de mises à jour :** L’édition GitHub contacte GitHub lors d’une vérification demandée ou si les vérifications automatiques sont activées.

📋 [Politique de sécurité](SECURITY.md) · 📝 [Changelog](https://github.com/ShiinaLabs/wifi-lens/releases) · ❓ [FAQ](https://wifi-lens.shiinalabs.com/fr/faq/?utm_source=github&utm_medium=readme&utm_campaign=github_readme) · 🌐 [Politique de confidentialité complète](https://wifi-lens.shiinalabs.com/fr/privacy/?utm_source=github&utm_medium=readme&utm_campaign=github_readme)

---

## Obtenir WiFi Lens

Nécessite **macOS 14.6 (Sonoma) ou ultérieur**. Fonctionne sur Mac Intel et Apple Silicon. Le scan 6 GHz nécessite un matériel Wi-Fi 6E/7.

### WiFi Lens Pro
WiFi Lens Pro ajoute au Wi-Fi en direct le suivi dans la barre des menus, Network Experience, Problem History, l’enregistrement du spectre, l’observation facultative en arrière-plan et un test Wi-Fi Calling propre à l’opérateur. Disponible sur le [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8).

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="Télécharger sur le Mac App Store" width="190"></a>
</p>

### Édition open source

Pour la distribution GitHub et le développement communautaire :

- [GitHub Releases](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
- Homebrew : `brew tap ShiinaLabs/apps && brew install --cask ShiinaLabs/apps/wifi-lens`
- Code source : ce dépôt

> [!IMPORTANT]
> Sur macOS 14.6+, les **Services de localisation** doivent être activés pour que l’app puisse lire les noms SSID Wi-Fi. Ouvrez **Réglages Système → Confidentialité et sécurité → Service de localisation** et activez WiFi Lens lorsque le système le demande.

---

## Développement

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

La documentation d’architecture se trouve dans [docs/](docs/).

---

## Contribuer

Les questions, rapports de bugs et idées de fonctionnalités sont les bienvenus. Consultez les [directives de contribution](.github/CONTRIBUTING.md) pour la configuration, les conventions de pull request et les exigences de localisation.

Rejoignez **[Rabbit Hole](https://discord.gg/gH6sTCYaJ7)**, une petite communauté pour WiFi Lens et d’autres projets.

**Contact :** [@WiFiLens sur X](https://x.com/WiFiLens) · [contacts@shiinalabs.com](mailto:contacts@shiinalabs.com)

---

## Licence

Forké de [tiny-wifi-analyzer](https://github.com/nolze/tiny-wifi-analyzer). Les données de fabricants MAC proviennent de l’[IEEE Registration Authority](https://standards.ieee.org/products-programs/regauth/) — voir les [mentions tierces](docs/THIRD-PARTY-NOTICES.md).

Apache License 2.0 © 2020 nolze, 2026 ShiinaLabs — voir [LICENSE](LICENSE).
