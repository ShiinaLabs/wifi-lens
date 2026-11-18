# WiFi Lens

**看清 Wi-Fi 正在发生什么。**

从 Mac、路由器到互联网，检查连接可能在哪一环出现问题；分析附近的 Wi-Fi 网络，并进一步调查反复出现的异常。

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>获取 WiFi Lens Pro</strong></a> · <a href="https://github.com/ShiinaLabs/wifi-lens/releases/latest"><strong>免费下载 OSS 版</strong></a> · <a href="https://wifi-lens.shiinalabs.com/zh-Hans/?utm_source=github&amp;utm_medium=readme&amp;utm_campaign=github_readme">官方网站</a>
</p>
<p align="center"><a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="在 Mac App Store 下载" width="190"></a></p>
<p align="center"><img alt="Network Check 展示从这台 Mac、路由器到互联网的连接路径" src="assets/screenshot-selfcheck.webp" width="800"></p>
<p align="center">macOS 14.6+ &nbsp;·&nbsp; Apple Silicon 与 Intel &nbsp;·&nbsp; 本地优先</p>
<p align="center">🩺 <strong>Network Check 网络检查</strong> — 检查 Mac、局域网与互联网连接<br>📡 <strong>Wi-Fi 分析</strong> — 查看附近网络、信道使用、信号与安全性<br>🔒 <strong>本地优先</strong> — Wi-Fi 扫描记录保留在 Mac 上；不收集使用遥测</p>
<p align="center"><sub>本仓库提供免费的 WiFi Lens 开源版，用于实时本地分析、网络排障、开发和社区贡献。</sub></p>

---

<p align="center">
  <a href="README.md">🇺🇸 English</a> · <a href="README.de.md">🇩🇪 Deutsch</a> · <a href="README.es-ES.md">🇪🇸 Español</a> · <a href="README.fr.md">🇫🇷 Français</a> · 🇨🇳 简体中文 · <a href="README.ja.md">🇯🇵 日本語</a> · <a href="README.zh-Hant.md">🇭🇰 繁體中文</a>
</p>

<p align="center">
  <a href="#核心能力">核心能力</a> · <a href="#为什么选择-wifi-lens-pro">为什么选择 WiFi Lens Pro</a> · <a href="#版本">版本</a> · <a href="#ai--mcp-集成">AI / MCP</a> · <a href="#开源版">开源版</a> · <a href="#隐私">隐私</a> · <a href="#获取-wifi-lens">获取 WiFi Lens</a> · <a href="#开发">开发</a> · <a href="#贡献">贡献</a> · <a href="#许可证">许可证</a>
</p>

---

## 核心能力
WiFi Lens 提供实时工具，帮助你了解附近网络、信道使用情况和 Mac 的连接状态。

### 排查连接问题

当你需要排查连接问题时，可以运行 **Network Check**，检查从 Mac、局域网到互联网的连接路径。它会检查网络路径、网关可达性、DNS 解析、HTTP/HTTPS 访问、可选的 IPv6 连通性以及已配置的代理路由。结果按 **This Mac**、**LAN** 和 **Internet** 分组，帮助你判断问题可能出在哪一段。

| 能力 | 用途 |
|------|------|
| 📡 Wi-Fi 扫描 | 扫描 2.4、5 和 6 GHz 频段的附近网络 |
| 📊 频谱与信道质量 | 查看占用情况、拥堵评分和区域信道推荐 |
| 🔍 网络详情 | 查看 PHY 代际、信道宽度、802.11k/r/v、WPA3 和连接信息 |
| 🚶 漫游与热力图 | 验证 AP 切换并比较各频段占用情况 |
| 🩺 Network Self-Check | 检查连接、DNS、HTTPS、IPv6 和已配置的代理 |
| 📻 AP Radar（预览） | 追踪选定 AP，并提供基于 RSSI 的指引和可选音频反馈 |
| 🤖 MCP 与导出 | 连接本地 AI 工具，并将图表保存为 PNG 或 CSV |
| 🔒 本地优先隐私 | 扫描数据保留在 Mac 上，不收集使用遥测 |

<p align="center"><img alt="WiFi Lens 概览界面，展示附近 Wi-Fi 信息、信号、信道质量和信道建议" src="assets/screenshot-hero.webp" width="800"></p>

---

## 为什么选择 WiFi Lens Pro

WiFi Lens Pro 在实时 Wi-Fi 分析基础上增加历史与后续调查能力，帮助你理解反复出现的问题、比较一段时间内的观测结果，并在需要时持续观测。

| 工作流 | WiFi Lens Pro 提供的能力 |
|--------|--------------------------|
| 快速查看状态 | 从菜单栏查看当前连接信息 |
| 评估网络可靠性 | 查看所选时段内观测到的网络体验 |
| 与历史基准比较 | 将已保存的网关延迟测量值与兼容的历史基准比较 |
| 调查已记录的问题 | 查看已保存的问题记录、相关证据和后续观测 |
| 应用关闭时继续观测 | 可选的后台观测，默认关闭；Mac 进入睡眠后会暂停 |

Pro 将实时分析与历史视图结合，帮助你评估观测到的网络可靠性，并调查已记录的问题。此外还提供面向运营商场景的 Wi-Fi Calling Test。

<table>
<tr>
<td width="50%" align="center"><img alt="Network Experience 的可靠性评估与观测覆盖情况" src="assets/screenshot-network-experience.webp" width="100%"><sub>Network Experience</sub></td>
<td width="50%" align="center"><img alt="Historical Baseline 中网关延迟与历史测量值的比较" src="assets/screenshot-historical-baseline.webp" width="100%"><sub>Historical Baseline</sub></td>
</tr>
<tr>
<td colspan="2" align="center"><img alt="Problem History 展示已记录的问题及其支持证据" src="assets/screenshot-problem-history.webp" width="80%"><sub>Problem History</sub></td>
</tr>
</table>

### 从实时分析到历史上下文

遇到偶发问题时，Network Experience 可帮助你评估一段时间内观测到的情况。Problem History 将已记录的问题及其证据汇总，方便后续调查。

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>获取 WiFi Lens Pro →</strong></a>
</p>

---

## 版本

### WiFi Lens Pro
WiFi Lens Pro 可通过 [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8) 一次性购买。它增加了菜单栏状态、Network Experience、Problem History、频谱录制、可选的后台观测，以及面向运营商场景的 Wi-Fi Calling Test。Historical Baseline 是 Network Experience 中的一个视图。

### 开源版

WiFi Lens OSS 免费且开源。你可以通过 [GitHub Releases](https://github.com/ShiinaLabs/wifi-lens/releases/latest)、Homebrew 或源代码获取实时 Wi-Fi 分析和本地网络诊断。

| 能力 | WiFi Lens Pro | 开源版 |
|------|---------------|--------|
| 实时 Wi-Fi 分析 | ✅ | ✅ |
| 网络诊断 | ✅ | ✅ |
| 信道推荐 | ✅ | ✅ |
| MCP 集成 | ✅ | ✅ |
| 菜单栏状态 | ✅ | — |
| Network Experience 与 Historical Baseline | ✅ | — |
| Problem History | ✅ | — |
| 频谱录制 | ✅ | — |
| 可选的后台观测 | ✅ | — |
| Wi-Fi Calling Test | ✅ | — |

两个版本都在 Mac 上处理 Wi-Fi 扫描数据。Pro 增加了历史分析、频谱录制、可选后台观测和 Wi-Fi Calling Test。

---

## AI / MCP 集成


WiFi Lens 提供可选的本地 MCP 服务器。启用后，兼容客户端可以从这台 Mac 请求实时 Wi-Fi 扫描数据。可在 Codex Desktop 或 Claude Desktop 等 MCP 客户端中进行配置。

```json
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840"
    }
  }
}
```

手动配置时，请使用客户端要求的格式：

```toml
# Codex：~/.codex/config.toml
[mcp_servers.wifi-lens]
url = "http://127.0.0.1:19840/"
```

```json
// Claude Desktop 及其他基于 JSON 的客户端
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840/"
    }
  }
}
```

连接后，你可以问 AI 助手“附近哪些信道比较拥堵？”或“附近哪些网络支持 WPA3？”。MCP 服务器仅在 `127.0.0.1` 上监听；连接的客户端或模型服务可能按其自身政策和配置处理收到的数据。

更多示例请参考 [AI 工作流指南](https://wifi-lens.shiinalabs.com/zh-Hans/ai-mcp/?utm_source=github&utm_medium=readme&utm_campaign=github_readme)。

---

## 开源版
WiFi Lens OSS 免费且开源，可用于本地实时分析、开发、查看源码和参与社区贡献。

- **GitHub Releases** — [下载最新版本](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
- **Homebrew** — `brew tap ShiinaLabs/apps && brew install --cask ShiinaLabs/apps/wifi-lens`
- **源码与文档** — 浏览本仓库和[架构文档](docs/)

<details>
<summary>开源版功能</summary>

| 能力 | 说明 | 状态 |
|------|------|------|
| 📡 Wi-Fi 扫描 | 跨 2.4 / 5 / 6 GHz 频段的实时扫描 | 稳定 |
| 📊 频谱视图 | 高斯曲线展示信道占用 | 稳定 |
| 🎯 信道质量 | 拥堵评分与区域推荐 | 稳定 |
| 🔍 网络详情 | PHY 代际、信道宽度、802.11k/r/v、WPA3 | 稳定 |
| 📶 连接信息 | IP、网关、DNS、MAC、发送速率和安全摘要 | 稳定 |
| 🚶 漫游测试 | AP 切换监控与会话保存/加载 | 稳定 |
| 🗺️ 信道热力图 | 各频段占用热力图 | 稳定 |
| 🎧 BLE 扫描器 | Bluetooth LE 设备发现、RSSI 分析和追踪 | 稳定 |
| 🎨 智能着色 | 基于 SSID 的确定性颜色分配 | 稳定 |
| 🌐 MCP 服务器 | 用于 AI 工具集成的内嵌 HTTP API | 稳定 |
| 📤 导出 | 将图表保存为 PNG 或 CSV | 稳定 |
| 🔒 隐私优先 | 无遥测；扫描数据保留在 Mac 上 | 稳定 |
| ⬆️ 自动更新 | GitHub 版使用 Sparkle | 稳定 |
| 🌍 本地化 | 英语、法语、德语、日语、俄语、西班牙语、简体中文和繁体中文 | 稳定 |
| 🩺 Network Self-Check | 检查连接、DNS、HTTPS、IPv6 和已配置的代理 | 稳定 |
| 📻 AP Radar | 追踪选定 AP，并提供音频脉冲反馈 | 预览 |
| 📜 开源许可证 | 在“设置 → 关于”中查看已包含的组件、许可证和声明 | 稳定 |

</details>

[![Downloads](https://img.shields.io/github/downloads/ShiinaLabs/wifi-lens/WiFiLens.dmg?label=Downloads&displayAssetName=false&color=2563eb)](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
[![Latest release](https://img.shields.io/github/v/release/ShiinaLabs/wifi-lens?label=Latest&color=2563eb)](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

---

## 隐私
WiFi Lens 不会将 Wi-Fi 扫描记录上传至应用服务，也不收集使用分析或遥测数据。

- **定位服务：** macOS 需要此权限才能提供 Wi-Fi SSID 名称。WiFi Lens 不读取 GPS 位置。
- **区域检测：** 在设备上使用系统语言设置、硬件上报的信道列表和附近 AP 的国家代码。
- **Network Self-Check：** 会向公共目标发送诊断探测，并在适用时探测已配置的代理。诊断证据保存在本地。
- **MCP 服务器：** 可选功能，仅绑定到 `127.0.0.1`。连接的客户端和模型服务会根据各自政策与配置处理收到的数据。
- **后台观测：** Pro 中的可选功能，默认关闭。观测数据保存在本地；Mac 进入睡眠后会暂停采集。
- **更新检查：** GitHub 版在你请求检查更新或启用自动检查时联系 GitHub。

📋 [安全策略](SECURITY.md) · 📝 [更新日志](https://github.com/ShiinaLabs/wifi-lens/releases) · ❓ [常见问题](https://wifi-lens.shiinalabs.com/zh-Hans/faq/?utm_source=github&utm_medium=readme&utm_campaign=github_readme) · 🌐 [完整隐私政策](https://wifi-lens.shiinalabs.com/zh-Hans/privacy/?utm_source=github&utm_medium=readme&utm_campaign=github_readme)

---

## 获取 WiFi Lens

需要 **macOS 14.6（Sonoma）或更高版本**。支持 Intel 和 Apple Silicon。6 GHz 扫描需要 Wi-Fi 6E/7 硬件。

### WiFi Lens Pro
WiFi Lens Pro 在实时 Wi-Fi 分析基础上增加菜单栏状态、Network Experience、Problem History、频谱录制、可选后台观测，以及面向运营商场景的 Wi-Fi Calling Test。前往 [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8) 获取。

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="在 Mac App Store 下载" width="190"></a>
</p>

### 开源版

适合 GitHub 分发和社区开发：

- [GitHub Releases](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
- Homebrew：`brew tap ShiinaLabs/apps && brew install --cask ShiinaLabs/apps/wifi-lens`
- 源码：本仓库

> [!IMPORTANT]
> 在 macOS 14.6+ 上，必须启用**定位服务**，应用才能读取 Wi-Fi SSID 名称。请前往**系统设置 → 隐私与安全性 → 定位服务**，并在系统提示时启用 WiFi Lens。

---

## 开发

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

架构文档位于 [docs/](docs/)。

---

## 贡献

欢迎提交问题报告、功能想法和改进建议。请参阅[贡献指南](.github/CONTRIBUTING.md)，了解环境设置、PR 约定和本地化要求。

欢迎加入 **[Rabbit Hole](https://discord.gg/gH6sTCYaJ7)**，这里是 WiFi Lens 和其他项目的小型社区。

**联系：** [X 上的 @WiFiLens](https://x.com/WiFiLens) · [contacts@shiinalabs.com](mailto:contacts@shiinalabs.com)

---

## 许可证

本项目 Fork 自 [tiny-wifi-analyzer](https://github.com/nolze/tiny-wifi-analyzer)。MAC 厂商数据来自 [IEEE Registration Authority](https://standards.ieee.org/products-programs/regauth/)，详见[第三方声明](docs/THIRD-PARTY-NOTICES.md)。

Apache License 2.0 © 2020 nolze, 2026 ShiinaLabs — 详见 [LICENSE](LICENSE)。
