# Third-Party Notices

This file lists third-party data sources bundled with or downloaded by WiFi Lens.

## Swift Packages

### ChartLens

WiFi Lens uses the Apache-2.0-licensed [ChartLens](https://github.com/ShiinaLabs/chart-lens) Swift package from ShiinaLabs.

- Pinned revision: `e2e00e5253a51e7031d30cf41015ff146cd9a886`
- License: [Apache-2.0](https://github.com/ShiinaLabs/chart-lens/blob/master/LICENSE)

### SplitView

WiFi Lens uses the MIT-licensed [SplitView](https://github.com/ShiinaLabs/SplitView) Swift package from ShiinaLabs.

- Pinned revision: `7737a80740919c2fa94a6e64f870d37ef77b9b5f`
- License: [MIT](https://github.com/ShiinaLabs/SplitView/blob/main/LICENSE)

## MAC Vendor Database (IEEE Registry Data)

WiFi Lens bundles a pre-built MAC address prefix-to-organization mapping derived from the IEEE Standards Association Registration Authority public registries. It also supports runtime download of the same registries.

- Source: [IEEE Registration Authority](https://standards.ieee.org/products-programs/regauth/)
- Registries used: MA-L (OUI), MA-M (OUI-28), MA-S (OUI-36), IAB
- Download endpoints:
  - https://standards-oui.ieee.org/oui/oui.csv
  - https://standards-oui.ieee.org/oui28/mam.csv
  - https://standards-oui.ieee.org/oui36/oui36.csv
  - https://standards-oui.ieee.org/iab/iab.csv

IEEE does not endorse WiFi Lens and is not affiliated with this project. All trademarks and registry content remain the property of the IEEE Standards Association and its registrants.
