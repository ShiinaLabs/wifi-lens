<h1 align="center">WiFi Lens Pro</h1>

<p align="center"><strong>看清 Wi-Fi 正在发生什么。</strong></p>

<p align="center">
  原生 macOS Wi-Fi 分析与网络诊断应用。<br>
  实时排查连接问题，按需持续观测，并利用历史证据调查反复出现的异常。
</p>

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="在 Mac App Store 获取 WiFi Lens Pro" width="190"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.6%2B-555?style=flat" alt="macOS 14.6+">
  <img src="https://img.shields.io/badge/Chip-Intel%20%7C%20Apple%20Silicon-555?style=flat" alt="Intel 与 Apple Silicon">
  <img src="https://img.shields.io/badge/Telemetry-None-555?style=flat" alt="无遥测">
</p>

<p align="center">
  <a href="https://wifi-lens.shiinalabs.com/zh-Hans/?utm_source=github&amp;utm_medium=readme&amp;utm_campaign=github_readme">官方网站</a>
  &nbsp;·&nbsp; 一次性购买
</p>

<p align="center">
  <img src="assets/screenshot-network-experience.webp" alt="WiFi Lens Pro — Network Experience 网络可靠性分析" width="880">
</p>

<p align="center"><sub>Network Experience · 根据实际观测评估网络可靠性</sub></p>

---

<p align="center">
  <a href="README.md">🇺🇸 English</a> ·
  <a href="README.de.md">🇩🇪 Deutsch</a> ·
  <a href="README.es-ES.md">🇪🇸 Español</a> ·
  <a href="README.fr.md">🇫🇷 Français</a> ·
  <strong>🇨🇳 简体中文</strong> ·
  <a href="README.ja.md">🇯🇵 日本語</a> ·
  <a href="README.zh-Hant.md">🇭🇰 繁體中文</a>
</p>

## 网络问题，不会等你准备好

Wi-Fi 偶尔断连、延迟突然升高、连接过一会儿又恢复。等你想排查时，问题可能已经消失。

**WiFi Lens Pro 不只帮助你检查现在的网络，还会在需要时持续观测，让过去的问题有迹可循。**

| **🔍 01 · 实时排查** | **📡 02 · 持续观测** | **🗂️ 03 · 历史调查** |
|:---|:---|:---|
| 了解当前连接与无线环境 | 在需要时持续收集观测结果 | 回看可靠性、历史基准与问题证据 |
| [查看网络诊断](#01--实时排查) | [了解持续观测](#02--持续观测) | [调查历史问题](#03--历史调查) |

---

## 01 · 实时排查

### 先确认问题在哪里

使用 **网络自检（Network Check）**，从 **This Mac、LAN、Internet** 三个阶段检查连接路径。你可以查看网关、DNS、HTTP/HTTPS、可选 IPv6 和代理相关检查结果，区分已确认的问题与证据不足的情况。

当问题与无线环境有关时，**Wi-Fi 分析**可以展示附近 2.4 / 5 / 6 GHz 网络、信号强度、信道使用与拥堵、网络安全信息及区域信道建议。

<table>
<tr>
<td width="50%" align="center">
  <img src="assets/screenshot-selfcheck.webp" alt="Network Check 网络自检界面" width="100%">
  <sub>Network Check · 逐阶段检查连接</sub>
</td>
<td width="50%" align="center">
  <img src="assets/screenshot-hero.webp" alt="Wi-Fi 实时分析与信道建议" width="100%">
  <sub>Wi-Fi 分析 · 查看附近的无线环境</sub>
</td>
</tr>
</table>

这两项实时能力也包含在免费开源版中。Pro 在此基础上提供持续观测与历史调查工作流。

---

## 02 · 持续观测

### 不必守在屏幕前等待问题再次出现

有些异常只持续几秒。与其不断打开扫描器，不如在需要时持续观测并保存相应记录。

| 能力 | 可以做什么 |
|---|---|
| **菜单栏状态** | 查看当前连接、网关状态、近期变化和简短趋势。 |
| **持续观测（Continuous Observation）** | 可选地在 Pro 应用关闭后继续采集受支持的网络观测结果；默认关闭，Mac 睡眠时暂停。 |
| **频谱录制（Spectrum → Recording）** | 录制选定 AP 的信号变化，之后重新加载并查看记录。 |

> **素材占位｜菜单栏状态与持续观测设置**  
> （待补充实际界面截图）

---

## 03 · 历史调查

### 问题过去了，证据仍然有价值

Pro 的历史能力集中在 **Network Experience** 和 **Problem History**，不是让用户在一堆图表里自行猜测。

**网络可靠性（Network Experience → Reliability）**

选择网络与时间范围，查看基于现有证据形成的可靠性评估、发现的问题及其发生时间。观测覆盖不足的部分不会被当作“网络正常”。

**历史基准（Network Experience → Baseline）**

把已保存的网关延迟测量与相容的历史基准比较。这里展示的是有依据的相对变化，不会仅凭一次偏移断言网络已经故障。

**问题记录（Problem History）**

查看已经保存的问题记录、支持证据和后续观测。对于有依据的发现，可以查看建议的下一步检查并进入相应工具；检查仍由用户主动执行。

<table>
<tr>
<td width="50%" align="center">
  <img src="assets/screenshot-historical-baseline.webp" alt="Historical Baseline 网关延迟历史基准对比" width="100%">
  <sub>Historical Baseline · 与符合条件的历史基准比较</sub>
</td>
<td width="50%" align="center">
  <img src="assets/screenshot-problem-history.webp" alt="Problem History 问题记录与证据" width="100%">
  <sub>Problem History · 回顾问题记录与证据</sub>
</td>
</tr>
</table>

<p align="center"><strong>从现在的检查，到长期观测，再到事后调查。</strong></p>
<p align="center">这才是 WiFi Lens Pro 的完整体验。</p>
<p align="center"><a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>获取 WiFi Lens Pro</strong></a></p>

---

## 更多实用工具

除了上述工作流，你还可以使用漫游测试、信道热力图、AP Radar、Bluetooth LE 扫描、图表导出和本地 MCP 集成。

WiFi Lens Pro 另提供面向运营商场景的 **Wi-Fi Calling Test**，支持运营商预设或自定义 MCC/MNC。

## Pro 与开源版

开源版是免费的实时 Wi-Fi 分析与本地网络诊断工具。**WiFi Lens Pro** 则在此基础上增加持续观测、历史分析和问题调查能力。

| 功能 | Pro | 开源版 |
|---|:---:|:---:|
| Wi-Fi 分析、信道质量与建议 | ✓ | ✓ |
| 网络自检（Network Check） | ✓ | ✓ |
| 漫游测试、AP Radar、信道热力图 | ✓ | ✓ |
| 本地 MCP、图表导出 | ✓ | ✓ |
| 菜单栏状态与持续观测 | ✓ | — |
| 网络可靠性与历史基准 | ✓ | — |
| 问题记录与历史调查 | ✓ | — |
| 频谱录制、Wi-Fi Calling Test | ✓ | — |

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8">获取 WiFi Lens Pro</a>
  &nbsp;·&nbsp;
  <a href="https://github.com/ShiinaLabs/wifi-lens/releases/latest">下载免费开源版</a>
</p>

---

## 隐私与数据

WiFi Lens 在本机处理 Wi-Fi 扫描数据，不需要账号，不使用云端同步，也不收集使用遥测。

- **网络自检：** 会连接公共诊断目标，并在适用时检查已配置的代理。
- **持续观测：** 默认关闭；观测数据保存在本机，Mac 睡眠时暂停。
- **本地 MCP：** 服务器仅绑定 `127.0.0.1`；如果 AI 客户端连接到外部服务，应另行确认该客户端的数据处理方式。
- **系统权限：** macOS 要求读取 Wi-Fi SSID 的应用获得定位权限；WiFi Lens 不读取 GPS 位置。

详见 [完整隐私政策](https://wifi-lens.shiinalabs.com/zh-Hans/privacy/?utm_source=github&utm_medium=readme&utm_campaign=github_readme)。

## 获取 WiFi Lens

**WiFi Lens Pro**：通过 [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8) 一次性购买。支持 macOS 14.6+、Intel 和 Apple Silicon；6 GHz 扫描需要 Wi-Fi 6E/7 硬件。

**WiFi Lens 开源版**：[GitHub Releases](https://github.com/ShiinaLabs/wifi-lens/releases/latest) 或 Homebrew：

<p>
  <a href="https://github.com/ShiinaLabs/wifi-lens/releases/latest"><img src="https://img.shields.io/github/v/release/ShiinaLabs/wifi-lens?label=Latest&amp;color=2563eb" alt="最新版本"></a>
  <a href="https://github.com/ShiinaLabs/wifi-lens/releases/latest"><img src="https://img.shields.io/github/downloads/ShiinaLabs/wifi-lens/WiFiLens.dmg?label=Downloads&amp;displayAssetName=false&amp;color=2563eb" alt="下载量"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue" alt="Apache 2.0 许可证"></a>
</p>

```sh
brew tap ShiinaLabs/apps
brew install --cask ShiinaLabs/apps/wifi-lens
```

<details>
<summary><strong>AI / MCP：查看集成与配置</strong></summary>

WiFi Lens 提供可选的本地 MCP 服务器。启用后，兼容的 AI 工具可以读取实时 Wi-Fi 扫描数据，例如查看附近的信道占用与网络安全信息。

服务器仅绑定到 `127.0.0.1`。可使用如下 MCP 客户端配置：

```json
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840/"
    }
  }
}
```

Codex 配置：

```toml
[mcp_servers.wifi-lens]
url = "http://127.0.0.1:19840/"
```

更多示例见 [AI 工作流指南](https://wifi-lens.shiinalabs.com/zh-Hans/ai-mcp/?utm_source=github&utm_medium=readme&utm_campaign=github_readme)。

</details>

<details>
<summary><strong>开发与贡献</strong></summary>

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

架构文档位于 [docs/](docs/)。欢迎查看[贡献指南](.github/CONTRIBUTING.md)，提交问题报告、功能建议和 PR。

</details>

## 社区与许可

加入 [Rabbit Hole](https://discord.gg/gH6sTCYaJ7) 讨论 WiFi Lens 与其他项目。

**联系：** [@WiFiLens](https://x.com/WiFiLens) · [contacts@shiinalabs.com](mailto:contacts@shiinalabs.com)

项目 Fork 自 [tiny-wifi-analyzer](https://github.com/nolze/tiny-wifi-analyzer)。MAC 厂商数据来自 [IEEE Registration Authority](https://standards.ieee.org/products-programs/regauth/)，详见[第三方声明](docs/THIRD-PARTY-NOTICES.md)。

Apache License 2.0 © 2020 nolze, 2026 ShiinaLabs — 详见 [LICENSE](LICENSE)。
