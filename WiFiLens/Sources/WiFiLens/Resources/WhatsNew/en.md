# What's New in 2.0

WiFi Lens 2.0 is a major foundation release focused on making Wi-Fi analysis more accurate, reliable, and consistent.

## Join the Community

Questions, feedback, or just want to talk about WiFi Lens?

**Join us on Discord:** https://discord.gg/gH6sTCYaJ7

## Deeper Wi-Fi Protocol Analysis

* WiFi Lens now performs more robust low-level parsing of 802.11 Information Elements advertised by nearby access points.
* Improved detection of operating channel width, including 20, 40, 80, 160, and 80+80 MHz configurations.
* More reliable identification of WPA3 security, encryption suites, 802.11k/r/v/w capabilities, Wi-Fi generations, MCS, and spatial streams.
* Malformed or incomplete wireless metadata is now handled more conservatively instead of being guessed, reducing misleading capability results.

## A Stronger Troubleshooting Foundation

* Network Self-Check has been rebuilt around clearer, evidence-based diagnostics for connectivity, DNS, HTTPS, IPv6, and configured proxies.
* Wi-Fi analysis components now share a cleaner internal architecture, improving consistency across Spectrum, Channels, Interfaces, AP Radar, and diagnostics.
* Runtime and storage handling have been redesigned to better protect user data and improve reliability across different app environments.

## WiFi Lens Pro

* Timeline storage and historical data handling are more robust, including safer migration for existing installations.
* Long-term observation infrastructure has been strengthened to provide a more dependable foundation for history, Statistics, Insights, and investigation workflows.
* Production and development environments now use isolated identities, storage, and MCP endpoints.

## AI & MCP

* The built-in MCP server is now integrated more cleanly with the app runtime.
* Compatible AI clients can continue to access live Wi-Fi information locally through the MCP endpoint enabled in Settings.
* MCP environments are now better isolated between development and production builds.

## Reliability

* Improved persistence boundaries, startup validation, logging, crash diagnostics, and MetricKit storage.
* Numerous fixes and tests were added across networking, diagnostics, localization, accessibility, and runtime behavior.

WiFi Lens 2.0 provides a more trustworthy foundation for understanding what your wireless environment is actually advertising — and for investigating problems when they happen.
