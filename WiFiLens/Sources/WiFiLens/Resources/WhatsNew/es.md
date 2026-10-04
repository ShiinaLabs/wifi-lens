# Novedades de la versión 2.0

WiFi Lens 2.0 refuerza los cimientos para que el análisis Wi-Fi sea más preciso, fiable y coherente.

## Únete a la comunidad

¿Tienes preguntas, comentarios o simplemente quieres hablar sobre WiFi Lens?

**Únete a Discord:** https://discord.gg/gH6sTCYaJ7

## Análisis más profundo de los protocolos Wi-Fi

* WiFi Lens ahora analiza con mayor solidez y a bajo nivel los elementos de información 802.11 que anuncian los puntos de acceso cercanos.
* Mejoramos la detección del ancho de canal en uso, incluidas las configuraciones de 20, 40, 80, 160 y 80+80 MHz.
* Ahora identifica de forma más fiable la seguridad WPA3, las suites de cifrado, las capacidades 802.11k/r/v/w, las generaciones Wi-Fi, MCS y los flujos espaciales.
* Los metadatos inalámbricos incompletos o malformados se procesan con más cautela en lugar de inferirse, para reducir resultados de capacidades engañosos.

## Una base más sólida para solucionar problemas

* Reconstruimos Network Self-Check con diagnósticos más claros y basados en evidencias para la conectividad, DNS, HTTPS, IPv6 y los proxies configurados.
* Los componentes de análisis Wi-Fi ahora comparten una arquitectura interna más limpia, lo que mejora la coherencia entre Spectrum, Channels, Interfaces, AP Radar y los diagnósticos.
* Rediseñamos la gestión del entorno de ejecución y del almacenamiento para proteger mejor los datos de usuario y mejorar la fiabilidad entre distintos entornos de la app.

## WiFi Lens Pro

* El almacenamiento de Timeline y la gestión del historial son más fiables, incluida una migración más segura para las instalaciones existentes.
* Reforzamos la infraestructura de observación a largo plazo para ofrecer una base más fiable para el historial, Statistics, Insights y los flujos de investigación.
* Los entornos de producción y desarrollo ahora tienen identidades, almacenamiento y endpoints MCP aislados.

## IA y MCP

* El servidor MCP integrado ahora se conecta de forma más limpia con el entorno de ejecución de la app.
* Los clientes de IA compatibles pueden seguir accediendo localmente a información Wi-Fi en tiempo real mediante el endpoint MCP activado en Ajustes.
* Los entornos MCP están mejor aislados entre las compilaciones de desarrollo y producción.

## Fiabilidad

* Mejoramos los límites de persistencia, la validación al iniciar, el registro, el diagnóstico de fallos y el almacenamiento de MetricKit.
* Añadimos numerosas correcciones y pruebas para redes, diagnósticos, localización, accesibilidad y comportamiento en tiempo de ejecución.

WiFi Lens 2.0 ofrece una base más fiable para entender lo que realmente anuncia tu entorno inalámbrico y para investigar los problemas cuando aparecen.
