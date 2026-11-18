<h1 align="center">WiFi Lens Pro</h1>

<p align="center"><strong>Comprenez ce qui se passe sur votre Wi-Fi.</strong></p>
<p align="center">Une app macOS native d’analyse Wi-Fi et de diagnostic réseau.<br>Diagnostiquez les problèmes de connexion, observez votre réseau lorsque nécessaire et enquêtez sur les problèmes récurrents à l’aide de données historiques.</p>
<p align="center"><a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="Obtenir WiFi Lens Pro sur le Mac App Store" width="190"></a></p>
<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.6%2B-555?style=flat" alt="macOS 14.6+">
  <img src="https://img.shields.io/badge/Chip-Intel%20%7C%20Apple%20Silicon-555?style=flat" alt="Intel et Apple Silicon">
  <img src="https://img.shields.io/badge/Telemetry-None-555?style=flat" alt="Aucune télémétrie">
</p>
<p align="center"><a href="https://wifi-lens.shiinalabs.com/fr/?utm_source=github&amp;utm_medium=readme&amp;utm_campaign=github_readme">Site officiel</a> &nbsp;·&nbsp; Achat unique</p>
<p align="center"><img src="assets/screenshot-network-experience.webp" alt="WiFi Lens Pro — analyse de la fiabilité réseau dans Network Experience" width="880"></p>
<p align="center"><sub>Network Experience · Évaluer la fiabilité du réseau à partir des observations enregistrées</sub></p>

---

<p align="center"><a href="README.md">🇺🇸 English</a> · <a href="README.de.md">🇩🇪 Deutsch</a> · <a href="README.es-ES.md">🇪🇸 Español</a> · <strong>🇫🇷 Français</strong> · <a href="README.zh-Hans.md">🇨🇳 简体中文</a> · <a href="README.ja.md">🇯🇵 日本語</a> · <a href="README.zh-Hant.md">🇭🇰 繁體中文</a></p>

## Les problèmes Wi-Fi n’attendent pas que vous soyez prêt

Une connexion Wi-Fi peut se couper soudainement, la latence peut augmenter fortement, puis la connexion peut revenir d’elle-même. Lorsque vous êtes prêt à enquêter, le problème a peut-être déjà disparu.

**WiFi Lens Pro vous aide à vérifier votre réseau maintenant et à l’observer lorsque nécessaire, afin que les problèmes récurrents laissent des traces que vous pourrez examiner.**

| **🔍 01 · Diagnostiquer maintenant** | **📡 02 · Observer dans la durée** | **🗂️ 03 · Enquêter dans l’historique** |
|:---|:---|:---|
| Comprendre la connexion actuelle et l’environnement sans fil | Recueillir des observations lorsque vous en avez besoin | Examiner la fiabilité, les références historiques et les preuves des problèmes |
| [Voir le diagnostic réseau](#01--diagnostiquer-maintenant) | [Voir l’observation continue](#02--observer-dans-la-durée) | [Voir l’enquête historique](#03--enquêter-dans-lhistorique) |

---

## 01 · Diagnostiquer maintenant

### Commencez par déterminer où se situe le problème

Utilisez **Network Check** pour examiner le chemin de connexion en trois étapes : **This Mac, LAN et Internet**. Consultez les vérifications de la passerelle, du DNS, de HTTP/HTTPS, d’IPv6 en option et du proxy configuré. Les résultats permettent de distinguer les problèmes confirmés des situations où les éléments disponibles sont insuffisants.

Si l’environnement sans fil peut être en cause, l’**analyse Wi-Fi** affiche les réseaux proches en 2,4 / 5 / 6 GHz, la puissance du signal, l’utilisation et l’encombrement des canaux, les détails de sécurité et des recommandations de canaux adaptées à la région.

<table>
<tr>
<td width="50%" align="center"><img src="assets/screenshot-selfcheck.webp" alt="Diagnostic Network Check" width="100%"><sub>Network Check · Examiner la connexion étape par étape</sub></td>
<td width="50%" align="center"><img src="assets/screenshot-hero.webp" alt="Analyse Wi-Fi en direct et recommandations de canaux" width="100%"><sub>Analyse Wi-Fi · Explorer votre environnement sans fil</sub></td>
</tr>
</table>

Ces deux fonctions en direct sont également incluses dans l’édition open source gratuite. Pro les complète avec l’observation continue et l’enquête historique.

---

## 02 · Observer dans la durée

### Inutile de rester devant l’écran à attendre le retour d’un problème

Certaines anomalies ne durent que quelques secondes. Plutôt que de relancer sans cesse un scanner, vous pouvez observer votre réseau lorsque nécessaire et conserver des relevés à consulter plus tard.

| Fonction | Ce qu’elle permet |
|---|---|
| **État dans la barre des menus** | Affiche la connexion actuelle, l’état de la passerelle, les changements récents et les tendances à court terme. |
| **Continuous Observation** | Peut continuer à recueillir les observations réseau prises en charge après la fermeture de l’app Pro. Désactivée par défaut ; la collecte est suspendue lorsque votre Mac est en veille. |
| **Spectrum → Recording** | Enregistre les variations du signal d’un AP sélectionné. Vous pouvez sauvegarder les enregistrements et les recharger pour les consulter ultérieurement. |

---

## 03 · Enquêter dans l’historique

### Le problème a peut-être disparu, mais ses preuves restent utiles

Les fonctions historiques de Pro s’articulent autour de **Network Experience** et de **Problem History**. Vous pouvez suivre les éléments enregistrés au lieu d’essayer d’interpréter une série de graphiques sans lien entre eux.

**Fiabilité du réseau (Network Experience → Reliability)**

Choisissez un réseau et une période pour consulter une évaluation de la fiabilité fondée sur les éléments disponibles, notamment les problèmes détectés et leur date. Les périodes dont la couverture d’observation est insuffisante ne sont pas considérées comme la preuve que le réseau fonctionnait normalement.

**Référence historique (Network Experience → Baseline)**

Comparez les mesures de latence de passerelle enregistrées avec des références historiques compatibles. Vous obtenez ainsi des variations relatives étayées par des données ; un écart isolé ne suffit pas à prouver une panne du réseau.

**Enregistrements de problèmes (Problem History)**

Consultez les problèmes enregistrés, les éléments qui les étayent et les observations ultérieures. Lorsque les éléments le justifient, vous pouvez suivre une suggestion de vérification vers l’outil correspondant. Le lancement de cette vérification reste une action volontaire de l’utilisateur.

<table>
<tr>
<td width="50%" align="center"><img src="assets/screenshot-historical-baseline.webp" alt="Comparaison historique de la latence de passerelle" width="100%"><sub>Historical Baseline · Comparer des mesures historiques compatibles</sub></td>
<td width="50%" align="center"><img src="assets/screenshot-problem-history.webp" alt="Enregistrements et preuves de Problem History" width="100%"><sub>Problem History · Consulter les problèmes enregistrés et leurs preuves</sub></td>
</tr>
</table>

<p align="center"><strong>Vérifier ce qui se passe maintenant, observer dans la durée et enquêter plus tard.</strong></p>
<p align="center">Voilà l’expérience complète de WiFi Lens Pro.</p>
<p align="center"><a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>Obtenir WiFi Lens Pro</strong></a></p>

---

## D’autres outils utiles

En plus de ce flux de travail, WiFi Lens propose des tests d’itinérance, des cartes thermiques des canaux, AP Radar, l’analyse Bluetooth LE, l’export des graphiques et une intégration MCP locale.

WiFi Lens Pro inclut également **Wi-Fi Calling Test** pour les scénarios propres aux opérateurs, avec des profils prédéfinis ou des valeurs MCC/MNC personnalisées.

## Pro et open source

L’édition open source gratuite fournit l’analyse Wi-Fi en direct et le diagnostic réseau local. **WiFi Lens Pro** complète ces fonctions avec l’observation continue, l’analyse historique et l’enquête sur les problèmes.

| Fonction | Pro | Open source |
|---|:---:|:---:|
| Analyse Wi-Fi, qualité des canaux et recommandations | ✓ | ✓ |
| Network Check | ✓ | ✓ |
| Tests d’itinérance, AP Radar et cartes thermiques des canaux | ✓ | ✓ |
| MCP local et export des graphiques | ✓ | ✓ |
| État dans la barre des menus et observation continue | ✓ | — |
| Fiabilité du réseau et références historiques | ✓ | — |
| Enregistrements de problèmes et enquête historique | ✓ | — |
| Enregistrement du spectre et Wi-Fi Calling Test | ✓ | — |

<p align="center"><a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8">Obtenir WiFi Lens Pro</a> &nbsp;·&nbsp; <a href="https://github.com/ShiinaLabs/wifi-lens/releases/latest">Télécharger l’édition open source gratuite</a></p>

---

## Confidentialité et données

WiFi Lens traite les données de scan Wi-Fi localement sur votre Mac. Aucun compte, aucune synchronisation cloud ni télémétrie d’utilisation ne sont nécessaires.

- **Network Check :** Se connecte à des destinations de diagnostic publiques et, le cas échéant, vérifie le proxy configuré.
- **Continuous Observation :** Désactivée par défaut. Les données d’observation restent sur votre Mac et la collecte s’interrompt pendant la veille.
- **MCP local :** Le serveur écoute uniquement sur `127.0.0.1`. Si votre client IA se connecte à un service externe, vérifiez séparément la façon dont ce client traite les données.
- **Autorisations système :** macOS exige l’autorisation des services de localisation pour que les apps puissent lire les SSID Wi-Fi. WiFi Lens ne lit pas votre position GPS.

Consultez la [politique de confidentialité complète](https://wifi-lens.shiinalabs.com/fr/privacy/?utm_source=github&utm_medium=readme&utm_campaign=github_readme).

## Obtenir WiFi Lens

**WiFi Lens Pro:** Achat unique sur le [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8). Nécessite macOS 14.6+ et prend en charge Intel et Apple Silicon. Le scan 6 GHz nécessite un matériel Wi-Fi 6E/7.

**WiFi Lens open source:** Disponible sur [GitHub Releases](https://github.com/ShiinaLabs/wifi-lens/releases/latest) ou via Homebrew :

<p>
<a href="https://github.com/ShiinaLabs/wifi-lens/releases/latest"><img src="https://img.shields.io/github/v/release/ShiinaLabs/wifi-lens?label=Latest&amp;color=2563eb" alt="Dernière version"></a>
<a href="https://github.com/ShiinaLabs/wifi-lens/releases/latest"><img src="https://img.shields.io/github/downloads/ShiinaLabs/wifi-lens/WiFiLens.dmg?label=Downloads&amp;displayAssetName=false&amp;color=2563eb" alt="Téléchargements"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue" alt="Licence Apache 2.0"></a>
</p>

```sh
brew tap ShiinaLabs/apps
brew install --cask ShiinaLabs/apps/wifi-lens
```

<details>
<summary><strong>IA / MCP : intégration et configuration</strong></summary>

WiFi Lens fournit un serveur MCP local facultatif. Une fois activé, les outils d’IA compatibles peuvent lire les données de scan Wi-Fi en direct, par exemple l’utilisation des canaux proches et les informations de sécurité des réseaux.

Le serveur écoute uniquement sur `127.0.0.1`. Exemple de configuration d’un client MCP :

```json
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840/"
    }
  }
}
```

Configuration de Codex :

```toml
[mcp_servers.wifi-lens]
url = "http://127.0.0.1:19840/"
```

D’autres exemples sont disponibles dans le [guide des workflows IA](https://wifi-lens.shiinalabs.com/fr/ai-mcp/?utm_source=github&utm_medium=readme&utm_campaign=github_readme).

</details>

<details>
<summary><strong>Développement et contribution</strong></summary>

```sh
git clone https://github.com/ShiinaLabs/wifi-lens
cd wifi-lens

xcodebuild -project WiFiLens.xcodeproj -scheme "WiFi Lens" \
  -configuration Debug -destination 'platform=macOS' build

xcodebuild -project WiFiLens.xcodeproj -scheme "WiFi Lens" \
  -configuration Debug -destination 'platform=macOS' \
  -skipPackageUpdates test -only-testing:WiFiLensTests -only-testing:WiFiLensCoreTests
```

Consultez [docs/](docs/) pour la documentation de l’architecture et le [guide de contribution](.github/CONTRIBUTING.md) pour signaler des problèmes, proposer des améliorations et envoyer des pull requests.

</details>

## Communauté et licence

Rejoignez [Rabbit Hole](https://discord.gg/gH6sTCYaJ7) pour discuter de WiFi Lens et d’autres projets.

**Contact :** [@WiFiLens](https://x.com/WiFiLens) · [contacts@shiinalabs.com](mailto:contacts@shiinalabs.com)

Ce projet est un fork de [tiny-wifi-analyzer](https://github.com/nolze/tiny-wifi-analyzer). Les données des fabricants MAC proviennent de l’[IEEE Registration Authority](https://standards.ieee.org/products-programs/regauth/) ; consultez les [mentions relatives aux composants tiers](docs/THIRD-PARTY-NOTICES.md).

Apache License 2.0 © 2020 nolze, 2026 ShiinaLabs — voir [LICENSE](LICENSE).
