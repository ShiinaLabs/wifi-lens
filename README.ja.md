# WiFi Lens

**Wi-Fiで何が起きているかを把握する。**

macOSネイティブのWi-Fiアナライザー／ネットワーク診断アプリ。

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>WiFi Lens Proを入手</strong></a>
  &nbsp;·&nbsp;
  <a href="https://wifi-lens.shiinalabs.com/ja/?utm_source=github&amp;utm_medium=readme&amp;utm_campaign=github_readme">公式サイト</a>
</p>

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="Mac App Storeからダウンロード" width="190"></a>
</p>

<p align="center"><img alt="Problem Historyの記録済み問題と根拠を表示するWiFi Lens Pro" src="assets/screenshot-problem-history.webp" width="800"></p>

<p align="center">macOS 14.6以降 &nbsp;·&nbsp; Apple Silicon / Intel &nbsp;·&nbsp; ローカル優先</p>

<p align="center">
  🔒 <strong>ローカルで処理</strong> — Wi-Fiスキャン記録はMacに保存。利用状況のテレメトリーはありません<br>
  🩺 <strong>ネットワーク診断</strong> — 接続、DNS、HTTPS、IPv6、設定済みプロキシを確認<br>
  🤖 <strong>AIワークフロー向けMCP</strong> — 互換クライアントからMac上のライブWi-Fiデータに接続
</p>

<p align="center"><sub>このリポジトリには、リアルタイムのローカル分析、開発、ソースコードの確認、コミュニティへの貢献のためのオープンソース版が含まれています。</sub></p>

---

<p align="center">
  <a href="README.md">🇺🇸 English</a> · <a href="README.de.md">🇩🇪 Deutsch</a> · <a href="README.es-ES.md">🇪🇸 Español</a> · <a href="README.fr.md">🇫🇷 Français</a> · <a href="README.zh-Hans.md">🇨🇳 简体中文</a> · 🇯🇵 日本語 · <a href="README.zh-Hant.md">🇭🇰 繁體中文</a>
</p>

<p align="center">
  <a href="#wifi-lens-proを選ぶ理由">WiFi Lens Proを選ぶ理由</a> · <a href="#コア機能">コア機能</a> · <a href="#エディション">エディション</a> · <a href="#ai--mcp連携">AI / MCP</a> · <a href="#オープンソース版">オープンソース版</a> · <a href="#プライバシー">プライバシー</a> · <a href="#wifi-lensを入手">入手方法</a> · <a href="#開発">開発</a> · <a href="#コントリビュート">コントリビュート</a> · <a href="#ライセンス">ライセンス</a>
</p>

---

## WiFi Lens Proを選ぶ理由
ライブWi-Fi分析で現在の接続状況を把握できます。WiFi Lens Proでは、観測された信頼性の確認、ゲートウェイ遅延と過去の基準との比較、記録された問題と根拠の調査も行えます。

| ワークフロー | WiFi Lens Proでできること |
|--------------|---------------------------|
| 状態をすぐ確認 | メニューバーから現在の接続情報を確認 |
| 信頼性を評価 | 選択した期間に観測されたネットワーク体験を確認 |
| 過去の基準と比較 | 保存されたゲートウェイ遅延を互換性のある過去の基準と比較 |
| 記録された問題を調査 | 保存された問題、その根拠、後からの観測を確認 |
| アプリ終了中も観測 | 任意のバックグラウンド観測。初期状態ではオフで、Macのスリープ中は停止 |

WiFi Lens Proはライブ分析に、信頼性と過去の問題を確認するビューを加えます。StatisticsとInsightsは提供を終了しました。Timelineは既存イベントの表示と書き出しのみ利用でき、新しい記録や分析は追加されません。

<table>
<tr>
<td width="50%" align="center"><img alt="信頼性評価と観測範囲を表示するNetwork Experience" src="assets/screenshot-network-experience.webp" width="100%"><sub>Network Experience</sub></td>
<td width="50%" align="center"><img alt="ゲートウェイ遅延と過去の測定値を比較するHistorical Baseline" src="assets/screenshot-historical-baseline.webp" width="100%"><sub>Historical Baseline</sub></td>
</tr>
</table>

### ライブ分析から過去の状況へ

問題が断続的に起きる場合、Network Experienceで一定期間に観測された状況を評価できます。Problem Historyでは、記録された問題とその根拠をまとめて確認できます。

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>WiFi Lens Proを入手 →</strong></a>
</p>

---

## コア機能
WiFi Lensは、近くのネットワーク、チャンネル利用状況、Macの接続を把握するためのライブツールを備えています。

| 機能 | できること |
|------|------------|
| 📡 Wi-Fiスキャン | 2.4 / 5 / 6 GHz帯の周辺ネットワークをスキャン |
| 📊 スペクトラムとチャンネル品質 | 使用状況、混雑度、地域に応じたチャンネル推奨を確認 |
| 🔍 ネットワーク詳細 | PHY世代、チャンネル幅、802.11k/r/v、WPA3、接続情報を確認 |
| 🚶 ローミングとヒートマップ | APハンドオフを検証し、帯域ごとの使用状況を比較 |
| 🩺 Network Self-Check | 接続、DNS、HTTPS、IPv6、設定済みプロキシを確認 |
| 📻 AP Radar（プレビュー） | 選択したAPを追跡し、RSSIに基づくガイダンスと音声フィードバックを利用 |
| 🤖 MCPとエクスポート | ローカルAIツールに接続し、チャートをPNGまたはCSVで保存 |
| 🔒 ローカルファーストのプライバシー | スキャンデータをMacに保持し、利用テレメトリーを収集しない |

---

## エディション

### WiFi Lens Pro
WiFi Lens Proは[Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8)での買い切りです。メニューバーの接続状況、Network Experience、Problem History、スペクトラム記録、任意のバックグラウンド観測が追加されます。Historical BaselineはNetwork Experience内のビューです。

### オープンソース版

WiFi Lens OSSは無料のオープンソース版です。ライブWi-Fi分析とローカルネットワーク診断を[GitHub Releases](https://github.com/ShiinaLabs/wifi-lens/releases/latest)、Homebrew、またはソースコードから利用できます。

| 機能 | WiFi Lens Pro | オープンソース版 |
|------|---------------|------------------|
| ライブWi-Fi分析 | ✅ | ✅ |
| ネットワーク診断 | ✅ | ✅ |
| チャンネル推奨 | ✅ | ✅ |
| MCP連携 | ✅ | ✅ |
| メニューバーの接続状況 | ✅ | — |
| Network ExperienceとHistorical Baseline | ✅ | — |
| Problem History | ✅ | — |
| スペクトラム記録 | ✅ | — |
| 任意のバックグラウンド観測 | ✅ | — |

どちらの版もWi-FiスキャンをMac上で処理します。Proには履歴を使った分析ビューと、任意のバックグラウンド観測が加わります。Timelineは既存イベントの表示と書き出しのみ利用できます。
---

## AI / MCP連携


WiFi Lensには、任意で有効にできるローカルMCPサーバーがあります。有効にすると、互換クライアントからこのMacのライブWi-Fiスキャンデータを取得できます。Codex DesktopやClaude Desktopなど、MCP対応クライアントで設定してください。

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

接続後は「近くで混雑しているチャンネルは？」や「近くのネットワークでWPA3に対応しているものは？」のように質問できます。MCPサーバーは`127.0.0.1`のみで待ち受けます。接続先のクライアントやモデルサービスは、受け取ったデータを各自のポリシーと設定に従って処理する場合があります。

詳しい例は [AIワークフローガイド](https://wifi-lens.shiinalabs.com/ja/ai-mcp/?utm_source=github&utm_medium=readme&utm_campaign=github_readme)をご覧ください。

---

## オープンソース版
WiFi Lens OSSは無料のオープンソース版です。ローカルでのライブ分析、開発、ソースコードの確認、コミュニティへの貢献に利用できます。

- **GitHub Releases** — [最新版をダウンロード](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
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
| 🌍 多言語対応 | 英語、フランス語、ドイツ語、日本語、ロシア語、スペイン語、簡体字中国語、繁体字中国語 | Stable |
| 🩺 Network Self-Check | 接続、DNS、HTTPS、IPv6、設定済みプロキシの確認 | Stable |
| 📻 AP Radar | 選択したAPを音声パルスで追跡 | Preview |
| 📜 オープンソースライセンス | 設定 → 情報から同梱コンポーネント、ライセンス、通知を確認 | Stable |

</details>

[![Downloads](https://img.shields.io/github/downloads/ShiinaLabs/wifi-lens/WiFiLens.dmg?label=Downloads&displayAssetName=false&color=2563eb)](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
[![Latest release](https://img.shields.io/github/v/release/ShiinaLabs/wifi-lens?label=Latest&color=2563eb)](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

---

## プライバシー
WiFi Lensは、Wi-Fiスキャン記録をアプリサービスにアップロードせず、利用状況の分析やテレメトリーも収集しません。

- **位置情報サービス：** macOSはWi-FiのSSID名を公開するためにこの権限を必要とします。WiFi LensはGPS位置情報を読み取りません。
- **地域検出：** システムのロケール、ハードウェアが報告するチャンネル一覧、近隣APの国コードをデバイス上で使用します。
- **Network Self-Check：** 公開先や該当する設定済みプロキシに診断プローブを送信します。診断エビデンスはローカルに保存されます。
- **MCPサーバー：** 任意機能で、`127.0.0.1`のみにバインドされます。接続クライアントやモデルサービスは、受信データを各自のポリシーと設定に従って処理します。
- **バックグラウンド観測：** Proの任意機能で、初期状態では無効です。観測データはローカルに保存され、Macのスリープ中は収集を停止します。
- **アップデート確認：** GitHub版は、アップデート確認を要求したとき、または自動確認を有効にしたときにGitHubへ接続します。

📋 [セキュリティポリシー](SECURITY.md) · 📝 [変更履歴](https://github.com/ShiinaLabs/wifi-lens/releases) · ❓ [FAQ](https://wifi-lens.shiinalabs.com/ja/faq/?utm_source=github&utm_medium=readme&utm_campaign=github_readme) · 🌐 [プライバシーポリシー全文](https://wifi-lens.shiinalabs.com/ja/privacy/?utm_source=github&utm_medium=readme&utm_campaign=github_readme)

---

## WiFi Lensを入手

**macOS 14.6（Sonoma）以降**が必要です。IntelとApple Siliconの両方に対応しています。6 GHzスキャンにはWi-Fi 6E/7対応ハードウェアが必要です。

### WiFi Lens Pro
WiFi Lens Proでは、ライブWi-Fi分析にメニューバーの接続状況、Network Experience、Problem History、スペクトラム記録、任意のバックグラウンド観測が加わります。[Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8)から入手できます。

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="Mac App Storeからダウンロード" width="190"></a>
</p>

### オープンソース版

GitHubからの配布とコミュニティ開発向けです。

- [GitHub Releases](https://github.com/ShiinaLabs/wifi-lens/releases/latest)
- Homebrew：`brew tap ShiinaLabs/apps && brew install --cask ShiinaLabs/apps/wifi-lens`
- ソースコード：このリポジトリ

> [!IMPORTANT]
> macOS 14.6以降では、Wi-FiのSSID名を読み取るために**位置情報サービス**を有効にする必要があります。**システム設定 → プライバシーとセキュリティ → 位置情報サービス**を開き、要求されたらWiFi Lensを有効にしてください。

---

## 開発

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

アーキテクチャドキュメントは [docs/](docs/)にあります。

---

## コントリビュート

質問、バグ報告、機能のアイデアを歓迎します。セットアップ、PRの規約、ローカライズ要件については[コントリビューションガイドライン](.github/CONTRIBUTING.md)をご覧ください。

WiFi Lensやその他のプロジェクトの小さなコミュニティ **[Rabbit Hole](https://discord.gg/gH6sTCYaJ7)** にも参加できます。

**連絡先：** [Xの@WiFiLens](https://x.com/WiFiLens) · [contacts@shiinalabs.com](mailto:contacts@shiinalabs.com)

---

## ライセンス

[tiny-wifi-analyzer](https://github.com/nolze/tiny-wifi-analyzer)からフォークしています。MACベンダーデータは[IEEE Registration Authority](https://standards.ieee.org/products-programs/regauth/)のものです。詳しくは[サードパーティ通知](docs/THIRD-PARTY-NOTICES.md)をご覧ください。

Apache License 2.0 © 2020 nolze, 2026 ShiinaLabs — [LICENSE](LICENSE)を参照してください。
