# WiFi Lens Pro

**看清 Wi-Fi 正在发生什么。**

WiFi Lens Pro 是一款原生 macOS Wi-Fi 分析与网络诊断应用。检查当前连接，按需持续观测网络状态，并结合历史证据调查间歇性问题。

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="在 Mac App Store 获取 WiFi Lens Pro" width="190"></a>
</p>

<p align="center"><a href="https://wifi-lens.shiinalabs.com/zh-Hans/?utm_source=github&amp;utm_medium=readme&amp;utm_campaign=github_readme">官方网站</a></p>

> **主视觉占位｜Network Experience → Reliability**  
> 展示 Pro 对所选网络的可靠性判断、观测范围和需要关注的问题，而不是通用 Wi-Fi 扫描界面。

<p align="center"><sub>macOS 14.6+ · Intel 与 Apple Silicon · 一次性购买</sub></p>

---

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.es-ES.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  简体中文 ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.zh-Hant.md">繁體中文</a>
</p>

<p align="center">
  <a href="#实时排查">实时排查</a> ·
  <a href="#持续观测">持续观测</a> ·
  <a href="#历史调查">历史调查</a> ·
  <a href="#pro-与开源版">Pro 与开源版</a>
</p>

---

## 网络问题，不会等你准备好

有些问题很容易重现：信道拥堵、信号偏弱，打开 Wi-Fi 分析器就能开始排查。

更麻烦的是另一类问题：网络突然中断，过一会儿又恢复；某一天延迟明显升高，却很难确定从什么时候开始；偶尔出现异常，但每次准备检查时都已经正常。

**一次实时检测只能告诉你眼前发生了什么。WiFi Lens Pro 还可以保留观测结果，让你有机会在事后继续调查。**

这就是 Pro 的完整工作流：

**实时排查 → 持续观测 → 历史调查**

## 实时排查

**先弄清楚当前连接和无线环境。**

### 网络自检（Network Check）

当连接行为不符合预期时，运行网络自检，按 **This Mac、LAN、Internet** 查看网络路径上的检查结果，包括网关、DNS、HTTP/HTTPS、可选的 IPv6 和已配置的代理。

你可以看到哪些检查成功、失败或没有足够证据，而不需要从零开始组合多个命令行工具。

> **截图占位｜Network Check**  
> 展示分阶段的真实检测结果，突出用户可以从哪里开始排查。

### Wi-Fi 分析

WiFi Lens Pro 也提供实时 Wi-Fi 分析能力：扫描附近 2.4 / 5 / 6 GHz 网络，查看信号、信道、拥堵情况、安全配置和区域信道建议。

当你怀疑问题出在无线环境或 AP 切换时，可以进一步使用漫游测试、信道热力图和 AP Radar。

这些实时工具在 **WiFi Lens Pro 与开源版中均可使用**。

## 持续观测

**问题偶尔发生时，最重要的是不必一直守着屏幕。**

### 菜单栏状态

随时查看当前连接、网关状态、近期变化和简短趋势，需要深入调查时再打开主窗口。

### 持续观测（Continuous Observation）

需要更长时间的观察时，可以在设置中启用持续观测。它可在 Pro 应用关闭后继续采集受支持的网络观察结果；**默认关闭**，Mac 睡眠时暂停。

### 频谱录制（Spectrum → Recording）

需要记录无线信号变化时，可以选定 AP 进行频谱录制，保存后再回看信号历史。

> **素材占位｜持续观测**  
> 展示菜单栏状态和持续观测的实际使用场景；不把后台代理状态或尚未提供的控制面板画成现有功能。

## 历史调查

**WiFi Lens Pro 的价值，在于问题发生后仍有证据可以调查。**

### 网络可靠性（Network Experience → Reliability）

选择一张已知网络和时间范围，查看 **Network Experience → Reliability** 的评估结果：哪些问题有观测证据、发生在什么时候，以及所选时段内有多少数据足以支持判断。

它不是凭空生成一个“网络健康分”，而是把观察到的影响与没有充分观测的数据区分开。

> **截图占位｜Network Experience → Reliability**  
> 以结论和问题列表为主，技术曲线与原始观测作为次级证据。

### 历史基准（Network Experience → Baseline）

在 **Network Experience** 中切换到 **Baseline**，比较已保存的网关延迟测量值与符合比较条件的历史基准。

它帮助你发现有依据的相对变化，但不会把一次延迟偏移直接当成整个 Wi-Fi 网络的故障结论。

> **截图占位｜Network Experience → Baseline**  
> 展示具体网关延迟测量与对应历史基准的比较。

### 问题记录（Problem History）

在 **Problem History** 中查看已保存的问题记录、支持证据和后续观测结果。

对于有依据的问题，页面可以提供下一步检查建议，帮助你打开相应的网络诊断或接口详情页面；**检查需要由用户手动执行**，并非自动诊断或自动修复。

> **截图占位｜Problem History**  
> 展示一个有真实证据的问题记录、建议检查方向，以及对应的后续观察。

当问题已经消失，保存的记录仍然可以成为下一次调查的起点。

---

## 其他实用工具

WiFi Lens Pro 同样包含实时 Wi-Fi 分析、网络自检、漫游测试、AP Radar、信道热力图、Bluetooth LE 扫描与本地 MCP 集成等能力。

Pro 还提供面向运营商场景的 **Wi-Fi Calling Test**，支持运营商预设或自定义 MCC/MNC。

这些工具服务于同一个目标：**让你更容易理解连接状态，并沿着已有证据继续排查。**

## Pro 与开源版

WiFi Lens Pro 提供完整的实时排查、持续观测与历史调查工作流。WiFi Lens 开源版（免费）提供实时 Wi-Fi 分析和本地网络诊断，也允许查看源码和参与开发。

| 能力 | WiFi Lens Pro | 开源版 |
|---|:---:|:---:|
| 实时 Wi-Fi 扫描、信道分析与推荐 | ✓ | ✓ |
| 网络自检（Network Check） | ✓ | ✓ |
| 漫游测试、AP Radar、信道热力图 | ✓ | ✓ |
| 本地 MCP 与导出 | ✓ | ✓ |
| 菜单栏状态 | ✓ | — |
| 持续观测（Continuous Observation） | ✓ | — |
| 网络体验分析（Network Experience：Reliability / Baseline） | ✓ | — |
| 问题记录与调查（Problem History） | ✓ | — |
| 频谱录制（Spectrum → Recording） | ✓ | — |
| Wi-Fi Calling Test | ✓ | — |

**如果你只需要分析当前 Wi-Fi，开源版就很有用；如果你需要持续观测并调查反复出现的问题，WiFi Lens Pro 提供了完整的工作流。**

[获取 WiFi Lens Pro](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8) · [下载开源版](https://github.com/ShiinaLabs/wifi-lens/releases/latest)

---

## AI / MCP 集成

WiFi Lens 内置可选的本地 MCP 服务器。启用后，兼容的 AI 客户端可以读取 Mac 上的实时 Wi-Fi 数据。

例如可以直接问：

> “附近哪些信道比较拥堵？”

> “附近哪些网络支持 WPA3？”

服务器仅绑定到 `127.0.0.1`。除非你主动将数据路由到其他服务，否则 Wi-Fi 数据不会通过 MCP 离开这台 Mac。

启用后，可以在 Codex Desktop、Claude Desktop 等兼容 MCP 的客户端中使用。

```json
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840"
    }
  }
}
```

Codex：

```toml
[mcp_servers.wifi-lens]
url = "http://127.0.0.1:19840/"
```

Claude Desktop：

```json
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840/"
    }
  }
}
```

更多示例请参考 [AI 工作流指南](https://wifi-lens.shiinalabs.com/zh-Hans/ai-mcp/?utm_source=github&utm_medium=readme&utm_campaign=github_readme)。

---

## 隐私优先

WiFi Lens 在 Mac 本地处理 Wi-Fi 数据，不要求账号，不使用云端同步，也不收集使用遥测。

- **Wi-Fi 扫描：** 扫描结果保留在 Mac 上。
- **网络自检（Network Check）：** 会向公共目标发送诊断请求，并在适用时检查已配置的代理；诊断结果保存在本地。
- **MCP：** 仅绑定 `127.0.0.1`，启用后本地客户端才能访问。
- **定位服务：** macOS 要求读取 Wi-Fi SSID 的应用获得此权限。WiFi Lens 不读取 GPS 位置。
- **区域检测：** 在设备上使用系统设置、硬件信道列表和附近 AP 的国家代码。
- **后台持续观测：** Pro 的观测数据保存在本地，Mac 进入睡眠后暂停采集。
- **更新检查：** GitHub 版在你请求检查更新或启用自动检查时联系 GitHub。

更多信息见 [完整隐私政策](https://wifi-lens.shiinalabs.com/zh-Hans/privacy/?utm_source=github&utm_medium=readme&utm_campaign=github_readme)。

---

## 获取 WiFi Lens Pro

需要 **macOS 14.6（Sonoma）或更高版本**，支持 Intel 和 Apple Silicon。6 GHz 扫描需要 Wi-Fi 6E/7 硬件。

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>在 Mac App Store 获取 WiFi Lens Pro →</strong></a>
</p>

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="在 Mac App Store 获取 WiFi Lens Pro" width="190"></a>
</p>

---

## 开源版

开源版适合本地实时分析、查看源码、开发和社区贡献。

- [GitHub Releases](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
- Homebrew：`brew tap ShiinaLabs/apps && brew install --cask ShiinaLabs/apps/wifi-lens`
- 源码与文档：本仓库和 [架构文档](docs/)

### 开源版功能

| 能力 | 说明 |
|---|---|
| 📡 Wi-Fi 扫描 | 跨 2.4 / 5 / 6 GHz 频段的实时扫描 |
| 📊 频谱视图 | 查看信道占用 |
| 🎯 信道质量 | 拥堵评分与区域推荐 |
| 🔍 网络详情 | PHY 代际、信道宽度、802.11k/r/v、WPA3 |
| 📶 连接信息 | IP、网关、DNS、MAC、发送速率和安全摘要 |
| 🚶 漫游测试 | AP 切换监控与会话保存/加载 |
| 🗺️ 信道热力图 | 各频段占用热力图 |
| 📻 AP Radar | 追踪选定 AP，并提供基于 RSSI 的反馈 |
| 🎧 BLE 扫描器 | Bluetooth LE 设备发现、RSSI 分析和追踪 |
| 🌐 MCP 服务器 | 用于 AI 工具集成的本地 HTTP API |
| 📤 导出 | 将图表保存为 PNG 或 CSV |
| 🔒 隐私优先 | 无使用遥测；扫描数据保留在 Mac 上 |
| ⬆️ 自动更新 | GitHub 版使用 Sparkle |
| 🩺 网络自检（Network Check） | 一键进行网络路径、DNS、HTTPS 和代理检查 |

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

欢迎加入 [Rabbit Hole](https://discord.gg/gH6sTCYaJ7)，这里是 WiFi Lens 和其他项目的小型社区。

**联系：** [X 上的 @WiFiLens](https://x.com/WiFiLens) · [contacts@shiinalabs.com](mailto:contacts@shiinalabs.com)

---

## 许可证

本项目 Fork 自 [tiny-wifi-analyzer](https://github.com/nolze/tiny-wifi-analyzer)。MAC 厂商数据来自 [IEEE Registration Authority](https://standards.ieee.org/products-programs/regauth/)，详见[第三方声明](docs/THIRD-PARTY-NOTICES.md)。

Apache License 2.0 © 2020 nolze, 2026 ShiinaLabs — 详见 [LICENSE](LICENSE)。
