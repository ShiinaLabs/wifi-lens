# WiFi Lens

**完整的 Mac Wi-Fi 故障排除工作流程。**

WiFi Lens Pro 將即時 Wi-Fi 分析、網路診斷、持續監測、Timeline 歷史資料、Statistics 和 Insights 整合在一套原生 macOS App 中。

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>取得 WiFi Lens Pro</strong></a>
  &nbsp;·&nbsp;
  <a href="https://wifi-lens.shiinalabs.com">官方網站</a>
</p>

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="在 Mac App Store 下載" width="190"></a>
</p>

<p align="center"><img alt="WiFi Lens Pro 在 macOS 上顯示 Event Timeline 歷史資料" src="assets/screenshot-timeline.webp" width="800"></p>

<p align="center">macOS 14.6+ &nbsp;·&nbsp; Apple Silicon 與 Intel &nbsp;·&nbsp; 不含遙測</p>

<p align="center">
  🔒 <strong>以本機為主的隱私設計</strong> — 無帳號、無雲端、無遙測<br>
  🩺 <strong>以證據為本的診斷</strong> — 可解釋的路徑、DNS、HTTPS 和代理伺服器檢查<br>
  🤖 <strong>支援 AI 工作流程的 MCP</strong> — 讓相容用戶端在 Mac 上存取即時 Wi-Fi 資料
</p>

<p align="center"><sub>本儲存庫提供 WiFi Lens 開放原始碼版，適用於即時本機分析、開發、檢視原始碼和社群協作。</sub></p>

---

<p align="center">
  <a href="README.md">🇺🇸 English</a> · <a href="README.de.md">🇩🇪 Deutsch</a> · <a href="README.es-ES.md">🇪🇸 Español</a> · <a href="README.fr.md">🇫🇷 Français</a> · <a href="README.zh-Hans.md">🇨🇳 简体中文</a> · <a href="README.ja.md">🇯🇵 日本語</a> · 🇭🇰 繁體中文
</p>
<p align="center">
  <a href="#為什麼選擇-wifi-lens-pro">為什麼選擇 WiFi Lens Pro</a> · <a href="#核心功能">核心功能</a> · <a href="#版本">版本</a> · <a href="#ai--mcp-整合">AI / MCP</a> · <a href="#開放原始碼版">開放原始碼版</a> · <a href="#隱私權">隱私權</a> · <a href="#取得-wifi-lens">取得 WiFi Lens</a> · <a href="#開發">開發</a> · <a href="#參與貢獻">參與貢獻</a> · <a href="#授權條款">授權條款</a>
</p>

---

## 為什麼選擇 WiFi Lens Pro

即時診斷能告訴你目前發生的狀況。遇到間歇性問題時，WiFi Lens Pro 會持續記錄相關資訊：觀察網路、記下事件、保存歷史資料，並協助你事後調查。

| 工作流程 | WiFi Lens Pro 提供的功能 |
|--------|--------------------------|
| 立即診斷 | 即時 Wi-Fi 分析、信道分析和網路診斷 |
| 持續觀察 | 選單列監測和連續觀測 |
| 捕捉偶發問題 | Timeline 與頻譜記錄 |
| 回顧過去狀況 | 歷史事件和連線變化 |
| 找出模式 | 跨記錄時段的 Statistics |
| 理解證據 | 根據記錄觀測資料整理的 Insights |

**WiFi Lens Pro 是完整版本。** 它將即時分析工具與監測、歷史資料及調查功能整合為完整工作流程。

<table>
<tr>
<td width="50%" align="center"><img alt="網路自我檢查診斷畫面" src="assets/screenshot-selfcheck.webp" width="100%"><sub>Network Self-Check</sub></td>
<td width="50%" align="center"><img alt="顯示連線歷史資料的 Event Timeline" src="assets/screenshot-timeline.webp" width="100%"><sub>Event Timeline（Pro）</sub></td>
</tr>
</table>

### 立即診斷 → 事後調查

Wi-Fi 問題常在你來得及檢查前就消失。WiFi Lens Pro 會保留中斷連線、漫遊或訊號變化前後的證據，讓你稍後檢視事件和當時的網路狀態。

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>取得 WiFi Lens Pro →</strong></a>
</p>

---

## 核心功能

WiFi Lens 將理解本機 Wi-Fi 環境所需的基本工具整合在原生 Mac App 中。

| 功能 | 用途 |
|------|------|
| 📡 Wi-Fi 掃描 | 掃描 2.4、5 和 6 GHz 頻段的附近網路 |
| 📊 頻譜與信道品質 | 檢視使用狀況、壅塞評分和依地區提供的信道建議 |
| 🔍 網路詳細資訊 | 檢視 PHY 世代、信道寬度、802.11k/r/v、WPA3 和連線資訊 |
| 🚶 漫遊與熱度圖 | 確認 AP 切換情況並比較各頻段的使用狀況 |
| 🩺 Network Self-Check（預覽） | 檢查路徑、DNS、HTTPS 和已設定代理伺服器的連線能力 |
| 📻 AP Radar（預覽） | 追蹤選取的 AP，提供根據 RSSI 的指引和選用音訊回饋 |
| 🤖 MCP 與匯出 | 連線至本機 AI 工具，並將圖表儲存為 PNG 或 CSV |
| 🔒 以本機為主的隱私設計 | 掃描資料保留在 Mac 上，不收集使用情況遙測 |

---

## 版本

### WiFi Lens Pro

**WiFi Lens Pro 是完整版本。** 可透過 [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8) 一次購買，適合需要持續觀察、記錄、歷史資料和調查功能的使用者。

### 開放原始碼版

開放原始碼版提供完整的即時分析功能，適合偏好透過 GitHub 取得 App、檢視原始碼並參與社群貢獻的使用者。請至 [GitHub Releases](https://github.com/SHIINASAMA/wifi-lens/releases/latest) 下載。

| 功能 | WiFi Lens Pro | 開放原始碼版 |
|------|---------------|--------------|
| 即時 Wi-Fi 分析 | ✅ | ✅ |
| 網路診斷 | ✅ | ✅ |
| 信道建議 | ✅ | ✅ |
| 持續監測 | ✅ | — |
| 事件歷史資料 | ✅ | — |
| 歷史統計 | ✅ | — |
| Insights | ✅ | — |
| 頻譜記錄 | ✅ | — |
| 選單列監測 | ✅ | — |

兩個版本都以本機處理為基礎。兩者的差異在於即時分析以外的工作流程：Pro 提供持續觀察、保存背景資訊和調查長期問題所需的功能。

---

## AI / MCP 整合

WiFi Lens 內建 MCP 伺服器，讓相容的 AI 助理讀取本機 Wi-Fi 資料。在「設定」中啟用後，選取「複製 AI 設定提示」，再將提示貼到 Codex Desktop、Claude Desktop 等相容 MCP 的桌面用戶端。

```json
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840"
    }
  }
}
```

手動設定時，請使用用戶端要求的格式：

```toml
# Codex: ~/.codex/config.toml
[mcp_servers.wifi-lens]
url = "http://127.0.0.1:19840/"
```

```json
// Claude Desktop and other JSON-based clients
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840/"
    }
  }
}
```

連線後，你可以詢問 AI 助理「附近哪些信道比較壅塞？」或「附近哪些網路支援 WPA3？」。伺服器只會繫結至 `127.0.0.1`；除非你主動將流量路由到其他位置，否則資料不會離開這部電腦。

更多範例請參閱 [AI 工作流程指南](https://wifi-lens.shiinalabs.com/ai-mcp/)。

---

## 開放原始碼版

開放原始碼版適用於本機分析、開發、檢視原始碼和社群協作。

- **GitHub Releases** — [下載最新版本](https://github.com/SHIINASAMA/wifi-lens/releases/latest)
- **Homebrew** — `brew tap ShiinaLabs/apps && brew install --cask ShiinaLabs/apps/wifi-lens`
- **原始碼與文件** — 瀏覽本儲存庫和[架構文件](docs/)

<details>
<summary>開放原始碼版功能</summary>

| 功能 | 說明 | 狀態 |
|------|------|------|
| 📡 Wi-Fi 掃描 | 即時掃描 2.4 / 5 / 6 GHz 頻段 | 穩定 |
| 📊 頻譜檢視 | 以高斯曲線呈現信道使用狀況 | 穩定 |
| 🎯 信道品質 | 壅塞評分和依地區提供的建議 | 穩定 |
| 🔍 網路詳細資訊 | PHY 世代、信道寬度、802.11k/r/v、WPA3 | 穩定 |
| 📶 連線資訊 | IP、閘道器、DNS、MAC、傳送速率和安全性摘要 | 穩定 |
| 🚶 漫遊測試 | 監測 AP 切換並儲存／載入工作階段 | 穩定 |
| 🗺️ 信道熱度圖 | 各頻段的使用率熱度圖 | 穩定 |
| 🎧 BLE 掃描器 | Bluetooth LE 裝置探索、RSSI 分析和追蹤 | 穩定 |
| 🎨 智慧著色 | 依 SSID 決定顏色，結果一致 | 穩定 |
| 🌐 MCP 伺服器 | 整合 AI 工具的內嵌 HTTP API | 穩定 |
| 📤 匯出 | 將圖表儲存為 PNG 或 CSV | 穩定 |
| 🔒 隱私優先 | 不含遙測；掃描資料保留在 Mac 上 | 穩定 |
| ⬆️ 自動更新 | GitHub 版本使用 Sparkle | 穩定 |
| 🌍 本地化 | 英文、德文、西班牙文、日文、簡體中文及繁體中文 | 穩定 |
| 🩺 Network Self-Check | 一鍵檢查路徑、DNS、HTTPS 和代理伺服器 | 預覽 |
| 📻 AP Radar | 追蹤選取的 AP，並提供音訊脈衝回饋 | 預覽 |

</details>

[![Downloads](https://img.shields.io/github/downloads/SHIINASAMA/wifi-lens/WiFiLens.dmg?label=Downloads&displayAssetName=false&color=2563eb)](https://github.com/SHIINASAMA/wifi-lens/releases/latest)
[![Latest release](https://img.shields.io/github/v/release/SHIINASAMA/wifi-lens?label=Latest&color=2563eb)](https://github.com/SHIINASAMA/wifi-lens/releases/latest)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

---

## 隱私權

WiFi Lens 不會收集使用分析資料、當機遙測或 Wi-Fi 掃描資料。

- **定位服務：** macOS 需要此權限才能提供 Wi-Fi SSID 名稱。WiFi Lens 不會讀取 GPS 位置。
- **地區偵測：** 在裝置上參考系統語言設定、硬體回報的信道清單和附近 AP 的國碼。
- **Network Self-Check：** 會解析公開端點（`www.apple.com`、`www.msftconnecttest.com`），也可能測試已設定代理伺服器端點的連線能力。
- **MCP 伺服器：** 僅繫結至 `127.0.0.1`。啟用後，本機工具才能存取資料。
- **檢查更新：** GitHub 版本只會在你手動檢查更新或啟用自動檢查時連線至 GitHub。

📋 [安全性政策](SECURITY.md) · 📝 [更新紀錄](https://github.com/SHIINASAMA/wifi-lens/releases) · ❓ [常見問題](https://wifi-lens.shiinalabs.com/faq/) · 🌐 [完整隱私權政策](https://wifi-lens.shiinalabs.com/privacy/)

---

## 取得 WiFi Lens

需要 **macOS 14.6（Sonoma）或更新版本**。支援 Intel 和 Apple Silicon。掃描 6 GHz 需要 Wi-Fi 6E/7 硬體。

### WiFi Lens Pro

完整版本支援持續監測、記錄、檢視歷史資料和調查問題。請至 [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8) 下載。

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="在 Mac App Store 下載" width="190"></a>
</p>

### 開放原始碼版

適合 GitHub 發行和社群開發：

- [GitHub Releases](https://github.com/SHIINASAMA/wifi-lens/releases/latest)
- Homebrew：`brew tap ShiinaLabs/apps && brew install --cask ShiinaLabs/apps/wifi-lens`
- 原始碼：本儲存庫

> [!IMPORTANT]
> 在 macOS 14.6 或更新版本中，App 必須取得**定位服務**權限，才能讀取 Wi-Fi SSID 名稱。請前往**系統設定 → 隱私權與安全性 → 定位服務**，並在系統提示時啟用 WiFi Lens。

---

## 開發

```sh
git clone https://github.com/SHIINASAMA/wifi-lens
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

架構文件位於 [docs/](docs/)。

---

## 參與貢獻

歡迎回報問題、提出功能構想和改進建議。請參閱[貢獻指南](.github/CONTRIBUTING.md)，瞭解環境設定、PR 慣例和本地化要求。

歡迎加入 **[Rabbit Hole](https://discord.gg/gH6sTCYaJ7)**，這裡是 WiFi Lens 和其他專案的交流社群。

**聯絡方式：** [X 上的 @WiFiLens](https://x.com/WiFiLens) · [wifi-lens@shiinalabs.com](mailto:wifi-lens@shiinalabs.com)

---

## 授權條款

本專案 fork 自 [tiny-wifi-analyzer](https://github.com/nolze/tiny-wifi-analyzer)。MAC 廠商資料來自 [IEEE Registration Authority](https://standards.ieee.org/products-programs/regauth/)，詳情請參閱[第三方聲明](docs/THIRD-PARTY-NOTICES.md)。

Apache License 2.0 © 2020 nolze, 2026 SHIINASAMA — 詳見 [LICENSE](LICENSE)。
