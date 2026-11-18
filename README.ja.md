# WiFi Lens Pro

**Wi-Fiで何が起きているかを把握する。**

ライブWi-Fi分析、ネットワーク診断、継続的な観測、問題発生後の履歴調査を1つにまとめたmacOSネイティブアプリです。

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><img src="assets/appstore-badge-en.svg" alt="WiFi Lens Proを入手" width="190"></a>
</p>

<p align="center"><a href="https://wifi-lens.shiinalabs.com/ja/?utm_source=github&amp;utm_medium=readme&amp;utm_campaign=github_readme">公式サイト</a></p>

<p align="center"><img src="assets/screenshot-network-experience.webp" alt="WiFi Lens ProのNetwork Experienceで観測された接続の信頼性を表示" width="800"></p>

<p align="center"><sub>macOS 14.6+ · Intel &amp; Apple Silicon · One-time purchase</sub></p>

---

<p align="center">
  <a href="README.md">🇺🇸 English</a> · <a href="README.de.md">🇩🇪 Deutsch</a> · <a href="README.es-ES.md">🇪🇸 Español</a> · <a href="README.fr.md">🇫🇷 Français</a> · <a href="README.zh-Hans.md">🇨🇳 简体中文</a> · 🇯🇵 日本語 · <a href="README.zh-Hant.md">🇭🇰 繁體中文</a>
</p>

<p align="center">
  <a href="#wifi-lens-proを選ぶ理由">Proについて</a> · <a href="#コア機能">ライブツール</a> · <a href="#エディション">エディション</a>
</p>

---

## WiFi Lens Proを選ぶ理由

Wi-Fiの問題は、調べようとしたときには消えていることがあります。WiFi Lens Proは現在の接続を調べるツールと、あとから確認できる観測履歴を組み合わせています。

### いまの接続を調べる

周辺のWi-Fiネットワークやチャンネルの混雑状況を確認し、接続に問題があるときはNetwork Checkを実行。ライブ分析とネットワーク診断をProの一連のワークフローで利用できます。

### 必要なときに観測を続ける

メニューバーで現在の接続情報を確認できます。任意のバックグラウンド観測はProアプリを閉じたあとも継続可能です。初期状態ではオフで、Macのスリープ中は停止します。

### 問題発生後に記録を調べる

Network Experienceで観測された期間の信頼性を確認。Historical Baselineは保存済みゲートウェイ遅延を過去の基準と比較し、Problem Historyは記録された問題と根拠をまとめて表示します。

<table>
<tr>
<td width="50%" align="center"><img src="assets/screenshot-historical-baseline.webp" alt="Historical Baselineで保存済みゲートウェイ遅延と過去の基準を比較" width="100%"><sub>Historical Baseline</sub></td>
<td width="50%" align="center"><img src="assets/screenshot-problem-history.webp" alt="Problem Historyに記録された問題と根拠を表示" width="100%"><sub>Problem History</sub></td>
</tr>
</table>

<p align="center"><a href="https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8"><strong>WiFi Lens Proを入手</strong></a></p>

---

## コア機能

日常的なトラブルシューティングに使うライブツールもProに含まれます。

- **Wi-Fi分析** — 2.4、5、6 GHz帯の周辺ネットワークをスキャンし、電波強度、チャンネル利用状況、混雑、セキュリティ、地域別の推奨を比較できます。
- **Network Check** — Macからローカルネットワーク、インターネットまでの経路を調べ、ゲートウェイ、DNS、HTTP/HTTPS、任意のIPv6、プロキシ経路を確認します。
- **その他のローカルツール** — ローミングとチャンネルヒートマップ、AP Radar、ローカルMCP連携、チャートのエクスポート。これらのライブツールは無料のオープンソース版でも利用できます。

<p align="center"><img src="assets/screenshot-hero.webp" alt="WiFi LensのWi-Fi分析概要とチャンネル品質の推奨" width="800"></p>
<p align="center"><img src="assets/screenshot-selfcheck.webp" alt="Network CheckのThis Mac、LAN、Internet各段階の結果" width="800"></p>

---

## エディション

### WiFi Lens Pro
WiFi Lens Proは[Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8)での買い切りです。メニューバーの接続状況、Network Experience、Problem History、スペクトラム記録、任意のバックグラウンド観測、キャリア向けのWi-Fi Calling Testが追加されます。Historical BaselineはNetwork Experience内のビューです。

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
| Wi-Fi Calling Test | ✅ | — |

どちらの版もWi-FiスキャンをMac上で処理します。Proには履歴分析、スペクトラム記録、任意のバックグラウンド観測、Wi-Fi Calling Testが加わります。

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
WiFi Lens Proでは、ライブWi-Fi分析にメニューバーの接続状況、Network Experience、Problem History、スペクトラム記録、任意のバックグラウンド観測、キャリア向けのWi-Fi Calling Testが加わります。[Mac App Store](https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=github_readme&mt=8)から入手できます。

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
