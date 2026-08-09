<div align="center">
  <img src="./banner.png" width="200" height="200" alt="Snapzy バナー" />

  <h1>Snapzy</h1>
  <p><strong>メニューバー常駐型、macOSネイティブなスクリーンショット、録画、注釈、編集アプリ</strong></p>

  <p>
    <a href="https://trendshift.io/repositories/24550" target="_blank"><img src="https://trendshift.io/api/badge/repositories/24550" alt="duongductrong%2FSnapzy | Trendshift" style="width: 250px; height: 55px;" width="250" height="55"/></a>
  </p>

  <p>
    <a href="https://developer.apple.com/xcode/swiftui/">SwiftUI</a>、
    <a href="https://developer.apple.com/documentation/appkit">AppKit</a>、
    <a href="https://developer.apple.com/documentation/screencapturekit">ScreenCaptureKit</a>、
    <a href="https://developer.apple.com/documentation/vision">Vision</a>、および
    <a href="https://sparkle-project.org/">Sparkle</a> を使用して構築されています
  </p>

  <p>
    <a href="./README.md">🇺🇸 English</a> •
    <a href="./README.vi.md">🇻🇳 Tiếng Việt</a> •
    <a href="./README.zh-CN.md">🇨🇳 简体中文</a> •
    <a href="./README.ja.md">🇯🇵 日本語</a>
  </p>

  <p>
    <a href="#features">機能</a> •
    <a href="#install">インストール</a> •
    <a href="#raycast">Raycast</a> •
    <a href="#shortcuts">ショートカット</a> •
    <a href="#development">開発</a> •
    <a href="#documentation">ドキュメント</a> •
    <a href="#community">コミュニティ</a> •
    <a href="#security">セキュリティ</a> •
    <a href="#contributing">コントリビュート</a> •
    <a href="#contributors">貢献者</a> •
    <a href="#acknowledgments">謝辞</a>
  </p>

  <p>
    <a href="https://github.com/duongductrong/Snapzy/stargazers"><img alt="GitHub Stars" src="https://img.shields.io/github/stars/duongductrong/Snapzy?style=flat&amp;logo=github" /></a>
    <a href="https://github.com/duongductrong/Snapzy/network/members"><img alt="GitHub Forks" src="https://img.shields.io/github/forks/duongductrong/Snapzy?style=flat&amp;logo=github" /></a>
    <a href="https://github.com/duongductrong/Snapzy/releases"><img alt="GitHub Downloads" src="https://img.shields.io/github/downloads/duongductrong/Snapzy/total?style=flat&amp;logo=github" /></a>
  </p>
  <p>
    <a href="https://deepwiki.com/duongductrong/Snapzy"><img alt="DeepWiki に質問" src="https://deepwiki.com/badge.svg" /></a>
    <a href="https://discord.gg/xkWDAuJkZu"><img alt="Discord コミュニティに参加" src="https://img.shields.io/badge/Discord-Join%20Community-5865F2?style=flat&amp;logo=discord&amp;logoColor=white" /></a>
    <a href="https://www.raycast.com/chkzz/snapzy"><img alt="Raycast 拡張機能" src="https://img.shields.io/badge/Raycast-Extension-FF6363?style=flat&amp;logo=raycast&amp;logoColor=white" /></a>
    <a href="#featured-on"><img alt="掲載実績" src="https://img.shields.io/badge/Featured%20On-Product%20Hunt%20%2B%20Unikorn-111827?style=flat&amp;logo=producthunt&amp;logoColor=white" /></a>
  </p>
  <p>
    <a href="https://github.com/sponsors/duongductrong"><img alt="GitHub Sponsors" src="https://img.shields.io/badge/Sponsor-%E2%9D%A4-ff69b4?style=flat&amp;logo=github" /></a>
    <a href="https://ko-fi.com/duongductrong"><img alt="Ko-fi Donate" src="https://img.shields.io/badge/Ko--fi-Donate-FF5E5B?style=flat&amp;logo=ko-fi&amp;logoColor=white" /></a>
  </p>
</div>

<a id="features"></a>

## 機能

- **スクリーンショット**: フルスクリーンまたは選択範囲のキャプチャ、手動選択／アプリケーションウインドウモードの切替（`Application Capture`、既定値は `A`）。通常はキャプチャ開始時に閉じる、すでに開いているサードパーティ製メニューバーのポップオーバーも選択時に視覚的に復元し、角丸の透明領域を保ったまま保存できる。保存前のインライン注釈付き範囲キャプチャ、ライブ結合プレビュー付きスクロールキャプチャ、ネイティブ通知で結果を表示する OCR テキスト抽出、安全な自動トリミングを任意で適用できる透明なオブジェクト切り抜き、ウインドウの影のキャプチャ（macOS 14+）、複数形式への書き出し（PNG/JPG/WebP）、デスクトップアイコン／ウィジェットの非表示、録画中のクイックスクリーンショットにも対応
- **画面収録**: ビデオまたは GIF 出力、システム音声 + マイク、マウスクリックのハイライト、キーストロークオーバーレイ、画面上のライブ注釈、前回の範囲の記憶、GIF のリサイズ、Follow Mouse 編集用の Smart Camera メタデータ
- **注釈エディタ**: 図形、矢印、テキスト、透かし、塗りつぶし矩形、ぼかし／ピクセル化、自動ローカル機密データマスキング、カウンター、エッジスナップ付きトリミング（`⌘` で無効化）とコンテンツへのワンキー自動トリミング（`A`）、トリミング領域を考慮した自動トリミング対応の背景削除、3D レンダラーによるモックアップ背景、ズーム／パン（ピンチ + キーボード）、編集を続けるオプションとエディタ再アクティブ化動作を備えたアプリへのドラッグ、設定可能なツール／アクションショートカット
- **キャプチャ後の設定**: 保存、Quick Access、クリップボードへのコピー、注釈に対するモード別アクションマトリクスと、独立したグローバルな背景削除時の自動トリミング切替（既定で有効）
- **ビデオエディタ**: 視覚的なタイムライン + フレームストリップによるトリミング、自動フォーカス付きズーム区間（Follow Mouse）、壁紙背景 + 余白、カスタム書き出し寸法、アニメーション GIF ビューア、取り消し／やり直し
- **Quick Access**: 各キャプチャ後に表示されるフローティングパネル。コピー、編集、アプリへのドラッグ、2本指スワイプでの閉じる操作、開く、削除を提供
- **キャプチャ履歴**: 最近のスクリーンショット、ビデオ、GIF のフローティング履歴パネル + 完全なブラウザ。種類／時間フィルター、ファイル名検索、コピー／開く／削除のクイック操作、Annotate または Video Editor でのワンクリック再オープン、確定済みスクリーンショット編集の編集可能な注釈復元、設定可能なパネルレイアウトと保持ポリシー
- **ショートカット**: キャプチャ、録画、注釈ツールのグローバルショートカットを完全に設定可能。ショートカットごとのオン／オフ制御とシステム競合の検出に対応
- **オンボーディング**: スプラッシュ画面、初回起動時の言語選択、権限設定のガイド、初めて使うユーザー向けのショートカット設定
- **ローカリゼーション**: 🇺🇸 English、🇻🇳 Vietnamese、🇨🇳 Simplified Chinese、🇹🇼 Traditional Chinese、🇪🇸 Spanish、🇯🇵 Japanese、🇰🇷 Korean、🇷🇺 Russian、🇫🇷 French、🇩🇪 German のアプリ内ローカリゼーションと、ネイティブ macOS のアプリごとの言語指定をサポート
- **クラウドアップロード**: プライバシー優先の持ち込みストレージ方式。AWS S3 または Cloudflare R2 を使い、サードパーティサーバーは介在しない。Quick Access からスクリーンショット、ビデオ、GIF を、Annotate からスクリーンショットを手動アップロードできる。認証情報は macOS Keychain に保存され、任意のパスワードで保護できる。別の Mac でのセットアップを速める手動の暗号化済み認証情報インポート／エクスポート、アップロード履歴、設定可能な自動有効期限（1〜90日または無期限）、ライフサイクルルール、カスタムドメインにも対応
- **高度な設定**: TOML のエクスポート／インポート、1回限りの設定フォルダ許可、デバウンスされたバックグラウンド同期、安全な開く前の同期、`~/.config/snapzy/config.toml` を介したポータブルな設定、dotfiles、バックアップ、マシン間セットアップのための起動時自動適用
- **アップデートと診断**: Sparkle によるアプリ内アップデート、診断ログバンドル付きの問題報告、キャッシュ管理
- **プラットフォーム**: メニューバーアプリ、外観テーマ（ライト／ダーク／システム）、安全なファイルアクセスブックマークを備えた App Sandbox

<a id="install"></a>

## インストール

> **macOS 13.0** 以降が必要です。

### Homebrew

```bash
brew install --cask snapzy
```

### シェルスクリプト

```bash
# Install a specific version
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/v1.30.1/install.sh | bash
```

### リリースをダウンロード

1. [Releases](https://github.com/duongductrong/Snapzy/releases) を開く
2. 最新のパッケージ済みアプリ資産（通常は `Snapzy-v<version>.dmg`）をダウンロードする
3. `Snapzy.app` を `/Applications` へ移動する
4. Snapzy を起動する
5. System Settingsで求められたら**画面収録とシステムオーディオ録音**の権限を許可する
6. macOS から求められた場合は、**画面収録とシステムオーディオ録音**を許可した後にSnapzyを再起動する
7. 録画で音声入力を使う場合は、Microphone 権限も許可する

> Snapzy は Apple による署名と公証を受けています。追加の手順なしで macOS から開けます。

## アンインストール

Snapzyを完全に削除し、すべての権限をリセットしてアプリデータを消去するには、以下のコマンドを実行します。

```bash
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/master/uninstall.sh | bash
```

またはリポジトリをクローンしている場合は、次を実行します。

```bash
./uninstall.sh
```

これにより`/Applications`からアプリが削除され、環境設定とキャッシュが削除され、TCC権限（Screen Recording、Microphone、Accessibility）がリセットされます。権限の変更を完全に反映するには、ログアウトまたは再起動が必要になる場合があります。

### 権限をリセット

アプリをアンインストールせずに TCC 権限（Screen Recording、Microphone、Accessibility）のみをリセットする場合は、以下のコマンドを実行します。

```bash
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/master/reset-permissions.sh | bash
```

またはリポジトリをクローンしている場合は、次を実行します。

```bash
./reset-permissions.sh
```

<a id="raycast"></a>

## Raycast

公式拡張機能を使ってRaycastからSnapzyを直接操作できます。

<a href="https://www.raycast.com/chkzz/snapzy" title="Install snapzy Raycast Extension"><img src="https://www.raycast.com/chkzz/snapzy/install_button@2x.png?v=1.1" height="64" style="height: 64px;" alt="" /></a>

<a id="shortcuts"></a>

## ショートカット

| 操作                                                    | ショートカット |
| ------------------------------------------------------- | -------------- |
| フルスクリーンショット                     | `⇧⌘3`         |
| 範囲選択スクリーンショット                               | `⇧⌘4`         |
| ↳ 手動／アプリケーションウインドウモードを切り替え（`Application Capture`） | `A`           |
| 範囲選択スクリーンショット + インライン注釈              | `⇧⌘7`         |
| スクロールスクリーンショット                           | `⇧⌘6`         |
| 画面収録（開始／停止の切り替え）                        | `⇧⌘5`         |
| 録画を一時停止／再開（任意、推奨は `⌘⇧Space`）         | _未設定_      |
| OCRテキストキャプチャ                                 | `⇧⌘2`         |
| オブジェクト切り抜きキャプチャ                         | `⇧⌘1`         |
| スマート要素キャプチャ                                 | `⌥⇧4`         |
| 画面注釈を開く                                        | `⇧⌘A`         |
| ビデオエディターを開く                                    | `⇧⌘E`         |
| クラウドアップロード画面を開く                                   | `⇧⌘L`         |
| ショートカット一覧を表示                               | `⇧⌘K`         |

### クイックアクセスカードの操作

クイックアクセスカードにカーソルを重ねてキーを押します。ポインタがカード上にある間のみ有効です。

| 操作 | ショートカット |
| ---- | -------------- |
| コピー | `⌘C` |
| 保存 / 開く | `⌘S` |
| 編集 | `⌘E` |
| クラウドにアップロード | `⌘U` |
| 画面にピン留め | `⌘P` |
| 削除 | `⌘⌫` |
| 閉じる | `⌘W` |

<a id="automation"></a>

## 自動化

Snapzyは `snapzy://` URL schemeを登録しているため、ランチャーや自動化ツール（[Raycast Extension](https://www.raycast.com/chkzz/snapzy)、Alfred、カスタムスクリプトなど）からキャプチャ操作を起動できます。この連携は **Settings -> Advanced -> URL Scheme integration** でオン／オフを切り替えられます。

| 操作                            | URL                               |
| ------------------------------- | --------------------------------- |
| フルスクリーンショット | `snapzy://capture/fullscreen`     |
| 範囲選択スクリーンショット       | `snapzy://capture/area`           |
| アプリケーションウインドウキャプチャ    | `snapzy://capture/application`    |
| アクティブウインドウのキャプチャ           | `snapzy://capture/active-window`  |
| 選択範囲への注釈                    | `snapzy://capture/area-annotate`  |
| スクロールスクリーンショット   | `snapzy://capture/scrolling`      |
| OCRテキストキャプチャ          | `snapzy://capture/ocr`            |
| スマート要素選択キャプチャ          | `snapzy://capture/smart-element`  |
| オブジェクト切り抜きキャプチャ  | `snapzy://capture/object-cutout`  |
| 画面収録                        | `snapzy://record/screen`          |
| アプリケーションの録画          | `snapzy://record/application`     |
| 画面注釈を開く                 | `snapzy://open/annotate`          |
| 画像を結合                      | `snapzy://open/combine`           |
| ビデオエディターを開く             | `snapzy://open/video-editor`      |
| クラウドアップロード画面を開く            | `snapzy://open/cloud-uploads`     |
| キャプチャ履歴を開く            | `snapzy://open/history`           |
| ショートカット一覧を表示        | `snapzy://show/shortcuts`         |
| 設定画面を開く                 | `snapzy://settings`               |
| Settingsのタブを開く           | `snapzy://settings?tab=annotate`  |

`snapzy://open/combine` は画像ピッカーを開きます。自動化ツールは、URLエンコードしたローカルパスを `file` パラメータとして2つ以上繰り返し指定することで、ピッカーをスキップできます。

```bash
open 'snapzy://open/combine?file=/tmp/first.png&file=/tmp/second.png'
```

<a id="development"></a>

## 開発

ローカルセットアップ、ソースビルド、初回の開発ワークフローは [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) から始めてください。

archive、export、DMG パッケージングのコマンドが必要な場合は [docs/BUILD.md](docs/BUILD.md) を参照してください。コントリビュートのワークフローは [CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。

<a id="documentation"></a>

## ドキュメント

- [DeepWiki に質問（対話型ドキュメントアシスタント）](https://deepwiki.com/duongductrong/Snapzy)
- [人間とエージェント向けのドキュメントマップ](docs/README.md)
- [プロジェクト構造とランタイムアーキテクチャ](docs/STRUCTURE.md)
- [アプリのライフサイクル、オンボーディング、メニューバー](docs/APP_LIFECYCLE.md)
- キャプチャ: [スクリーンショットフロー](docs/CAPTURE.md) · [スクロールキャプチャ](docs/SCROLLING_CAPTURE.md) · [録画](docs/RECORDING.md) · [キャプチャ後の振り分け](docs/POST_CAPTURE.md)
- エディタ: [Quick Access](docs/QUICK_ACCESS.md) · [キャプチャ履歴](docs/HISTORY.md) · [Annotate](docs/ANNOTATE.md) · [Video Editor](docs/VIDEO_EDITOR.md)
- プラットフォーム: [クラウドアップロード](docs/CLOUD.md) · [ショートカットと URL scheme](docs/SHORTCUTS.md) · [設定リファレンス](docs/PREFERENCES.md) · [アップデートと診断](docs/UPDATES.md)
- [TOML 設定のエクスポート／インポート](docs/CONFIGURATION.md)
- [ビルドとパッケージングガイド](docs/BUILD.md)
- [リリースとアップデートのワークフロー](docs/RELEASES.md)
- [ローカル Sparkle アップデートテスト](docs/UPDATE_TESTING.md)

<a id="community"></a>

## コミュニティ

- サポート、フィードバック、議論は公式Snapzy Discordコミュニティへ参加してください: [https://discord.gg/xkWDAuJkZu](https://discord.gg/xkWDAuJkZu)

<a id="featured-on"></a>

## 掲載実績

<p>
  <a href="https://www.producthunt.com/products/snapzy?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-snapzy" target="_blank" rel="noopener noreferrer"><img alt="Snapzy - CleanShot X を思わせる、オープンソースで開発者に優しいアプリ | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1097629&amp;theme=light&amp;t=1773585048784"></a>
  <a href="https://unikorn.vn/p/snapzy?ref=embed-snapzy" target="_blank"><img src="https://unikorn.vn/api/widgets/badge/snapzy?theme=light" alt="Unikorn.vnで紹介されたSnapzy" style="width: 250px; height: 54px;" width="250" height="54" /></a>
</p>

## ベンチマーク

### OCR

ベンチマーク日: 2026年4月19日。現在の OCR 数値は、クリーンな合成の折り返し済み UI／記事テキストコーパスに対して、`10 supported languages` 全体で `12 samples / language` を用い、`scripts/run-ocr-readme-benchmark.sh` から実行したものです。`Character accuracy` が主要な指標で、`exact match` は意図的に厳格に判定しています。このコーパスでの `no-output` は、下表のすべての言語で `0%` です。

| 言語                | Character Accuracy | Exact Match |
| ------------------- | -----------------: | ----------: |
| English             |             100.0% |      100.0% |
| Vietnamese          |             100.0% |      100.0% |
| Simplified Chinese  |              99.3% |       75.0% |
| Traditional Chinese |              99.0% |       66.7% |
| Spanish             |              99.9% |       91.7% |
| Japanese            |              99.4% |       66.7% |
| Korean              |              99.7% |       83.3% |
| Russian             |             100.0% |      100.0% |
| French              |              99.3% |       33.3% |
| German              |              99.8% |       75.0% |

実際のスクリーンショットでは、特に絵文字、低コントラストのフッター、一般的でない句読点、グラデーション、ぼかし、装飾的なフォントが含まれる場合に、この数値より低くなることがあります。

<a id="security"></a>

## セキュリティ

Snapzy は最小限の entitlement で macOS App Sandbox 内で動作します。ネットワーク要求は Sparkle のアップデート確認、ローカルループバックの OAuth コールバックリダイレクト、そして **あなた自身の** クラウドストレージ（AWS S3、Cloudflare R2、Google Drive）へのユーザー主導のクラウドアップロードに限られ、データがサードパーティサーバーへ送信されることはありません。クラウド認証情報と OAuth トークンは macOS Keychain のみに保存され、任意のパスワードでさらに保護できます（SHA-256 でハッシュ化され、平文では決して保存されません）。認証情報は、ユーザーが指定したアーカイブパスフレーズで保護された手動の暗号化エクスポート／インポートフローを介してのみ転送できます。Snapzy はテレメトリーを収集しません。

脆弱性の報告には [GitHub Security Advisory](https://github.com/duongductrong/Snapzy/security/advisories/new) を使うか、メンテナーへ非公開で連絡してください。詳細は [SECURITY.md](SECURITY.md) を参照してください。

<a id="contributing"></a>

## コントリビュート

コントリビューションを歓迎します。プルリクエストを開く前に [CONTRIBUTING.md](CONTRIBUTING.md) を読んでください。

<a id="contributors"></a>

## 貢献者

Snapzy に貢献してくださるすべての方々に感謝します！

<a href="https://github.com/duongductrong/Snapzy/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=duongductrong/Snapzy" />
</a>

## スターの履歴

<a href="https://www.star-history.com/?repos=duongductrong%2FSnapzy&type=date&logscale=&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&theme=dark&logscale&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&logscale&legend=top-left" />
   <img alt="スター履歴グラフ" src="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&logscale&legend=top-left" />
 </picture>
</a>

<a id="acknowledgments"></a>

## 謝辞

Snapzy は、macOS 向けの高度なスクリーンショットおよび画面収録アプリケーションである [CleanShot X](https://cleanshot.com/) に着想を得ています。

## ライセンス

BSD 3-Clause License。詳細は [LICENSE](LICENSE) を参照してください。
