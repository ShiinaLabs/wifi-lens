<h1 align="center">WiFi Lens Pro</h1>

<p align="center"><strong>Descubre qué está pasando con tu Wi-Fi.</strong></p>
<p align="center">Una app nativa para macOS de análisis Wi-Fi y diagnóstico de red.<br>Diagnostica problemas de conexión, observa tu red cuando lo necesites e investiga problemas recurrentes con evidencias históricas.</p>
<p align="center"><a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="Obtener WiFi Lens Pro en el Mac App Store" width="190"></a></p>
<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.6%2B-555?style=flat" alt="macOS 14.6+">
  <img src="https://img.shields.io/badge/Chip-Intel%20%7C%20Apple%20Silicon-555?style=flat" alt="Intel y Apple Silicon">
  <img src="https://img.shields.io/badge/Telemetry-None-555?style=flat" alt="Sin telemetría">
</p>
<p align="center"><a href="https://wifi-lens.shiinalabs.com/es/?utm_source=github&amp;utm_medium=readme&amp;utm_campaign=github_readme">Sitio web oficial</a> &nbsp;·&nbsp; Pago único</p>
<p align="center"><img src="assets/screenshot-network-experience.webp" alt="WiFi Lens Pro — análisis de fiabilidad de red en Network Experience" width="880"></p>
<p align="center"><sub>Network Experience · Evalúa la fiabilidad de la red a partir de observaciones registradas</sub></p>

---

<p align="center"><a href="README.md">🇺🇸 English</a> · <a href="README.de.md">🇩🇪 Deutsch</a> · <strong>🇪🇸 Español</strong> · <a href="README.fr.md">🇫🇷 Français</a> · <a href="README.zh-Hans.md">🇨🇳 简体中文</a> · <a href="README.ja.md">🇯🇵 日本語</a> · <a href="README.zh-Hant.md">🇭🇰 繁體中文</a></p>

## Los problemas de Wi-Fi no esperan a que estés preparado

La conexión Wi-Fi puede interrumpirse de repente, la latencia puede aumentar bruscamente o la conexión puede recuperarse por sí sola. Cuando te dispones a investigar, quizá el problema ya haya desaparecido.

**WiFi Lens Pro te ayuda a comprobar tu red ahora y a mantenerla bajo observación cuando lo necesites, para que los problemas recurrentes dejen evidencias que puedas investigar.**

| **🔍 01 · Diagnosticar ahora** | **📡 02 · Mantener la observación** | **🗂️ 03 · Investigar el historial** |
|:---|:---|:---|
| Comprende tu conexión actual y el entorno inalámbrico | Recopila observaciones cuando lo necesites | Revisa la fiabilidad, las referencias históricas y las evidencias de problemas |
| [Ver diagnóstico de red](#01--diagnosticar-ahora) | [Ver observación continua](#02--mantener-la-observación) | [Ver investigación histórica](#03--investigar-el-historial) |

---

## 01 · Diagnosticar ahora

### Empieza por averiguar dónde puede estar el problema

Usa **Network Check** para revisar la ruta de conexión en tres etapas: **This Mac, LAN e Internet**. Consulta las comprobaciones del gateway, DNS, HTTP/HTTPS, IPv6 opcional y el proxy configurado. Los resultados ayudan a distinguir los fallos confirmados de los casos en los que no hay evidencias suficientes.

Si el entorno inalámbrico puede estar implicado, el **análisis Wi-Fi** muestra las redes cercanas de 2,4 / 5 / 6 GHz, la intensidad de señal, el uso y la congestión de los canales, los detalles de seguridad y recomendaciones de canales adaptadas a la región.

<table>
<tr>
<td width="50%" align="center"><img src="assets/screenshot-selfcheck.webp" alt="Diagnóstico de Network Check" width="100%"><sub>Network Check · Comprueba la conexión por etapas</sub></td>
<td width="50%" align="center"><img src="assets/screenshot-hero.webp" alt="Análisis Wi-Fi en directo y recomendaciones de canales" width="100%"><sub>Análisis Wi-Fi · Explora el entorno inalámbrico</sub></td>
</tr>
</table>

Estas dos capacidades en directo también están incluidas en la edición gratuita de código abierto. Pro las amplía con observación continua e investigación histórica.

---

## 02 · Mantener la observación

### No tienes que quedarte delante de la pantalla esperando a que vuelva el problema

Algunas incidencias solo duran unos segundos. En lugar de abrir un analizador una y otra vez, puedes observar tu red cuando lo necesites y conservar registros para revisarlos más tarde.

| Capacidad | Qué permite hacer |
|---|---|
| **Estado en la barra de menús** | Muestra la conexión actual, el estado del gateway, los cambios recientes y las tendencias a corto plazo. |
| **Continuous Observation** | Recopila opcionalmente observaciones de red compatibles después de cerrar la app Pro. Está desactivada de forma predeterminada y se pausa cuando el Mac entra en reposo. |
| **Spectrum → Recording** | Registra los cambios de señal de un AP seleccionado. Puedes guardar las grabaciones y volver a cargarlas para revisarlas más tarde. |

---

## 03 · Investigar el historial

### El problema puede haber desaparecido, pero sus evidencias siguen siendo útiles

Las capacidades históricas de Pro se centran en **Network Experience** y **Problem History**. Así puedes seguir las evidencias registradas en lugar de intentar interpretar por tu cuenta una colección de gráficos desconectados.

**Fiabilidad de red (Network Experience → Reliability)**

Elige una red y un intervalo de tiempo para consultar una evaluación de fiabilidad basada en las evidencias disponibles, incluidos los problemas detectados y cuándo ocurrieron. Los periodos con una cobertura de observación insuficiente no se consideran una prueba de que la red funcionara correctamente.

**Referencia histórica (Network Experience → Baseline)**

Compara las mediciones guardadas de latencia del gateway con referencias históricas compatibles. Esto muestra cambios relativos respaldados por evidencias; una desviación aislada no demuestra por sí sola que la red haya fallado.

**Registros de problemas (Problem History)**

Consulta los registros de problemas guardados, sus evidencias y las observaciones posteriores. Cuando las evidencias lo justifiquen, puedes seguir una sugerencia de comprobación hasta la herramienta correspondiente. La ejecución de esa comprobación sigue siendo una acción que realiza el usuario de forma explícita.

<table>
<tr>
<td width="50%" align="center"><img src="assets/screenshot-historical-baseline.webp" alt="Comparación histórica de la latencia del gateway" width="100%"><sub>Historical Baseline · Compara mediciones históricas compatibles</sub></td>
<td width="50%" align="center"><img src="assets/screenshot-problem-history.webp" alt="Registros y evidencias de Problem History" width="100%"><sub>Problem History · Revisa los problemas registrados y sus evidencias</sub></td>
</tr>
</table>

<p align="center"><strong>Comprueba lo que ocurre ahora, observa la red con el tiempo e investiga más adelante.</strong></p>
<p align="center">Esa es la experiencia completa de WiFi Lens Pro.</p>
<p align="center"><a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>Obtener WiFi Lens Pro</strong></a></p>

---

## Más herramientas útiles

Además de este flujo de trabajo, WiFi Lens ofrece pruebas de roaming, mapas de calor de canales, AP Radar, escaneo Bluetooth LE, exportación de gráficos e integración MCP local.

WiFi Lens Pro también incluye **Wi-Fi Calling Test** para escenarios específicos de operadores, con perfiles predefinidos o valores MCC/MNC personalizados.

## Pro y código abierto

La edición gratuita de código abierto ofrece análisis Wi-Fi en directo y diagnóstico de red local. **WiFi Lens Pro** amplía esas capacidades con observación continua, análisis histórico e investigación de problemas.

| Función | Pro | Código abierto |
|---|:---:|:---:|
| Análisis Wi-Fi, calidad de canales y recomendaciones | ✓ | ✓ |
| Network Check | ✓ | ✓ |
| Pruebas de roaming, AP Radar y mapas de calor de canales | ✓ | ✓ |
| MCP local y exportación de gráficos | ✓ | ✓ |
| Estado en la barra de menús y observación continua | ✓ | — |
| Fiabilidad de red y referencias históricas | ✓ | — |
| Registros de problemas e investigación histórica | ✓ | — |
| Grabación de espectro y Wi-Fi Calling Test | ✓ | — |

<p align="center"><a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8">Obtener WiFi Lens Pro</a> &nbsp;·&nbsp; <a href="https://github.com/ShiinaLabs/wifi-lens/releases/latest">Descargar la edición gratuita de código abierto</a></p>

---

## Privacidad y datos

WiFi Lens procesa los datos de escaneo Wi-Fi en tu Mac. No requiere cuenta, sincronización en la nube ni telemetría de uso.

- **Network Check:** Se conecta a destinos públicos de diagnóstico y, cuando corresponde, comprueba el proxy configurado.
- **Continuous Observation:** Está desactivada de forma predeterminada. Los datos de observación permanecen en tu Mac y la recopilación se pausa durante el reposo.
- **MCP local:** El servidor solo se enlaza a `127.0.0.1`. Si tu cliente de IA se conecta a un servicio externo, revisa por separado cómo gestiona los datos ese cliente.
- **Permisos del sistema:** macOS exige permiso de Localización para que las apps puedan leer los SSID Wi-Fi. WiFi Lens no lee tu ubicación GPS.

Consulta la [política de privacidad completa](https://wifi-lens.shiinalabs.com/es/privacy/?utm_source=github&utm_medium=readme&utm_campaign=github_readme).

## Obtener WiFi Lens

**WiFi Lens Pro:** Compra única en el [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8). Requiere macOS 14.6+ y es compatible con Intel y Apple Silicon. El escaneo de 6 GHz requiere hardware Wi-Fi 6E/7.

**WiFi Lens de código abierto:** Descárgalo desde [GitHub Releases](https://github.com/ShiinaLabs/wifi-lens/releases/latest) o mediante Homebrew:

<p>
<a href="https://github.com/ShiinaLabs/wifi-lens/releases/latest"><img src="https://img.shields.io/github/v/release/ShiinaLabs/wifi-lens?label=Latest&amp;color=2563eb" alt="Última versión"></a>
<a href="https://github.com/ShiinaLabs/wifi-lens/releases/latest"><img src="https://img.shields.io/github/downloads/ShiinaLabs/wifi-lens/WiFiLens.dmg?label=Downloads&amp;displayAssetName=false&amp;color=2563eb" alt="Descargas"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue" alt="Licencia Apache 2.0"></a>
</p>

```sh
brew tap ShiinaLabs/apps
brew install --cask ShiinaLabs/apps/wifi-lens
```

<details>
<summary><strong>IA / MCP: integración y configuración</strong></summary>

WiFi Lens ofrece un servidor MCP local opcional. Al activarlo, las herramientas de IA compatibles pueden leer datos de escaneo Wi-Fi en directo, como el uso de canales cercanos y la información de seguridad de las redes.

El servidor solo se enlaza a `127.0.0.1`. Ejemplo de configuración para un cliente MCP:

```json
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840/"
    }
  }
}
```

Configuración de Codex:

```toml
[mcp_servers.wifi-lens]
url = "http://127.0.0.1:19840/"
```

Encontrarás más ejemplos en la [guía de flujos de trabajo de IA](https://wifi-lens.shiinalabs.com/es/ai-mcp/?utm_source=github&utm_medium=readme&utm_campaign=github_readme).

</details>

<details>
<summary><strong>Desarrollo y contribución</strong></summary>

```sh
git clone https://github.com/ShiinaLabs/wifi-lens
cd wifi-lens
git submodule update --init ChartLens
cd WiFiLens

xcodebuild -project WiFiLens.xcodeproj -scheme "WiFi Lens" \
  -configuration Debug -destination 'platform=macOS' build

xcodebuild -project WiFiLens.xcodeproj -scheme "WiFi Lens" \
  -configuration Debug -destination 'platform=macOS' \
  -skipPackageUpdates test -only-testing:WiFiLensTests -only-testing:WiFiLensCoreTests
```

Consulta [docs/](docs/) para la documentación de arquitectura y la [guía de contribución](.github/CONTRIBUTING.md) para informar de errores, proponer mejoras y enviar pull requests.

</details>

## Comunidad y licencia

Únete a [Rabbit Hole](https://discord.gg/gH6sTCYaJ7) para hablar sobre WiFi Lens y otros proyectos.

**Contacto:** [@WiFiLens](https://x.com/WiFiLens) · [contacts@shiinalabs.com](mailto:contacts@shiinalabs.com)

Este proyecto es un fork de [tiny-wifi-analyzer](https://github.com/nolze/tiny-wifi-analyzer). Los datos de fabricantes MAC proceden de [IEEE Registration Authority](https://standards.ieee.org/products-programs/regauth/); consulta los [avisos de terceros](docs/THIRD-PARTY-NOTICES.md).

Apache License 2.0 © 2020 nolze, 2026 ShiinaLabs — consulta [LICENSE](LICENSE).
