# WiFi Lens

**MacのWi-Fiトラブルシューティングを完結させるワークフロー。**

WiFi Lens Proは、リアルタイムWi-Fi分析、ネットワーク診断、継続的なモニタリング、Timeline履歴、Statistics、Insightsを、ネイティブmacOSアプリにまとめます。

**WiFi Lens ProはWiFi Lensの完全版です。**

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>WiFi Lens Proを入手</strong></a>
  &nbsp;·&nbsp;
  <a href="https://wifi-lens.shiinalabs.com">公式サイト</a>
</p>

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="Mac App Storeからダウンロード" width="190"></a>
</p>

<p align="center"><img alt="macOSでWi-Fiスペクトラムを分析するWiFi Lens" src="assets/screenshot-hero.webp" width="800"></p>

<p align="center">macOS 14以降 &nbsp;·&nbsp; Apple Silicon / Intel &nbsp;·&nbsp; テレメトリーなし</p>

<p align="center">
  🔒 <strong>ローカルファーストのプライバシー</strong> — アカウント、クラウド、テレメトリーなし<br>
  🩺 <strong>証拠に基づく診断</strong> — 経路、DNS、HTTPS、プロキシを説明可能な形で確認<br>
  🤖 <strong>AIワークフロー向けMCP</strong> — 対応クライアントからMac上のリアルタイムWi-Fiデータに接続
</p>

<p align="center"><sub>このリポジトリには、基本的なローカル分析、開発、ソースコードの確認、コミュニティへの貢献のためのオープンソース版が含まれています。</sub></p>

---

<p align="center">
  <a href="README.md">🇺🇸 English</a> · <a href="README.de.md">🇩🇪 Deutsch</a> · <a href="README.es-ES.md">🇪🇸 Español</a> · <a href="README.fr.md">🇫🇷 Français</a> · <a href="README.zh-Hans.md">🇨🇳 简体中文</a> · 🇯🇵 日本語
</p>
<p align="center">
  <a href="#wifi-lens-proを選ぶ理由">WiFi Lens Proを選ぶ理由</a> · <a href="#コア機能">コア機能</a> · <a href="#エディション">エディション</a> · <a href="#ai--mcp連携">AI / MCP</a> · <a href="#オープンソース版">オープンソース版</a> · <a href="#プライバシー">プライバシー</a> · <a href="#wifi-lensを入手">入手方法</a> · <a href="#開発">開発</a> · <a href="#コントリビュート">コントリビュート</a> · <a href="#ライセンス">ライセンス</a>
</p>

---

## WiFi Lens Proを選ぶ理由

ライブ診断は、今起きていることを教えてくれます。問題が断続的に起きるとき、WiFi Lens Proはその先まで追跡します。継続的に観測・記録し、履歴を残して、後から何が起きたのかを調べられます。

| ワークフロー | WiFi Lens Proでできること |
|--------------|---------------------------|
| 今すぐ診断する | リアルタイムWi-Fi分析、チャンネル分析、ネットワーク診断 |
| 継続して見守る | メニューバーからのモニタリングと継続観測 |
| 断続的な問題を記録する | Timelineとスペクトラム記録 |
| 起きたことを振り返る | 過去のイベントと接続変化の確認 |
| パターンを見つける | 記録期間をまたいだStatistics |
| 証拠を理解する | 記録した観測結果に基づくInsights |

**WiFi Lens Proは完全版です。** ライブアナライザーをモニタリング、履歴、調査につなぎ、別々のツールとして扱いません。

<table>
<tr>
<td width="50%" align="center"><img alt="Network Self-Checkの診断画面" src="assets/screenshot-selfcheck.webp" width="100%"><sub>Network Self-Check</sub></td>
<td width="50%" align="center"><img alt="接続履歴を表示するEvent Timeline" src="assets/screenshot-timeline.webp" width="100%"><sub>Event Timeline（Pro）</sub></td>
</tr>
</table>

### 今すぐ診断 → 後から調査

Wi-Fiの問題は、調べる前に消えてしまうことがあります。WiFi Lens Proは、切断、ローミング、信号変化の前後にある証拠を残し、後からイベントと周辺のネットワーク状態を確認できるようにします。

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>WiFi Lens Proを入手 →</strong></a>
</p>

---

## コア機能

WiFi Lensは、ローカルのWi-Fi環境を理解するための基本ツールを、ネイティブMacアプリにまとめています。

| 機能 | できること |
|------|------------|
| 📡 Wi-Fiスキャン | 2.4 / 5 / 6 GHz帯の周辺ネットワークをスキャン |
| 📊 スペクトラムとチャンネル品質 | 使用状況、混雑度、地域に応じたチャンネル推奨を確認 |
| 🔍 ネットワーク詳細 | PHY世代、チャンネル幅、802.11k/r/v、WPA3、接続情報を確認 |
| 🚶 ローミングとヒートマップ | APハンドオフを検証し、帯域ごとの使用状況を比較 |
| 🩺 Network Self-Check（プレビュー） | 経路、DNS、HTTPS、設定済みプロキシの到達性を確認 |
| 📻 AP Radar（プレビュー） | 選択したAPを追跡し、RSSIに基づくガイダンスと音声フィードバックを利用 |
| 🤖 MCPとエクスポート | ローカルAIツールに接続し、チャートをPNGまたはCSVで保存 |
| 🔒 ローカルファーストのプライバシー | スキャンデータをMacに保持し、利用テレメトリーを収集しない |

---

## エディション

### WiFi Lens Pro

**WiFi Lens Proは完全版です。** 継続観測、記録、履歴、調査を必要とするユーザー向けに、[Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8)で買い切り購入できます。

### オープンソース版

オープンソース版は、GitHubからの配布を好む方や、コードを確認して貢献したい方に、充実したライブ分析機能を提供します。[GitHub Releases](https://github.com/SHIINASAMA/wifi-lens/releases/latest)から入手できます。

| 機能 | WiFi Lens Pro | オープンソース版 |
|------|---------------|------------------|
| リアルタイムWi-Fi分析 | ✅ | ✅ |
| ネットワーク診断 | ✅ | ✅ |
| チャンネル推奨 | ✅ | ✅ |
| 継続モニタリング | ✅ | — |
| イベント履歴 | ✅ | — |
| 過去の統計 | ✅ | — |
| Insights | ✅ | — |
| スペクトラム記録 | ✅ | — |
| メニューバーモニタリング | ✅ | — |

どちらのエディションもローカルファーストです。違いはライブアナライザーを取り巻くワークフローにあります。Proは、時間をまたいだ問題を観測・保存・調査するためのコンテキストを追加します。

---

## AI / MCP連携

WiFi Lensには、対応するAIアシスタントがローカルのWi-Fiデータを読み取れる組み込みMCPサーバーがあります。設定で有効にし、**AIセットアッププロンプトをコピー**を選んで、Codex DesktopやClaude DesktopなどのMCP対応デスクトップクライアントに貼り付けてください。

```json
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840"
    }
  }
}
```

手動設定では、クライアントが要求する形式を使ってください。

```toml
# Codex: ~/.codex/config.toml
[mcp_servers.wifi-lens]
url = "http://127.0.0.1:19840/"
```

```json
// Claude DesktopなどJSONベースのクライアント
{
  "mcpServers": {
    "wifi-lens": {
      "url": "http://127.0.0.1:19840/"
    }
  }
}
```

接続後は、「近くで混雑しているチャンネルは？」や「近くのネットワークでWPA3に対応しているものは？」のように質問できます。サーバーは`127.0.0.1`のみにバインドされるため、意図的に別の場所へルーティングしない限りデータはMacの外へ出ません。

詳しい例は [AIワークフローガイド](https://wifi-lens.shiinalabs.com/ai-mcp/)をご覧ください。

---

## オープンソース版

オープンソース版は、ローカル分析、開発、ソースコードの確認、コミュニティへの貢献に利用できます。

- **GitHub Releases** — [最新版をダウンロード](https://github.com/SHIINASAMA/wifi-lens/releases/latest)
- **Homebrew** — `brew tap ShiinaLabs/apps && brew install --cask ShiinaLabs/apps/wifi-lens`
- **ソースコードとドキュメント** — リポジトリと[アーキテクチャドキュメント](docs/)を参照

<details>
<summary>オープンソース版の機能</summary>

| 機能 | 説明 | 状態 |
|------|------|------|
| 📡 Wi-Fiスキャン | 2.4 / 5 / 6 GHz帯のリアルタイムスキャン | Stable |
| 📊 スペクトラム表示 | ガウス曲線によるチャンネル使用率の表示 | Stable |
| 🎯 チャンネル品質 | 混雑スコアと地域別の推奨 | Stable |
| 🔍 ネットワーク詳細 | PHY世代、チャンネル幅、802.11k/r/v、WPA3 | Stable |
| 📶 接続情報 | IP、ゲートウェイ、DNS、MAC、Txレート、セキュリティ概要 | Stable |
| 🚶 ローミングテスト | APハンドオフの監視とセッションの保存・読み込み | Stable |
| 🗺️ チャンネルヒートマップ | 帯域ごとの使用率ヒートマップ | Stable |
| 🎧 BLEスキャナー | Bluetooth LEの検出、RSSI分析、追跡 | Stable |
| 🎨 スマートカラー | SSIDに基づく決定的な色割り当て | Stable |
| 🌐 MCPサーバー | AIツール連携用の組み込みHTTP API | Stable |
| 📤 エクスポート | チャートをPNGまたはCSVで保存 | Stable |
| 🔒 プライバシーファースト | テレメトリーなし。スキャンデータはMacに保持 | Stable |
| ⬆️ 自動アップデート | GitHub版ではSparkleを使用 | Stable |
| 🌍 多言語対応 | 英語、ドイツ語、スペイン語、日本語、中国語 | Stable |
| 🩺 Network Self-Check | 経路、DNS、HTTPS、プロキシをワンクリックで診断 | Preview |
| 📻 AP Radar | 選択したAPを音声パルスで追跡 | Preview |

</details>

[![Downloads](https://img.shields.io/github/downloads/SHIINASAMA/wifi-lens/WiFiLens.dmg?label=Downloads&displayAssetName=false&color=2563eb)](https://github.com/SHIINASAMA/wifi-lens/releases/latest)
[![Latest release](https://img.shields.io/github/v/release/SHIINASAMA/wifi-lens?label=Latest&color=2563eb)](https://github.com/SHIINASAMA/wifi-lens/releases/latest)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

---

## プライバシー

WiFi Lensは、利用分析、クラッシュテレメトリー、Wi-Fiスキャンデータを収集しません。

- **位置情報サービス：** macOSはWi-FiのSSID名を公開するためにこの権限を必要とします。WiFi LensはGPS位置情報を読み取りません。
- **地域検出：** システムのロケール、ハードウェアが報告するチャンネル一覧、近隣APの国コードをデバイス上で使用します。
- **Network Self-Check：** 公開エンドポイント（`www.apple.com`、`www.msftconnecttest.com`）を解決し、設定済みプロキシの到達性を確認することがあります。
- **MCPサーバー：** `127.0.0.1`のみにバインドされます。有効化した後にローカルツールがデータへアクセスできます。
- **アップデート確認：** GitHub版は、アップデート確認を要求したとき、または自動確認を有効にしたときにGitHubへ接続します。

📋 [セキュリティポリシー](SECURITY.md) · 📝 [変更履歴](https://github.com/SHIINASAMA/wifi-lens/releases) · ❓ [FAQ](https://wifi-lens.shiinalabs.com/faq/) · 🌐 [プライバシーポリシー全文](https://wifi-lens.shiinalabs.com/privacy/)

---

## WiFi Lensを入手

**macOS 14（Sonoma）以降**が必要です。IntelとApple Siliconの両方に対応しています。6 GHzスキャンにはWi-Fi 6E/7対応ハードウェアが必要です。

### WiFi Lens Pro

継続モニタリング、記録、履歴、調査のための完全版です。[Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8)から入手できます。

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="Mac App Storeからダウンロード" width="190"></a>
</p>

### オープンソース版

GitHubからの配布とコミュニティ開発向けです。

- [GitHub Releases](https://github.com/SHIINASAMA/wifi-lens/releases/latest)
- Homebrew：`brew tap ShiinaLabs/apps && brew install --cask ShiinaLabs/apps/wifi-lens`
- ソースコード：このリポジトリ

> [!IMPORTANT]
> macOS 14以降では、Wi-FiのSSID名を読み取るために**位置情報サービス**を有効にする必要があります。**システム設定 → プライバシーとセキュリティ → 位置情報サービス**を開き、要求されたらWiFi Lensを有効にしてください。

---

## 開発

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

アーキテクチャドキュメントは [docs/](docs/)にあります。

---

## コントリビュート

質問、バグ報告、機能のアイデアを歓迎します。セットアップ、PRの規約、ローカライズ要件については[コントリビューションガイドライン](.github/CONTRIBUTING.md)をご覧ください。

WiFi Lensやその他のプロジェクトの小さなコミュニティ **[Rabbit Hole](https://discord.gg/gH6sTCYaJ7)** にも参加できます。

**連絡先：** [Xの@WiFiLens](https://x.com/WiFiLens) · [wifi-lens@shiinalabs.com](mailto:wifi-lens@shiinalabs.com)

---

## ライセンス

[tiny-wifi-analyzer](https://github.com/nolze/tiny-wifi-analyzer)からフォークしています。MACベンダーデータは[IEEE Registration Authority](https://standards.ieee.org/products-programs/regauth/)のものです。詳しくは[サードパーティ通知](docs/THIRD-PARTY-NOTICES.md)をご覧ください。

Apache License 2.0 © 2020 nolze, 2026 SHIINASAMA — [LICENSE](LICENSE)を参照してください。
