# Nouveautés de la version 2.0.1

## Dans cette mise à jour

Cette mise à jour fait en sorte que WiFi Lens n’affiche que les informations qu’il peut confirmer. Les états de connexion et les métriques individuelles qui ne peuvent pas être confirmés apparaissent désormais comme « Inconnu », les relevés obsolètes ne sont plus affichés comme des valeurs actuelles, un scan qui échoue vide la liste des réseaux et, lorsque l’état du Wi-Fi est inconnu, le scan est mis en pause et le motif est expliqué.

Le test d’itinérance suit le même principe : seuls les changements entre échantillons associés de façon continue sont enregistrés, la courbe de signal s’interrompt pendant les périodes sans mesure et, au survol, il est possible de voir en même temps les relevés de tous les AP à cet instant.

Côté interface, AP Radar et Diagnostic réseau n’affichent plus de titre redondant avec celui de la fenêtre, le groupe Analyse réunit désormais Expérience réseau et Historique des problèmes, et le badge de titre de la barre d’outils est désormais compatible avec VoiceOver.

## Rétrospective de WiFi Lens 2.0

WiFi Lens 2.0 renforce ses fondations pour rendre l’analyse Wi-Fi plus précise, fiable et cohérente.

### Analyse plus poussée des protocoles Wi-Fi

* WiFi Lens analyse désormais plus rigoureusement, à bas niveau, les éléments d’information 802.11 annoncés par les points d’accès à proximité.
* La détection de la largeur de canal utilisée a été améliorée, notamment pour les configurations 20, 40, 80, 160 et 80+80 MHz.
* L’app identifie plus fiablement la sécurité WPA3, les suites de chiffrement, les capacités 802.11k/r/v/w, les générations Wi-Fi, MCS et les flux spatiaux.
* Les métadonnées sans fil mal formées ou incomplètes sont traitées avec davantage de prudence au lieu d’être devinées, ce qui réduit les informations trompeuses sur les capacités.

### Des bases plus solides pour le dépannage

* Network Self-Check a été repensé avec des diagnostics plus clairs, fondés sur des éléments vérifiables, pour la connectivité, le DNS, HTTPS, IPv6 et les proxys configurés.
* Les composants d’analyse Wi-Fi partagent maintenant une architecture interne plus cohérente, ce qui harmonise Spectrum, Channels, Interfaces, AP Radar et les diagnostics.
* La gestion de l’environnement d’exécution et du stockage a été repensée afin de mieux protéger les données des utilisateurs et d’améliorer la fiabilité entre les environnements de l’app.

### WiFi Lens Pro

* Le stockage de Timeline et la gestion de l’historique sont plus fiables, avec une migration plus sûre des installations existantes.
* L’infrastructure d’observation à long terme a été renforcée pour offrir une base plus fiable à l’historique, Statistics, Insights et aux enquêtes.
* Les environnements de production et de développement utilisent désormais des identités, des espaces de stockage et des points de terminaison MCP distincts.

### IA et MCP

* Le serveur MCP intégré s’intègre plus proprement à l’environnement d’exécution de l’app.
* Les clients d’IA compatibles peuvent toujours accéder localement aux informations Wi-Fi en direct via le point de terminaison MCP activé dans Réglages.
* Les environnements MCP sont mieux isolés entre les versions de développement et de production.

### Fiabilité

* Les limites de persistance, la validation au démarrage, la journalisation, le diagnostic des plantages et le stockage MetricKit ont été améliorés.
* De nombreuses corrections et vérifications ont été ajoutées pour le réseau, les diagnostics, la localisation, l’accessibilité et le comportement à l’exécution.

WiFi Lens 2.0 offre une base plus digne de confiance pour comprendre ce que votre environnement sans fil annonce réellement et pour enquêter sur les problèmes lorsqu’ils surviennent.

## Rejoindre la communauté

Une question, un commentaire ou simplement envie de parler de WiFi Lens ?

**Rejoignez-nous sur Discord :** https://discord.gg/gH6sTCYaJ7
