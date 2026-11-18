# WiFi Lens Pro

**Entiende qué ocurre con tu Wi-Fi.**

Una app nativa para macOS que reúne análisis Wi-Fi en directo, diagnóstico de red, observación continua e historial para investigar problemas recurrentes.

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="Obtener WiFi Lens Pro" width="190"></a>
</p>

<p align="center"><a href="https://wifi-lens.shiinalabs.com/es/?utm_source=github&amp;utm_medium=readme&amp;utm_campaign=github_readme">Sitio web oficial</a></p>

<p align="center"><img src="assets/screenshot-network-experience.webp" alt="Network Experience de WiFi Lens Pro mostrando la fiabilidad observada" width="800"></p>

<p align="center"><sub>macOS 14.6+ · Intel &amp; Apple Silicon · One-time purchase</sub></p>

---

<p align="center">
  <a href="README.md">🇺🇸 English</a> · <a href="README.de.md">🇩🇪 Deutsch</a> · 🇪🇸 Español · <a href="README.fr.md">🇫🇷 Français</a> · <a href="README.zh-Hans.md">🇨🇳 简体中文</a> · <a href="README.ja.md">🇯🇵 日本語</a> · <a href="README.zh-Hant.md">🇭🇰 繁體中文</a>
</p>

<p align="center">
  <a href="#por-qué-wifi-lens-pro">Por qué Pro</a> · <a href="#capacidades-principales">Herramientas</a> · <a href="#ediciones">Ediciones</a>
</p>

---

## Por qué WiFi Lens Pro

Los problemas de Wi-Fi pueden desaparecer antes de que puedas investigarlos. WiFi Lens Pro combina herramientas para examinar la conexión ahora con observaciones que puedes consultar más adelante.

### Comprende la conexión actual

Explora las redes Wi-Fi cercanas y la congestión de los canales. Cuando algo falla, utiliza Network Check para acotar el problema. El análisis en directo y el diagnóstico forman parte de la experiencia Pro.

### Sigue observando cuando lo necesites

Consulta la conexión actual en la barra de menús. La observación opcional en segundo plano puede continuar después de cerrar Pro; está desactivada por defecto y se pausa cuando el Mac entra en reposo.

### Investiga con datos registrados

Network Experience ayuda a evaluar la fiabilidad observada. Historical Baseline compara las mediciones guardadas de latencia de la puerta de enlace con una referencia compatible; Problem History reúne los problemas registrados y sus evidencias.

<table>
<tr>
<td width="50%" align="center"><img src="assets/screenshot-historical-baseline.webp" alt="Historical Baseline compara la latencia guardada con una referencia anterior" width="100%"><sub>Historical Baseline</sub></td>
<td width="50%" align="center"><img src="assets/screenshot-problem-history.webp" alt="Problem History muestra problemas registrados y sus evidencias" width="100%"><sub>Problem History</sub></td>
</tr>
</table>

<p align="center"><a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>Obtener WiFi Lens Pro</strong></a></p>

---

## Capacidades principales

Pro también incluye las herramientas en directo para el diagnóstico diario:

- **Análisis Wi-Fi** — Escanea redes de 2,4, 5 y 6 GHz y compara señal, actividad y congestión de canales, seguridad y recomendaciones regionales.
- **Network Check** — Revisa la ruta desde tu Mac por la red local hasta Internet, incluida la puerta de enlace, DNS, HTTP/HTTPS, IPv6 opcional y el enrutamiento por proxy.
- **Otras herramientas locales** — Roaming y mapa de canales, AP Radar, integración MCP local y exportación de gráficos. También existe una edición gratuita de código abierto con estas herramientas en directo.

<p align="center"><img src="assets/screenshot-hero.webp" alt="Vista Wi-Fi de WiFi Lens con calidad de canales y recomendaciones" width="800"></p>
<p align="center"><img src="assets/screenshot-selfcheck.webp" alt="Network Check con resultados de This Mac, LAN e Internet" width="800"></p>

---

## Ediciones

### WiFi Lens Pro
WiFi Lens Pro es una compra única en el [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8). Añade estado en la barra de menús, Network Experience, Problem History, grabación del espectro, observación opcional en segundo plano y una prueba de llamadas Wi-Fi específica del operador. Historical Baseline forma parte de Network Experience.

### Edición de código abierto

WiFi Lens OSS es gratis y de código abierto. Descarga el análisis Wi-Fi en directo y el diagnóstico local de red desde [GitHub Releases](https://github.com/ShiinaLabs/wifi-lens/releases/latest), Homebrew o el código fuente.

| Capacidad | WiFi Lens Pro | Edición de código abierto |
|-----------|---------------|----------------------------|
| Análisis Wi-Fi en directo | ✅ | ✅ |
| Diagnóstico de red | ✅ | ✅ |
| Recomendaciones de canal | ✅ | ✅ |
| Integración MCP | ✅ | ✅ |
| Estado en la barra de menús | ✅ | — |
| Network Experience y Historical Baseline | ✅ | — |
| Problem History | ✅ | — |
| Grabación del espectro | ✅ | — |
| Observación opcional en segundo plano | ✅ | — |
| Wi-Fi Calling Test | ✅ | — |

Ambas ediciones procesan los escaneos Wi-Fi en tu Mac. Pro añade análisis histórico, grabación, observación opcional en segundo plano y Wi-Fi Calling Test.

---

## Integración de IA / MCP


WiFi Lens incluye un servidor MCP local opcional. Cuando lo activas, los clientes compatibles pueden solicitar datos de escaneo Wi-Fi en directo desde este Mac. Configúralo en un cliente compatible con MCP, como Codex Desktop o Claude Desktop.

```json
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840"
    }
  }
}
```

Para configurarlo manualmente, usa el formato que espera tu cliente:

```toml
# Codex: ~/.codex/config.toml
[mcp_servers.wifi-lens]
url = "http://127.0.0.1:19840/"
```

```json
// Claude Desktop y otros clientes basados en JSON
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840/"
    }
  }
}
```

Una vez conectado, pregunta cosas como _«¿Qué canales están congestionados cerca de mí?»_ o _«¿Qué redes cercanas admiten WPA3?»_. El servidor MCP solo escucha en `127.0.0.1`; el cliente o servicio de modelo conectado puede tratar los datos recibidos según sus propias políticas y configuración.

Consulta la [guía de flujos de IA](https://wifi-lens.shiinalabs.com/es/ai-mcp/?utm_source=github&utm_medium=readme&utm_campaign=github_readme) para ver más ejemplos.

---

## Edición de código abierto
WiFi Lens OSS es gratis y de código abierto. Úsalo para análisis local en directo, desarrollo, inspección del código y contribuciones de la comunidad.

- **GitHub Releases** — [Descargar la versión más reciente](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
- **Homebrew** — `brew tap ShiinaLabs/apps && brew install --cask ShiinaLabs/apps/wifi-lens`
- **Código fuente y documentación** — Explora el repositorio y la [documentación de arquitectura](docs/)

<details>
<summary>Capacidades de la edición de código abierto</summary>

| Capacidad | Descripción | Estado |
|-----------|-------------|--------|
| 📡 Escaneo Wi-Fi | Escaneo en tiempo real en 2,4 / 5 / 6 GHz | Estable |
| 📊 Vista de espectro | Gráficos gaussianos de ocupación de canales | Estable |
| 🎯 Calidad de canal | Puntuaciones de congestión con recomendaciones regionales | Estable |
| 🔍 Detalles de red | Generación PHY, ancho de canal, 802.11k/r/v, WPA3 | Estable |
| 📶 Información de conexión | IP, puerta de enlace, DNS, MAC, tasa Tx y resumen de seguridad | Estable |
| 🚶 Prueba de roaming | Monitorización de cambios de AP con guardado y carga de sesiones | Estable |
| 🗺️ Mapa de calor de canales | Mapa de calor de ocupación por banda | Estable |
| 🎧 Escáner BLE | Descubrimiento Bluetooth LE, análisis RSSI y seguimiento | Estable |
| 🎨 Colores inteligentes | Asignación determinista basada en SSID | Estable |
| 🌐 Servidor MCP | API HTTP integrada para herramientas de IA | Estable |
| 📤 Exportación | Guardar gráficos como PNG o CSV | Estable |
| 🔒 Privacidad primero | Sin telemetría; los datos permanecen en tu Mac | Estable |
| ⬆️ Actualizaciones automáticas | Sparkle para la edición de GitHub | Estable |
| 🌍 Localizado | Inglés, francés, alemán, japonés, ruso, español, chino simplificado y chino tradicional | Estable |
| 🩺 Network Self-Check | Comprobaciones de conectividad, DNS, HTTPS, IPv6 y proxies configurados | Estable |
| 📻 AP Radar | Seguir un AP seleccionado con pulsos de audio | Vista previa |
| 📜 Licencias de código abierto | Consulta componentes, licencias y avisos incluidos en Ajustes → Acerca de | Estable |

</details>

[![Downloads](https://img.shields.io/github/downloads/ShiinaLabs/wifi-lens/WiFiLens.dmg?label=Downloads&displayAssetName=false&color=2563eb)](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
[![Latest release](https://img.shields.io/github/v/release/ShiinaLabs/wifi-lens?label=Latest&color=2563eb)](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

---

## Privacidad
WiFi Lens no sube registros de escaneo Wi-Fi a sus servicios de aplicación y no recopila analíticas de uso ni telemetría.

- **Servicios de ubicación:** macOS necesita este permiso para mostrar los nombres SSID de las redes Wi-Fi. WiFi Lens no lee la posición GPS.
- **Detección de región:** Usa la configuración regional del sistema, la lista de canales indicada por el hardware y los códigos de país de los AP cercanos en el dispositivo.
- **Network Self-Check:** Envía pruebas de diagnóstico a destinos públicos y, cuando corresponde, a proxies configurados. Las evidencias se guardan localmente.
- **Servidor MCP:** Es opcional y solo se vincula a `127.0.0.1`. Los clientes y servicios de modelo conectados tratan los datos recibidos según sus políticas y configuración.
- **Observación en segundo plano:** Es opcional en Pro y está desactivada por defecto. Las observaciones se guardan localmente; la recopilación se pausa cuando el Mac entra en reposo.
- **Comprobaciones de actualización:** La edición de GitHub contacta con GitHub cuando solicitas una comprobación o activas las comprobaciones automáticas.

📋 [Política de seguridad](SECURITY.md) · 📝 [Changelog](https://github.com/ShiinaLabs/wifi-lens/releases) · ❓ [FAQ](https://wifi-lens.shiinalabs.com/es/faq/?utm_source=github&utm_medium=readme&utm_campaign=github_readme) · 🌐 [Política de privacidad completa](https://wifi-lens.shiinalabs.com/es/privacy/?utm_source=github&utm_medium=readme&utm_campaign=github_readme)

---

## Obtener WiFi Lens

Requiere **macOS 14.6 (Sonoma) o posterior**. Funciona tanto en Intel como en Apple Silicon. El escaneo de 6 GHz requiere hardware Wi-Fi 6E/7.

### WiFi Lens Pro
WiFi Lens Pro añade estado en la barra de menús, Network Experience, Problem History, grabación del espectro, observación opcional en segundo plano y una prueba de llamadas Wi-Fi específica del operador al análisis Wi-Fi en directo. Está disponible en el [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8).

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="Descargar en el Mac App Store" width="190"></a>
</p>

### Edición de código abierto

Para la distribución por GitHub y el desarrollo de la comunidad:

- [GitHub Releases](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
- Homebrew: `brew tap ShiinaLabs/apps && brew install --cask ShiinaLabs/apps/wifi-lens`
- Código fuente: este repositorio

> [!IMPORTANT]
> En macOS 14.6+, los **Servicios de ubicación** deben estar activados para que la app lea los nombres SSID de Wi-Fi. Ve a **Ajustes del Sistema → Privacidad y seguridad → Localización** y activa WiFi Lens cuando se solicite.

---

## Desarrollo

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

La documentación de arquitectura está en [docs/](docs/).

---

## Contribuir

Son bienvenidos los informes de errores, las ideas de funciones y las preguntas. Consulta las [directrices para contribuir](.github/CONTRIBUTING.md) para conocer la configuración, las convenciones de pull requests y los requisitos de localización.

Únete a **[Rabbit Hole](https://discord.gg/gH6sTCYaJ7)**, una pequeña comunidad para WiFi Lens y otros proyectos.

**Contacto:** [@WiFiLens en X](https://x.com/WiFiLens) · [contacts@shiinalabs.com](mailto:contacts@shiinalabs.com)

---

## Licencia

Bifurcado de [tiny-wifi-analyzer](https://github.com/nolze/tiny-wifi-analyzer). Los datos de fabricantes MAC proceden de [IEEE Registration Authority](https://standards.ieee.org/products-programs/regauth/); consulta los [avisos de terceros](docs/THIRD-PARTY-NOTICES.md).

Apache License 2.0 © 2020 nolze, 2026 ShiinaLabs — consulta [LICENSE](LICENSE).
