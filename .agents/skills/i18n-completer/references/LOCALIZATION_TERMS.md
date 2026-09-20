# Localization Terminology Guide

Standardized terms for `en`, `de`, `es`, `fr`, `ja`, `ru`, `zh-Hans` translations in `Localizable.xcstrings`.

## zh-Hans (简体中文)

| English | Use | Do NOT use | Notes |
|---------|-----|------------|-------|
| channel | 信道 | ~~频道~~, ~~通路~~ | Consistent with existing 38+ strings |
| Wi-Fi (technology) | Wi-Fi | ~~WIFI~~, ~~Wifi~~ | Hyphenated, per Apple convention |
| WiFi Lens (product) | WiFi Lens | ~~Wifi Lens~~, ~~Wi-Fi Lens~~ | Product name, no hyphen |
| AP | AP | ~~接入点~~, ~~热点~~ | Abbreviation kept as-is, per industry standard |
| network | 网络 | ~~网络连接~~ | |
| Bluetooth | 蓝牙 | ~~蓝牙技术~~ | |
| signal | 信号 | ~~讯号~~ | |
| scan / scanning | 扫描 | ~~探测~~, ~~侦测~~ | |
| System Settings | 系统设置 | ~~系统偏好设置~~ | macOS 13+ uses "系统设置" |
| Preferences (pane) | 偏好设置 | ~~偏好设定~~ | For specific preference panes |
| device | 设备 | ~~装置~~ | |
| interface | 接口 | ~~界面~~ (for network interfaces) | "界面" reserved for UI context |
| recommendation | 推荐 | ~~建议~~ (for channel recommendations) | "建议" used for advice/diagnosis |
| you (informal) | 你 | ~~您~~ | App uses informal tone throughout |
| open (verb) | 打开 | ~~开启~~ | For opening settings/apps |
| enable (verb) | 开启 | ~~启用~~ | For toggling features on |
| disabled | 已关闭 | ~~已禁用~~, ~~已停用~~ | For feature toggles |
| granted | 已授予 | ~~已允许~~ | For permission states |
| denied | 被拒绝 | ~~被拒~~ | For permission states |
| excellent | 优秀 | ~~极佳~~ | Quality tier |
| good | 良好 | ~~好~~ | Quality tier |
| moderate | 一般 | ~~中等~~ | Quality tier |
| busy | 繁忙 | ~~忙碌~~ | Quality tier |
| congested | 拥堵 | ~~拥塞~~ | Quality tier |
| low (overlap) | 低 | — | Overlap level |
| moderate (overlap) | 中等 | — | Overlap level |
| high (overlap) | 高 | — | Overlap level |

## ja (日本語)

| English | Use | Do NOT use | Notes |
|---------|-----|------------|-------|
| channel | チャンネル | ~~周波数~~ | "周波数帯" acceptable for "frequency band" |
| Wi-Fi | Wi-Fi | — | |
| WiFi Lens | WiFi Lens | — | Product name |
| AP | AP | ~~アクセスポイント~~ | Abbreviation kept as-is |
| scan | スキャン | ~~探査~~ | |
| System Settings | システム設定 | — | |
| recommendation | 推奨 | ~~勧め~~ | |
| permission (noun) | 権限 | — | "許可" reserved for verb "allow/grant" |

## de (Deutsch)

| English | Use | Do NOT use | Notes |
|---------|-----|------------|-------|
| channel | Kanal | ~~Frequenz~~ | |
| Wi-Fi | Wi-Fi | — | |
| WiFi Lens | WiFi Lens | — | Product name |
| AP | AP | ~~Zugangspunkt~~ | Abbreviation kept as-is |
| scan | Scan | ~~Abtastung~~ | |
| System Settings | Systemeinstellungen | — | |
| recommendation | Empfehlung | ~~Rat~~ | |

## es (Español)

| English | Use | Do NOT use | Notes |
|---------|-----|------------|-------|
| channel | canal | ~~frecuencia~~ | |
| Wi-Fi | Wi-Fi | — | |
| WiFi Lens | WiFi Lens | — | Product name |
| AP | AP | ~~punto de acceso~~ | Abbreviation kept as-is |
| scan | escaneo | ~~barrido~~ | |
| System Settings | Ajustes del Sistema | — | macOS Spanish localization |
| recommendation | recomendación | ~~sugerencia~~ | |

## General Rules

1. **Product name "WiFi Lens"** — never translate, never hyphenate, always exactly `WiFi Lens`
2. **Technical abbreviations** (AP, RSSI, MCS, NSS, BSSID, SSID, DFS, EMA) — keep as-is in all languages
3. **Apple terminology** — follow Apple's own localization for the target platform (e.g., macOS "System Settings" / "系统設定" / "Systemeinstellungen")
4. **Parameterized strings** — use `%@`, `%lld`, `%1$@` etc. exactly as in English; do not reorder placeholders in translation
5. **Punctuation** — follow target language conventions (e.g., `…` not `...` in ja/zh-Hans, `«»` in fr)
6. **Tone** — use informal "你" (zh-Hans), not formal "您"
7. **AP in prose** — short labels (badges, table headers, menu items) keep the abbreviation `AP`. Longer explanatory prose may expand the full term for readability (zh 接入点, ja アクセスポイント, de Zugangspunkt, es punto de acceso); existing AP Radar long-form usages are sanctioned.

## fr (Français)

| English | Use | Do NOT use | Notes |
|---------|-----|------------|-------|
| channel | canal | ~~fréquence~~ | "fréquence" reserved for frequency (e.g. frequency band = bande de fréquence) |
| Wi-Fi | Wi-Fi | — | |
| WiFi Lens | WiFi Lens | — | Product name, never hyphenated |
| AP | AP | ~~point d'accès~~ | Abbreviation kept as-is in short labels/badges; prose may expand to "point d'accès" |
| scan / scanning | scan / analyse | ~~balayage~~ | "analyse" for analysis; "scan" for the scan action/feature |
| System Settings | Réglages Système | ~~Préférences Système~~ | macOS 13+ French uses "Réglages Système" |
| recommendation | recommandation | ~~suggestion~~ | For channel recommendations |
| permission (noun) | autorisation | — | "autoriser" for the verb allow/grant |
| network | réseau | — | |
| device | appareil | ~~dispositif~~ | |
| signal | signal | — | |
| hide / hidden (network) | masquer / réseau masqué | ~~caché~~ | |
| enable (verb) | activer | — | For toggling features on |
| disabled | désactivé | — | For feature states/toggles |
| granted | accordée / accordé | — | Permission states |
| denied | refusée / refusé | — | Permission states |
| overlap | chevauchement | ~~recouvrement~~ | Channel overlap |
| open (verb) | ouvrir | — | Opening settings/apps |
| interface (network) | interface | — | Network interface |
| you (informal) | tu | ~~vous~~ | App uses informal tone throughout |

## General Rules (fr addition)

1. **Guillemets** — use `« »` for quoted text in French
2. **Feminine/plural agreement** — match the noun gender/number for quality tiers, permission states, and "X est/est désactivé" forms
3. **Product name & abbreviations** — never translate `WiFi Lens`, `AP`, `RSSI`, `MCS`, `NSS`, `BSSID`, `SSID`, `DFS`, `EMA` in short labels; keep them as-is

## ru (Русский)

| English | Use | Do NOT use | Notes |
|---------|-----|------------|-------|
| channel | канал | ~~частота~~ | «Частота» is reserved for frequency |
| Wi-Fi (technology) | Wi‑Fi | ~~WiFi~~, ~~вайфай~~ | Follow Apple Russian typography |
| WiFi Lens (product) | WiFi Lens | ~~Wi‑Fi Lens~~ | Product name, never translate |
| AP (short UI) | AP | ~~ТД~~ | Keep the industry abbreviation in badges, tables, and compact labels |
| access point (prose) | точка доступа | ~~роутер~~ | Use the full term in explanatory prose |
| scan / scanning | сканировать / сканирование | ~~скан~~ | Choose verb or noun by UI context |
| System Settings | Системные настройки | ~~Системные параметры~~ | Apple macOS terminology |
| Location Services | Службы геолокации | ~~Сервисы геолокации~~ | Apple macOS terminology |
| menu bar | строка меню | ~~панель меню~~ | Apple macOS terminology |
| Show in Finder | Показать в Finder | ~~Открыть в Finder~~ | Apple macOS menu wording |
| network | сеть | — | |
| network interface | сетевой интерфейс | ~~интерфейс сети~~ | |
| gateway | шлюз | ~~гейтвей~~ | |
| router | маршрутизатор | ~~роутер~~ | Prefer the standard technical term in UI |
| signal strength | уровень сигнала | ~~сила сигнала~~ | Natural Russian UI terminology |
| interference | помехи | ~~интерференция~~ | Wireless interference |
| overlap | перекрытие | ~~наложение~~ | Channel overlap |
| roaming | роуминг | ~~перемещение~~ | Wi-Fi roaming |
| latency | задержка | ~~латентность~~ | |
| throughput | пропускная способность | ~~пропускная скорость~~ | |
| Timeline | хронология | ~~таймлайн~~ | Product feature name in Russian |
| Insights | выводы | ~~инсайты~~ | Product feature name in Russian |
| permission | разрешение / доступ | ~~пермиссия~~ | Pick the natural noun for the sentence |
| enabled / disabled | включено / выключено | ~~активировано / деактивировано~~ | Prefer native macOS-style state wording |
| unknown | неизвестно | — | |

### General Rules (ru addition)

1. Use natural Russian macOS UI wording rather than word-for-word translation.
2. Preserve technical abbreviations such as `AP`, `RSSI`, `MCS`, `NSS`, `BSSID`, `SSID`, `DFS`, `EMA`, `MCC`, `MNC`, `IKE`, and `NAT`.
3. Keep format placeholders (`%@`, `%lld`, `%1$@`, etc.) exactly as in the source and in the same order.
4. Prefer concise imperatives for actions: «Открыть», «Показать», «Сохранить», «Очистить», «Проверить».
5. Avoid unnecessary English loanwords when an established Russian networking or macOS term exists.
6. Use `…` for ellipses and Russian decimal commas in localized prose/units where the value is literal.
7. Product and brand names (`WiFi Lens`, `Finder`, `App Store`, `GitHub`, carrier names) are not translated.
8. Compact table and card metrics use concise terms: keep `AP`, and use `Сосед.`, `Совп.`, and `Блок.` where the UI compares adjacent, co-channel, or lock metrics. Full explanatory wording belongs in prose, not narrow headers.
