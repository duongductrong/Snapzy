<div align="center">
  <img src="./banner.png" width="200" height="200" alt="Snapzy バナー" />

  <h1>Snapzy</h1>
  <p><strong>メニューバーから使える、macOS ネイティブのスクリーンショット・画面収録・注釈・編集アプリ</strong></p>

  <p>
    <a href="https://trendshift.io/repositories/24550" target="_blank"><img src="https://trendshift.io/api/badge/repositories/24550" alt="duongductrong%2FSnapzy | Trendshift" style="width: 250px; height: 55px;" width="250" height="55"/></a>
  </p>

  <p>
    <a href="https://developer.apple.com/xcode/swiftui/">SwiftUI</a>、
    <a href="https://developer.apple.com/documentation/appkit">AppKit</a>、
    <a href="https://developer.apple.com/documentation/screencapturekit">ScreenCaptureKit</a>、
    <a href="https://developer.apple.com/documentation/vision">Vision</a>、
    <a href="https://sparkle-project.org/">Sparkle</a> で構築されています。
  </p>

  <p>
    <a href="./README.md">🇺🇸 English</a> •
    <a href="./README.vi.md">🇻🇳 Tiếng Việt</a> •
    <a href="./README.zh-CN.md">🇨🇳 简体中文</a> •
    <a href="./README.ja.md">🇯🇵 日本語</a>
  </p>

  <p>
    <a href="#install">インストール</a> •
    <a href="#uninstall">アンインストール</a> •
    <a href="#quick-start">クイックスタート</a> •
    <a href="#what-snapzy-can-do">Snapzy でできること</a> •
    <a href="#shortcuts">ショートカット</a> •
    <a href="#quick-access-card-actions">クイックアクセスカードの操作</a> •
    <a href="#command-line-tools">コマンドラインツール</a> •
    <a href="#automation">自動化</a> •
    <a href="#security-and-privacy">セキュリティとプライバシー</a> •
    <a href="#more-details">詳細ドキュメント</a> •
    <a href="#contributing">コントリビュート</a> •
    <a href="#contributors">コントリビューター</a> •
    <a href="#featured-on">掲載実績</a> •
    <a href="#star-history">Star 履歴</a> •
    <a href="#acknowledgments">謝辞</a> •
    <a href="#license">ライセンス</a>
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
    <a href="https://ko-fi.com/duongductrong"><img alt="Ko-fi で支援" src="https://img.shields.io/badge/Ko--fi-Donate-FF5E5B?style=flat&amp;logo=ko-fi&amp;logoColor=white" /></a>
  </p>
</div>

Snapzy は、スクリーンショット、画面収録、注釈、編集をこなす macOS ネイティブのメニューバーアプリです。macOS 13.0 以降が必要です。

<a id="install"></a>

## インストール

~~~bash
brew install --cask snapzy
~~~

特定のバージョンをインストールする場合：

~~~bash
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/v2.1.0/install.sh | bash
~~~

[リリースページ](https://github.com/duongductrong/Snapzy/releases)からダウンロードすることもできます。Snapzy.app を /Applications（アプリケーションフォルダ）に移動して起動し、求められたら「画面収録」の権限を許可してください。macOS から求められた場合は、アプリを再起動してください。マイクとカメラの権限は、それぞれを録画の入力として使う場合にのみ必要です。Snapzy は署名済みで、Apple による公証を受けています。

<a id="uninstall"></a>

## アンインストール

~~~bash
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/master/uninstall.sh | bash
~~~

アンインストール中に、Application Support フォルダを削除するかどうかをスクリプトが確認します。このフォルダには一時的なキャプチャや録画が含まれている場合があります。フォルダを残す場合は n と答えてください。アンインストールせずに権限だけをリセットするには、次を実行します：

~~~bash
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/master/reset-permissions.sh | bash
~~~

<a id="quick-start"></a>

## クイックスタート

1. ⇧⌘4 で範囲を、⇧⌘3 で全画面をキャプチャします。
2. クイックアクセス（Quick Access）カードから、結果のコピー、注釈、編集、ドラッグ、アップロードができます。
3. 履歴（History）を開くと、最近のスクリーンショット、ビデオ、GIF を探して再利用できます。

<a id="what-snapzy-can-do"></a>

## Snapzy でできること

- **キャプチャ**
  - 全画面、選択範囲、アプリのウィンドウ、またはスマート要素（Smart Element）をキャプチャできます。開いているサードパーティ製メニューバーのポップオーバーもキャプチャでき、スクロールするコンテンツはライブプレビューを見ながら 1 枚の画像に結合できます。
  - 内蔵の Apple Vision OCR、または設定した OpenAI 互換エンドポイントでテキストを抽出できます。ライブルーペでピクセルの色を取得し、HEX、RGB、HSL、HSB、CMYK、OKLCH、SwiftUI 形式でコピーできます。被写体の切り抜きにも対応し、安全な自動トリミングも選べます。
- **画面収録**
  - 画面全体またはアプリをビデオとして収録できます。システムオーディオとマイク入力も任意で含められ、GIF として保存することもできます。
  - カメラオーバーレイ（iPhone の連係カメラにも対応）、マウスクリックとキー入力のハイライト、画面上でのライブ注釈を追加できます。
- **注釈と編集**
  - 矢印、図形、テキスト、透かし、ぼかし、ピクセル化を追加できます。機密データはデバイス上で検出してマスクできます。
  - 画像のトリミング、背景の削除、3D モックアップの作成ができます。ビデオのカット、ズーム区間や速度変更区間の追加、「マウスに追従」（Follow Mouse）によるカーソルの追尾にも対応しています。
- **クイックアクセスと履歴**
  - フローティング表示されるクイックアクセスカードから、キャプチャのコピー、編集、ドラッグ、アップロードができます。スクリーンショットを画面にピン留めすることもできます。
  - スクリーンショット、ビデオ、GIF をファイル名・種類・日時で検索し、エディタで開き直せます。
- **クラウドアップロード**
  - クイックアクセス、注釈（Annotate）、ビデオエディタ（Video Editor）、履歴から、AWS S3、Cloudflare R2、Google Drive へ手動でアップロードできます。
  - ファイルは選択したプロバイダーに直接アップロードされます。キャプチャ後の自動アップロードは行わず、Snapzy 独自のサーバーを経由することもありません。
- **アプリの言語**: macOS ネイティブのアプリ別言語設定に対応し、英語、ベトナム語、簡体字中国語、繁体字中国語、スペイン語、日本語、韓国語、ロシア語、フランス語、ドイツ語の 10 言語を利用できます。

<a id="shortcuts"></a>

## ショートカット

| 操作                                                       | ショートカット |
| ---------------------------------------------------------- | -------------- |
| 全画面キャプチャ                                           | `⇧⌘3`          |
| 領域キャプチャ                                             | `⇧⌘4`          |
| ↳ 手動選択／アプリウィンドウモードの切り替え（`Application Capture`） | `A` |
| 同じ領域を再撮影                                           | `⌃⌘⇧4`         |
| マークアップキャプチャ（範囲を選択してその場で注釈）       | `⇧⌘7`          |
| アクティブウィンドウを撮影                                 | `⇧⌘9`          |
| スクロールキャプチャ                                       | `⇧⌘6`          |
| 画面収録（開始／停止の切り替え）                           | `⇧⌘5`          |
| 録画の一時停止／再開（任意、推奨 `⌘⇧Space`）               | _未設定_       |
| テキストを抽出（OCR）                                      | `⇧⌘2`          |
| 被写体の切り抜き                                           | `⇧⌘1`          |
| スマート要素キャプチャ                                     | `⌥⇧4`          |
| 注釈を開く                                                 | `⇧⌘A`          |
| ビデオエディタを開く                                       | `⇧⌘E`          |
| クラウドアップロードを開く                                 | `⇧⌘L`          |
| ショートカットリストを表示                                 | `⇧⌘K`          |
| 履歴パネルの表示／非表示                                   | `⇧⌘H`          |

<a id="quick-access-card-actions"></a>

## クイックアクセスカードの操作

クイックアクセスカードにポインタを重ねてから、キーを押します。ポインタがカードの上にあるときだけ有効です。

| 操作 | ショートカット |
| ---- | -------------- |
| コピー | `⌘C` |
| 保存 / 開く | `⌘S` |
| 編集 | `⌘E` |
| クラウドにアップロード | `⌘U` |
| スクリーンショットを画面にピン留め | `⌘P` |
| 削除 | `⌘⌫` |
| 閉じる | `⌘W` |

<a id="command-line-tools"></a>

## コマンドラインツール

`snapzy` ヘルパーは `/Applications/Snapzy.app/Contents/Helpers/snapzy` にあります。**設定 → コマンドライン** で **インストール** をクリックすると、`PATH` に追加できます。

アクセスは、コマンドを呼び出すアプリごとに許可します。`snapzy status` 以外のコマンドはすべて、許可済みの呼び出し元アプリからのみ実行できます。一度許可すると、そのアプリからの以降のコマンドで確認が繰り返し表示されることはありません。

~~~bash
snapzy list windows --app Safari
snapzy capture window --app Safari --max-dimension 1568 -o shot.png
snapzy capture area --rect 0,0,800,600 -o area.png
~~~

詳しくは [CLI リファレンス](docs/CLI.md) を参照してください。

<a id="automation"></a>

## 自動化

Snapzy は `snapzy://` URL スキームを登録しているため、ランチャーや自動化ツール（[Raycast 拡張機能](https://www.raycast.com/chkzz/snapzy)、Alfred、独自スクリプトなど）からキャプチャ操作を実行できます。この連携は **設定 → 詳細 → URLスキーム** でオン／オフを切り替えられます。

| 操作                         | URL                                |
| ---------------------------- | ---------------------------------- |
| 全画面キャプチャ             | `snapzy://capture/fullscreen`      |
| 領域キャプチャ               | `snapzy://capture/area`            |
| 同じ領域を再撮影             | `snapzy://capture/repeat-area`     |
| 遅延領域キャプチャ           | `snapzy://capture/delayed`         |
| アプリのウィンドウをキャプチャ | `snapzy://capture/application`   |
| アクティブウィンドウを撮影   | `snapzy://capture/active-window`   |
| マークアップキャプチャ       | `snapzy://capture/area-annotate`   |
| スクロールキャプチャ         | `snapzy://capture/scrolling`       |
| テキストを抽出（OCR）        | `snapzy://capture/ocr`             |
| スマート要素キャプチャ       | `snapzy://capture/smart-element`   |
| 被写体の切り抜き             | `snapzy://capture/object-cutout`   |
| 画面収録                     | `snapzy://record/screen`           |
| アプリ録画                   | `snapzy://record/application`      |
| 注釈を開く                   | `snapzy://open/annotate`           |
| 画像を結合                   | `snapzy://open/combine`            |
| ビデオエディタを開く         | `snapzy://open/video-editor`       |
| クラウドアップロードを開く   | `snapzy://open/cloud-uploads`      |
| キャプチャ履歴を開く         | `snapzy://open/history`            |
| カラーを取得                 | `snapzy://tools/pick-color`        |
| ショートカットリストを表示   | `snapzy://show/shortcuts`          |
| 設定を開く                   | `snapzy://settings`                |
| 設定の特定タブを開く         | `snapzy://settings?tab=annotate`   |

`snapzy://open/combine` は画像ピッカーを開きます。自動化ツールから、URL エンコードしたローカルパスを 2 つ以上、`file` パラメータを繰り返して渡すと、ピッカーを省略できます：

~~~bash
open 'snapzy://open/combine?file=/tmp/first.png&file=/tmp/second.png'
~~~

詳しくは [ショートカットと URL スキーム](docs/SHORTCUTS.md) を参照してください。

<a id="security-and-privacy"></a>

## セキュリティとプライバシー

Snapzy はサンドボックス化されておらず、起動したユーザーアカウントの権限で動作します。macOS の Hardened Runtime を有効にし、Developer ID で署名され、Apple の公証を受けています。ライブラリ検証も有効なため、Snapzy または Apple が署名したコードしか読み込まれません。キャプチャと録画はローカルに保存され、ユーザー自身の AWS S3、Cloudflare R2、Google Drive へのアップロードは、ユーザーが操作したときにのみ行われます。内蔵の OCR は Apple Vision によりデバイス上で処理されます。カスタムの OpenAI 互換 OCR エンドポイントを設定した場合は、キャプチャした画像を含む OCR リクエストがそのエンドポイントに送信されます。Snapzy はテレメトリを収集しません。

クラウドの認証情報、OAuth トークン、カスタム OCR の API キーは macOS のキーチェーンにのみ保存されます。クラウド認証情報を保護する任意のパスワードは SHA-256 でハッシュ化され、平文で保存されることはありません。クラウド認証情報は、パスフレーズで暗号化した手動のエクスポート／インポートでのみ移行でき、カスタム OCR の API キーは設定や認証情報のエクスポートに含まれません。ポータブルな TOML 設定ファイルには環境設定のみが含まれ、シークレット、キャプチャとアップロードの履歴、キャッシュ、CLI の許可情報、セキュリティスコープ付きブックマークは含まれません。ネットワークリクエストの詳細とセキュリティポリシーの全文は [SECURITY.md](SECURITY.md) を、ポータブルな設定については [設定ガイド](docs/CONFIGURATION.md) を参照してください。

脆弱性を報告する場合は、[GitHub Security Advisory](https://github.com/duongductrong/Snapzy/security/advisories/new) を利用するか、メンテナーに非公開で連絡してください。報告方法の詳細は [SECURITY.md](SECURITY.md) を参照してください。

<a id="more-details"></a>

## 詳細ドキュメント

以下の詳細ドキュメントは現在、英語版のみです。

- [キャプチャと OCR](docs/CAPTURE.md) · [スクロールキャプチャ](docs/SCROLLING_CAPTURE.md) · [画面収録](docs/RECORDING.md)
- [注釈](docs/ANNOTATE.md) · [ビデオエディタ](docs/VIDEO_EDITOR.md) · [クイックアクセス](docs/QUICK_ACCESS.md) · [履歴](docs/HISTORY.md)
- [クラウドアップロード](docs/CLOUD.md) · [ショートカットと URL スキーム](docs/SHORTCUTS.md) · [CLI](docs/CLI.md)
- [設定と環境設定](docs/CONFIGURATION.md) · [環境設定リファレンス](docs/PREFERENCES.md) · [アップデートと診断](docs/UPDATES.md)
- [開発](docs/DEVELOPMENT.md) · [ビルドとパッケージング](docs/BUILD.md) · [ドキュメントマップ](docs/README.md)
- [OCR ベンチマークの結果と手法](docs/OCR_BENCHMARK.md)

<a id="contributing"></a>

## コントリビュート

コントリビュートを歓迎します。プルリクエストを作成する前に [CONTRIBUTING.md](CONTRIBUTING.md) をお読みください。

<a id="contributors"></a>

## コントリビューター

Snapzy に貢献してくださったすべての方に感謝します！

<a href="https://github.com/duongductrong/Snapzy/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=duongductrong/Snapzy" />
</a>

<a id="featured-on"></a>

## 掲載実績

<p>
  <a href="https://www.producthunt.com/products/snapzy?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-snapzy" target="_blank" rel="noopener noreferrer"><img alt="Snapzy - Think CleanShot X, but open-source and developer-friendly | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1097629&amp;theme=light&amp;t=1773585048784"></a>
  <a href="https://unikorn.vn/p/snapzy?ref=embed-snapzy" target="_blank"><img src="https://unikorn.vn/api/widgets/badge/snapzy?theme=light" alt="Snapzy trên Unikorn.vn" style="width: 250px; height: 54px;" width="250" height="54" /></a>
</p>

<a id="star-history"></a>

## Star 履歴

<a href="https://www.star-history.com/?repos=duongductrong%2FSnapzy&type=date&logscale=&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&theme=dark&logscale&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&logscale&legend=top-left" />
   <img alt="Star 履歴グラフ" src="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&logscale&legend=top-left" />
 </picture>
</a>

<a id="acknowledgments"></a>

## 謝辞

Snapzy は、macOS 向けの高機能なスクリーンショット・画面収録アプリ [CleanShot X](https://cleanshot.com/) から着想を得ています。

<a id="license"></a>

## ライセンス

BSD 3-Clause License です。詳しくは [LICENSE](LICENSE) を参照してください。
