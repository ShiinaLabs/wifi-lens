# WiFi Lens

**Comprenez ce qui se passe sur votre Wi-Fi.**

Une app macOS native d’analyse Wi-Fi et de diagnostic réseau.

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>Obtenir WiFi Lens Pro</strong></a>
  &nbsp;·&nbsp;
  <a href="https://wifi-lens.shiinalabs.com/?utm_source=github&amp;utm_medium=readme&amp;utm_campaign=github_readme">Site officiel</a>
</p>

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="Télécharger sur le Mac App Store" width="190"></a>
</p>

<p align="center"><img alt="WiFi Lens Pro avec Problem History et preuves enregistrées" src="assets/screenshot-problem-history.webp" width="800"></p>

<p align="center">macOS 14.6+ &nbsp;·&nbsp; Apple Silicon et Intel &nbsp;·&nbsp; Traitement local</p>

<p align="center">
  🔒 <strong>Données locales</strong> — Les relevés Wi-Fi restent sur votre Mac ; aucune télémétrie d’usage<br>
  🩺 <strong>Diagnostic réseau</strong> — Vérifiez la connectivité, le DNS, HTTPS, IPv6 et les proxys configurés<br>
  🤖 <strong>MCP pour les workflows IA</strong> — Connectez des clients compatibles aux données Wi-Fi en direct de votre Mac
</p>

<p align="center"><sub>Ce dépôt héberge l’édition open source de WiFi Lens pour l’analyse locale en direct, le développement, l’inspection du code source et les contributions de la communauté.</sub></p>

---

<p align="center">
  <a href="README.md">🇺🇸 English</a> · <a href="README.de.md">🇩🇪 Deutsch</a> · <a href="README.es-ES.md">🇪🇸 Español</a> · 🇫🇷 Français · <a href="README.zh-Hans.md">🇨🇳 简体中文</a> · <a href="README.ja.md">🇯🇵 日本語</a> · <a href="README.zh-Hant.md">🇭🇰 繁體中文</a>
</p>

<p align="center">
  <a href="#pourquoi-wifi-lens-pro">Pourquoi WiFi Lens Pro</a> · <a href="#capacités-principales">Capacités principales</a> · <a href="#éditions">Éditions</a> · <a href="#intégration-ia--mcp">IA / MCP</a> · <a href="#édition-open-source">Édition open source</a> · <a href="#confidentialité">Confidentialité</a> · <a href="#obtenir-wifi-lens">Obtenir WiFi Lens</a> · <a href="#développement">Développement</a> · <a href="#contribuer">Contribuer</a> · <a href="#licence">Licence</a>
</p>

---

## Pourquoi WiFi Lens Pro
L’analyse Wi-Fi en direct vous aide à comprendre votre connexion maintenant. WiFi Lens Pro ajoute des outils pour examiner la fiabilité observée, comparer la latence de la passerelle à une référence historique et enquêter sur les problèmes enregistrés avec leurs éléments de preuve.

| Workflow | Ce que WiFi Lens Pro ajoute |
|----------|-----------------------------|
| Voir l’état en un coup d’œil | Consulter les informations de connexion dans la barre des menus |
| Évaluer la fiabilité | Examiner l’expérience observée sur une période sélectionnée |
| Comparer à une référence | Comparer les mesures enregistrées de latence de la passerelle à une référence historique compatible |
| Enquêter sur les problèmes | Examiner les problèmes enregistrés, leurs preuves et les observations ultérieures |
| Observer app fermée | Observation en arrière-plan facultative, désactivée par défaut ; elle s’interrompt lorsque le Mac se met en veille |

WiFi Lens Pro associe l’analyse en direct à des vues pour examiner la fiabilité et les problèmes historiques. Statistics et Insights ont été retirés. Timeline reste disponible uniquement pour consulter et exporter les événements existants ; il ne crée plus de nouveaux enregistrements ni d’analyses.

<table>
<tr>
<td width="50%" align="center"><img alt="Network Experience avec évaluation de fiabilité et de couverture" src="assets/screenshot-network-experience.webp" width="100%"><sub>Network Experience</sub></td>
<td width="50%" align="center"><img alt="Historical Baseline comparant la latence de la passerelle aux mesures historiques" src="assets/screenshot-historical-baseline.webp" width="100%"><sub>Historical Baseline</sub></td>
</tr>
</table>

### De l’analyse en direct au contexte historique

Lorsqu’un problème est intermittent, Network Experience vous aide à évaluer ce qui a été observé au fil du temps. Problem History rassemble les problèmes enregistrés et leurs preuves pour faciliter leur examen.

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>Obtenir WiFi Lens Pro →</strong></a>
</p>

---

## Capacités principales
WiFi Lens réunit des outils en direct pour comprendre les réseaux proches, l’utilisation des canaux et la connexion de votre Mac.

| Capacité | Utilité |
|----------|---------|
| 📡 Scan Wi-Fi | Scanner les réseaux voisins sur les bandes 2,4, 5 et 6 GHz |
| 📊 Spectre et qualité des canaux | Voir l’occupation, la congestion et les recommandations régionales |
| 🔍 Détails réseau | Examiner la génération PHY, la largeur de canal, 802.11k/r/v, WPA3 et la connexion |
| 🚶 Roaming et carte de chaleur | Valider les transitions entre AP et comparer l’occupation par bande |
| 🩺 Network Self-Check | Vérifiez la connectivité, le DNS, HTTPS, IPv6 et les proxys configurés |
| 📻 AP Radar *(Aperçu)* | Suivre un AP avec des indications fondées sur le RSSI et un retour audio optionnel |
| 🤖 MCP et export | Connecter des outils IA locaux et enregistrer les graphiques en PNG ou CSV |
| 🔒 Confidentialité locale | Conserver les données de scan sur le Mac sans télémétrie d’utilisation |

---

## Éditions

### WiFi Lens Pro
WiFi Lens Pro est disponible à l’achat unique sur le [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8). Il ajoute le suivi dans la barre des menus, Network Experience, Problem History, l’enregistrement du spectre et l’observation facultative en arrière-plan. Historical Baseline fait partie de Network Experience.

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

Les deux éditions traitent les relevés Wi-Fi sur votre Mac. Pro ajoute des vues d’analyse historique et une observation facultative en arrière-plan. Timeline est conservé uniquement pour consulter et exporter les événements existants.
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
WiFi Lens Pro ajoute au Wi-Fi en direct le suivi dans la barre des menus, Network Experience, Problem History, l’enregistrement du spectre et l’observation facultative en arrière-plan. Disponible sur le [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8).

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
