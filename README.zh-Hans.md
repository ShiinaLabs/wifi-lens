# WiFi Lens

**完整的 Mac Wi-Fi 故障排查工作流。**

WiFi Lens Pro 将实时 Wi-Fi 分析、网络诊断、持续监控、Timeline 历史、Statistics 和 Insights 汇聚在一款原生 macOS 应用中。

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>获取 WiFi Lens Pro</strong></a>
  &nbsp;·&nbsp;
  <a href="https://wifi-lens.shiinalabs.com">官方网站</a>
</p>

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="在 Mac App Store 下载" width="190"></a>
</p>

<p align="center"><img alt="WiFi Lens Pro 在 macOS 上展示 Event Timeline 历史记录" src="assets/screenshot-timeline.webp" width="800"></p>

<p align="center">macOS 14+ &nbsp;·&nbsp; Apple Silicon 与 Intel &nbsp;·&nbsp; 无遥测</p>

<p align="center">
  🔒 <strong>本地优先隐私</strong> — 无账号、无云端、无遥测<br>
  🩺 <strong>基于证据的诊断</strong> — 可解释的路径、DNS、HTTPS 与代理检查<br>
  🤖 <strong>面向 AI 工作流的 MCP</strong> — 让兼容客户端读取 Mac 上的实时 Wi-Fi 数据
</p>

<p align="center"><sub>本仓库包含 WiFi Lens 开源版，用于实时本地分析、开发、源码查看和社区贡献。</sub></p>

---

<p align="center">
  <a href="README.md">🇺🇸 English</a> · <a href="README.de.md">🇩🇪 Deutsch</a> · <a href="README.es-ES.md">🇪🇸 Español</a> · <a href="README.fr.md">🇫🇷 Français</a> · 🇨🇳 简体中文 · <a href="README.ja.md">🇯🇵 日本語</a>
</p>
<p align="center">
  <a href="#为什么选择-wifi-lens-pro">为什么选择 WiFi Lens Pro</a> · <a href="#核心能力">核心能力</a> · <a href="#版本">版本</a> · <a href="#ai--mcp-集成">AI / MCP</a> · <a href="#开源版">开源版</a> · <a href="#隐私">隐私</a> · <a href="#获取-wifi-lens">获取 WiFi Lens</a> · <a href="#开发">开发</a> · <a href="#贡献">贡献</a> · <a href="#许可证">许可证</a>
</p>

---

## 为什么选择 WiFi Lens Pro

实时诊断告诉你现在发生了什么。WiFi Lens Pro 则在问题具有偶发性时继续记录上下文：持续观察、记录事件、保存历史，并帮助你在事后调查发生过什么。

| 工作流 | WiFi Lens Pro 提供的能力 |
|--------|--------------------------|
| 立即诊断 | 实时 Wi-Fi 分析、信道分析和网络诊断 |
| 持续观察 | 菜单栏监控和连续观察 |
| 捕捉偶发问题 | Timeline 与频谱录制 |
| 回看发生过什么 | 历史事件和连接变化 |
| 找到规律 | 跨记录时段的 Statistics |
| 理解证据 | 基于记录观察结果的 Insights |

**WiFi Lens Pro 是完整版本。** 它把实时分析器与监控、历史和调查连接起来，而不是把它们当作互不相关的工具。

<table>
<tr>
<td width="50%" align="center"><img alt="网络自检诊断界面" src="assets/screenshot-selfcheck.webp" width="100%"><sub>Network Self-Check</sub></td>
<td width="50%" align="center"><img alt="展示连接历史的 Event Timeline" src="assets/screenshot-timeline.webp" width="100%"><sub>Event Timeline（Pro）</sub></td>
</tr>
</table>

### 现在诊断 → 之后调查

Wi-Fi 问题往往在你来得及检查前就消失。WiFi Lens Pro 会保留断连、漫游或信号变化周围的证据，让你稍后回看事件和当时的网络状态。

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>获取 WiFi Lens Pro →</strong></a>
</p>

---

## 核心能力

WiFi Lens 将理解本地 Wi-Fi 环境所需的基础工具整合在一款原生 Mac 应用中。

| 能力 | 用途 |
|------|------|
| 📡 Wi-Fi 扫描 | 扫描 2.4、5 和 6 GHz 频段的附近网络 |
| 📊 频谱与信道质量 | 查看占用情况、拥堵评分和区域信道推荐 |
| 🔍 网络详情 | 查看 PHY 代际、信道宽度、802.11k/r/v、WPA3 和连接信息 |
| 🚶 漫游与热力图 | 验证 AP 切换并比较各频段占用情况 |
| 🩺 Network Self-Check（预览） | 检查路径、DNS、HTTPS 和已配置代理的可达性 |
| 📻 AP Radar（预览） | 追踪选定 AP，并提供基于 RSSI 的指引和可选音频反馈 |
| 🤖 MCP 与导出 | 连接本地 AI 工具，并将图表保存为 PNG 或 CSV |
| 🔒 本地优先隐私 | 扫描数据保留在 Mac 上，不收集使用遥测 |

---

## 版本

### WiFi Lens Pro

**WiFi Lens Pro 是完整版本。** 它通过 [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8) 一次性购买，适合需要持续观察、录制、历史记录和调查的用户。

### 开源版

开源版为偏好 GitHub 分发、希望查看源码并参与贡献的用户提供了相当完整的实时分析能力。可从 [GitHub Releases](https://github.com/SHIINASAMA/wifi-lens/releases/latest) 获取。

| 能力 | WiFi Lens Pro | 开源版 |
|------|---------------|--------|
| 实时 Wi-Fi 分析 | ✅ | ✅ |
| 网络诊断 | ✅ | ✅ |
| 信道推荐 | ✅ | ✅ |
| 持续监控 | ✅ | — |
| 事件历史 | ✅ | — |
| 历史统计 | ✅ | — |
| Insights | ✅ | — |
| 频谱录制 | ✅ | — |
| 菜单栏监控 | ✅ | — |

两个版本都以本地处理为基础。区别在于实时分析器之外的工作流：Pro 增加了持续观察、保存上下文和调查长期问题所需的信息。

---

## AI / MCP 集成

WiFi Lens 内置 MCP 服务器，兼容的 AI 助手可以读取本地 Wi-Fi 数据。在设置中启用后，选择“复制 AI 设置提示词”，并将提示词粘贴到 Codex Desktop、Claude Desktop 等兼容 MCP 的桌面客户端。

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

连接后，你可以问 AI 助手“附近哪些信道比较拥堵？”或“附近哪些网络支持 WPA3？”。服务器仅绑定到 `127.0.0.1`，除非你主动将其路由到其他位置，否则数据不会离开电脑。

更多示例请参考 [AI 工作流指南](https://wifi-lens.shiinalabs.com/ai-mcp/)。

---

## 开源版

开源版适合本地分析、开发、查看源码和社区贡献。

- **GitHub Releases** — [下载最新版本](https://github.com/SHIINASAMA/wifi-lens/releases/latest)
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
| 🌍 本地化 | 英语、德语、西班牙语、日语、中文 | 稳定 |
| 🩺 Network Self-Check | 一键进行路径、DNS、HTTPS 和代理诊断 | 预览 |
| 📻 AP Radar | 追踪选定 AP，并提供音频脉冲反馈 | 预览 |

</details>

[![Downloads](https://img.shields.io/github/downloads/SHIINASAMA/wifi-lens/WiFiLens.dmg?label=Downloads&displayAssetName=false&color=2563eb)](https://github.com/SHIINASAMA/wifi-lens/releases/latest)
[![Latest release](https://img.shields.io/github/v/release/SHIINASAMA/wifi-lens?label=Latest&color=2563eb)](https://github.com/SHIINASAMA/wifi-lens/releases/latest)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

---

## 隐私

WiFi Lens 不收集使用分析、崩溃遥测或 Wi-Fi 扫描数据。

- **定位服务：** macOS 需要此权限才能提供 Wi-Fi SSID 名称。WiFi Lens 不读取 GPS 位置。
- **区域检测：** 在设备上使用系统语言设置、硬件上报的信道列表和附近 AP 的国家代码。
- **Network Self-Check：** 解析公共端点（`www.apple.com`、`www.msftconnecttest.com`），也可能测试已配置代理端点的可达性。
- **MCP 服务器：** 仅绑定 `127.0.0.1`。启用后本地工具才能访问数据。
- **更新检查：** GitHub 版在你请求检查更新或启用自动检查时联系 GitHub。

📋 [安全策略](SECURITY.md) · 📝 [更新日志](https://github.com/SHIINASAMA/wifi-lens/releases) · ❓ [常见问题](https://wifi-lens.shiinalabs.com/faq/) · 🌐 [完整隐私政策](https://wifi-lens.shiinalabs.com/privacy/)

---

## 获取 WiFi Lens

需要 **macOS 14（Sonoma）或更高版本**。支持 Intel 和 Apple Silicon。6 GHz 扫描需要 Wi-Fi 6E/7 硬件。

### WiFi Lens Pro

适合持续监控、录制、查看历史和调查问题的完整版本。前往 [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8) 获取。

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="在 Mac App Store 下载" width="190"></a>
</p>

### 开源版

适合 GitHub 分发和社区开发：

- [GitHub Releases](https://github.com/SHIINASAMA/wifi-lens/releases/latest)
- Homebrew：`brew tap ShiinaLabs/apps && brew install --cask ShiinaLabs/apps/wifi-lens`
- 源码：本仓库

> [!IMPORTANT]
> 在 macOS 14+ 上，必须启用**定位服务**，应用才能读取 Wi-Fi SSID 名称。请前往**系统设置 → 隐私与安全性 → 定位服务**，并在系统提示时启用 WiFi Lens。

---

## 开发

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
  -skipPackageUpdates test -only-testing:WiFiLensTests
```

架构文档位于 [docs/](docs/)。

---

## 贡献

欢迎提交问题报告、功能想法和改进建议。请参阅[贡献指南](.github/CONTRIBUTING.md)，了解环境设置、PR 约定和本地化要求。

欢迎加入 **[Rabbit Hole](https://discord.gg/gH6sTCYaJ7)**，这里是 WiFi Lens 和其他项目的小型社区。

**联系：** [X 上的 @WiFiLens](https://x.com/WiFiLens) · [wifi-lens@shiinalabs.com](mailto:wifi-lens@shiinalabs.com)

---

## 许可证

本项目 Fork 自 [tiny-wifi-analyzer](https://github.com/nolze/tiny-wifi-analyzer)。MAC 厂商数据来自 [IEEE Registration Authority](https://standards.ieee.org/products-programs/regauth/)，详见[第三方声明](docs/THIRD-PARTY-NOTICES.md)。

Apache License 2.0 © 2020 nolze, 2026 SHIINASAMA — 详见 [LICENSE](LICENSE)。
