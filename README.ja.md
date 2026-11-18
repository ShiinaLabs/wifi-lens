<h1 align="center">WiFi Lens Pro</h1>

<p align="center"><strong>Wi-Fiで何が起きているかを把握する。</strong></p>
<p align="center">Wi-Fi分析とネットワーク診断のためのmacOSネイティブアプリです。<br>接続の問題を診断し、必要に応じてネットワークを継続観測し、履歴の証拠から繰り返し発生する問題を調査できます。</p>
<p align="center"><a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="Mac App StoreでWiFi Lens Proを入手" width="190"></a></p>
<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.6%2B-555?style=flat" alt="macOS 14.6+">
  <img src="https://img.shields.io/badge/Chip-Intel%20%7C%20Apple%20Silicon-555?style=flat" alt="IntelとApple Silicon">
  <img src="https://img.shields.io/badge/Telemetry-None-555?style=flat" alt="テレメトリーなし">
</p>
<p align="center"><a href="https://wifi-lens.shiinalabs.com/ja/?utm_source=github&amp;utm_medium=readme&amp;utm_campaign=github_readme">公式サイト</a> &nbsp;·&nbsp; 買い切り</p>
<p align="center"><img src="assets/screenshot-network-experience.webp" alt="WiFi Lens Pro — Network Experienceによるネットワーク信頼性の分析" width="880"></p>
<p align="center"><sub>Network Experience · 記録された観測結果に基づいてネットワークの信頼性を評価</sub></p>

---

<p align="center"><a href="README.md">🇺🇸 English</a> · <a href="README.de.md">🇩🇪 Deutsch</a> · <a href="README.es-ES.md">🇪🇸 Español</a> · <a href="README.fr.md">🇫🇷 Français</a> · <a href="README.zh-Hans.md">🇨🇳 简体中文</a> · <strong>🇯🇵 日本語</strong> · <a href="README.zh-Hant.md">🇭🇰 繁體中文</a></p>

## Wi-Fiの問題は、都合のよいタイミングで起きるとは限りません

Wi-Fiが突然切断されたり、遅延が急に大きくなったり、しばらくすると接続が自然に回復したりすることがあります。調査しようとしたときには、問題がすでに消えているかもしれません。

**WiFi Lens Proは、今のネットワークを確認するだけでなく、必要に応じて継続観測することで、繰り返し発生する問題を後から調査できる記録として残します。**

| **🔍 01 · 今すぐ診断** | **📡 02 · 継続観測** | **🗂️ 03 · 履歴を調査** |
|:---|:---|:---|
| 現在の接続状態と無線環境を把握 | 必要なときに観測結果を収集 | 信頼性、過去の基準、問題の証拠を確認 |
| [ネットワーク診断を見る](#01--今すぐ診断) | [継続観測を見る](#02--継続観測) | [履歴調査を見る](#03--履歴を調査) |

---

## 01 · 今すぐ診断

### まず、問題がどこにあるのかを確認する

**Network Check**では、**This Mac、LAN、Internet**の3段階で接続経路を確認できます。ゲートウェイ、DNS、HTTP/HTTPS、オプションのIPv6、設定済みプロキシに関するチェック結果を確認し、問題が確認されたケースと、判断に十分な証拠がないケースを区別できます。

無線環境が関係している場合は、**Wi-Fi分析**で周辺の2.4 / 5 / 6 GHzネットワーク、信号強度、チャネルの使用状況と混雑度、セキュリティ情報、地域に応じたチャネルの推奨を確認できます。

<table>
<tr>
<td width="50%" align="center"><img src="assets/screenshot-selfcheck.webp" alt="Network Checkによるネットワーク診断" width="100%"><sub>Network Check · 接続を段階ごとに確認</sub></td>
<td width="50%" align="center"><img src="assets/screenshot-hero.webp" alt="リアルタイムWi-Fi分析とチャネルの推奨" width="100%"><sub>Wi-Fi分析 · 周辺の無線環境を確認</sub></td>
</tr>
</table>

これら2つのリアルタイム機能は、無料のオープンソース版にも含まれています。Proでは、継続観測と履歴調査のワークフローを追加しています。

---

## 02 · 継続観測

### 問題が再発するまで画面の前で待つ必要はありません

一部の問題は数秒で解消します。何度もスキャナーを開く代わりに、必要に応じてネットワークを観測し、後から確認できる記録を残せます。

| 機能 | できること |
|---|---|
| **メニューバーの状態表示** | 現在の接続、ゲートウェイの状態、最近の変化、短期的な傾向を表示します。 |
| **Continuous Observation** | Proアプリを終了した後も、対応するネットワーク観測データを任意で収集します。初期状態ではオフで、Macのスリープ中は収集を一時停止します。 |
| **Spectrum → Recording** | 選択したAPの信号変化を記録します。記録を保存し、後から読み込んで確認できます。 |

---

## 03 · 履歴を調査

### 問題が解消しても、証拠には価値があります

Proの履歴機能は、**Network Experience**と**Problem History**を中心に構成されています。関連のないグラフを自分で読み解くのではなく、記録された証拠をたどって調査できます。

**ネットワークの信頼性（Network Experience → Reliability）**

ネットワークと期間を選択し、利用可能な証拠に基づく信頼性評価を確認できます。検出された問題とその発生時刻も表示されます。観測範囲が不十分な期間は、ネットワークが正常だった証拠として扱われません。

**過去の基準値（Network Experience → Baseline）**

保存されたゲートウェイ遅延の測定値を、比較条件を満たす過去の基準値と比較します。根拠のある相対的な変化を確認できますが、単独の偏差だけでネットワーク障害と断定するものではありません。

**問題の記録（Problem History）**

保存された問題の記録、裏付けとなる証拠、その後の観測結果を確認できます。証拠に基づく場合は、次に行うチェックの提案から該当するツールに進めます。チェックの実行は、引き続きユーザーが明示的に行います。

<table>
<tr>
<td width="50%" align="center"><img src="assets/screenshot-historical-baseline.webp" alt="ゲートウェイ遅延の過去の基準値との比較" width="100%"><sub>Historical Baseline · 比較条件を満たす過去の測定値と比較</sub></td>
<td width="50%" align="center"><img src="assets/screenshot-problem-history.webp" alt="Problem Historyの問題記録と証拠" width="100%"><sub>Problem History · 記録された問題と証拠を確認</sub></td>
</tr>
</table>

<p align="center"><strong>今の状態を確認し、時間をかけて観測し、後から調査する。</strong></p>
<p align="center">それがWiFi Lens Proの一連の体験です。</p>
<p align="center"><a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>WiFi Lens Proを入手</strong></a></p>

---

## そのほかの便利なツール

このワークフローに加えて、WiFi Lensにはローミングテスト、チャネルヒートマップ、AP Radar、Bluetooth LEスキャン、グラフのエクスポート、ローカルMCP連携も用意されています。

WiFi Lens Proには、通信事業者向けのシナリオに対応する**Wi-Fi Calling Test**も含まれています。事業者プリセットまたはカスタムMCC/MNC値を使用できます。

## Proとオープンソース版

無料のオープンソース版では、リアルタイムのWi-Fi分析とローカルネットワーク診断を利用できます。**WiFi Lens Pro**は、それらに継続観測、履歴分析、問題調査の機能を追加します。

| 機能 | Pro | オープンソース版 |
|---|:---:|:---:|
| Wi-Fi分析、チャネル品質、推奨 | ✓ | ✓ |
| Network Check | ✓ | ✓ |
| ローミングテスト、AP Radar、チャネルヒートマップ | ✓ | ✓ |
| ローカルMCP、グラフのエクスポート | ✓ | ✓ |
| メニューバーの状態表示と継続観測 | ✓ | — |
| ネットワークの信頼性と過去の基準値 | ✓ | — |
| 問題の記録と履歴調査 | ✓ | — |
| スペクトラム録画、Wi-Fi Calling Test | ✓ | — |

<p align="center"><a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8">WiFi Lens Proを入手</a> &nbsp;·&nbsp; <a href="https://github.com/ShiinaLabs/wifi-lens/releases/latest">無料のオープンソース版をダウンロード</a></p>

---

## プライバシーとデータ

WiFi LensはWi-FiスキャンデータをMac上で処理します。アカウント、クラウド同期、利用状況のテレメトリーは必要ありません。

- **Network Check：** 公開されている診断先に接続し、該当する場合は設定済みのプロキシを確認します。
- **Continuous Observation：** 初期状態ではオフです。観測データはMac上に保存され、スリープ中は収集を一時停止します。
- **ローカルMCP：** サーバーは`127.0.0.1`のみにバインドします。AIクライアントが外部サービスに接続する場合は、そのクライアントのデータ取り扱いを別途確認してください。
- **システム権限：** macOSでは、アプリがWi-FiのSSIDを読み取るために位置情報サービスの許可が必要です。WiFi LensはGPS位置情報を読み取りません。

詳しくは [プライバシーポリシー](https://wifi-lens.shiinalabs.com/ja/privacy/?utm_source=github&utm_medium=readme&utm_campaign=github_readme).

## WiFi Lensを入手

**WiFi Lens Pro:** [Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8)での買い切り購入です。macOS 14.6以降が必要で、IntelとApple Siliconに対応しています。6 GHzスキャンにはWi-Fi 6E/7対応ハードウェアが必要です。

**WiFi Lens オープンソース版:** [GitHub Releases](https://github.com/ShiinaLabs/wifi-lens/releases/latest)またはHomebrewから入手できます。

<p>
<a href="https://github.com/ShiinaLabs/wifi-lens/releases/latest"><img src="https://img.shields.io/github/v/release/ShiinaLabs/wifi-lens?label=Latest&amp;color=2563eb" alt="最新リリース"></a>
<a href="https://github.com/ShiinaLabs/wifi-lens/releases/latest"><img src="https://img.shields.io/github/downloads/ShiinaLabs/wifi-lens/WiFiLens.dmg?label=Downloads&amp;displayAssetName=false&amp;color=2563eb" alt="ダウンロード数"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue" alt="Apache 2.0ライセンス"></a>
</p>

```sh
brew tap ShiinaLabs/apps
brew install --cask ShiinaLabs/apps/wifi-lens
```

<details>
<summary><strong>AI / MCP：連携と設定</strong></summary>

WiFi Lensには、任意で有効にできるローカルMCPサーバーがあります。有効にすると、互換性のあるAIツールからリアルタイムのWi-Fiスキャンデータを読み取れます。たとえば、周辺のチャネル使用状況やネットワークのセキュリティ情報を確認できます。

サーバーは`127.0.0.1`のみにバインドします。MCPクライアントの設定例：

```json
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840/"
    }
  }
}
```

Codexの設定：

```toml
[mcp_servers.wifi-lens]
url = "http://127.0.0.1:19840/"
```

詳しくは [AIワークフローガイド](https://wifi-lens.shiinalabs.com/ja/ai-mcp/?utm_source=github&utm_medium=readme&utm_campaign=github_readme).

</details>

<details>
<summary><strong>開発とコントリビュート</strong></summary>

```sh
git clone https://github.com/ShiinaLabs/wifi-lens
cd wifi-lens

xcodebuild -project WiFiLens.xcodeproj -scheme "WiFi Lens" \
  -configuration Debug -destination 'platform=macOS' build

xcodebuild -project WiFiLens.xcodeproj -scheme "WiFi Lens" \
  -configuration Debug -destination 'platform=macOS' \
  -skipPackageUpdates test -only-testing:WiFiLensTests -only-testing:WiFiLensCoreTests
```

アーキテクチャのドキュメントは[docs/](docs/)にあります。問題の報告、改善案、プルリクエストについては[コントリビューションガイド](.github/CONTRIBUTING.md)をご覧ください。

</details>

## コミュニティとライセンス

[Rabbit Hole](https://discord.gg/gH6sTCYaJ7)に参加して、WiFi Lensやその他のプロジェクトについて話しましょう。

**お問い合わせ：** [@WiFiLens](https://x.com/WiFiLens) · [contacts@shiinalabs.com](mailto:contacts@shiinalabs.com)

このプロジェクトは[tiny-wifi-analyzer](https://github.com/nolze/tiny-wifi-analyzer)からフォークされています。MACベンダーデータは[IEEE Registration Authority](https://standards.ieee.org/products-programs/regauth/)に由来します。詳しくは[第三者ライセンス表記](docs/THIRD-PARTY-NOTICES.md)をご覧ください。

Apache License 2.0 © 2020 nolze, 2026 ShiinaLabs — 詳細は [LICENSE](LICENSE).
