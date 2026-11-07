<div align="center">
  <img src="./banner.png" width="200" height="200" alt="Snapzy 横幅" />

  <h1>Snapzy</h1>
  <p><strong>在菜单栏中完成原生 macOS 截图、录屏、标注与编辑。</strong></p>

  <p>
    <a href="https://trendshift.io/repositories/24550" target="_blank"><img src="https://trendshift.io/api/badge/repositories/24550" alt="duongductrong%2FSnapzy | Trendshift" style="width: 250px; height: 55px;" width="250" height="55"/></a>
  </p>

  <p>
    基于 <a href="https://developer.apple.com/xcode/swiftui/">SwiftUI</a>、
    <a href="https://developer.apple.com/documentation/appkit">AppKit</a>、
    <a href="https://developer.apple.com/documentation/screencapturekit">ScreenCaptureKit</a>、
    <a href="https://developer.apple.com/documentation/vision">Vision</a> 和
    <a href="https://sparkle-project.org/">Sparkle</a> 构建。
  </p>

  <p>
    <a href="./README.md">🇺🇸 English</a> •
    <a href="./README.vi.md">🇻🇳 Tiếng Việt</a> •
    <a href="./README.zh-CN.md">🇨🇳 简体中文</a> •
    <a href="./README.ja.md">🇯🇵 日本語</a>
  </p>

  <p>
    <a href="#install">安装</a> •
    <a href="#uninstall">卸载</a> •
    <a href="#quick-start">快速上手</a> •
    <a href="#what-snapzy-can-do">功能一览</a> •
    <a href="#shortcuts">快捷键</a> •
    <a href="#quick-access-card-actions">快速访问卡片操作</a> •
    <a href="#command-line-tools">命令行工具</a> •
    <a href="#automation">自动化</a> •
    <a href="#security-and-privacy">安全与隐私</a> •
    <a href="#more-details">更多文档</a> •
    <a href="#contributing">参与贡献</a> •
    <a href="#contributors">贡献者</a> •
    <a href="#featured-on">推荐与收录</a> •
    <a href="#star-history">Star 历史</a> •
    <a href="#acknowledgments">致谢</a> •
    <a href="#license">许可证</a>
  </p>

  <p>
    <a href="https://github.com/duongductrong/Snapzy/stargazers"><img alt="GitHub Stars" src="https://img.shields.io/github/stars/duongductrong/Snapzy?style=flat&amp;logo=github" /></a>
    <a href="https://github.com/duongductrong/Snapzy/network/members"><img alt="GitHub Forks" src="https://img.shields.io/github/forks/duongductrong/Snapzy?style=flat&amp;logo=github" /></a>
    <a href="https://github.com/duongductrong/Snapzy/releases"><img alt="GitHub Downloads" src="https://img.shields.io/github/downloads/duongductrong/Snapzy/total?style=flat&amp;logo=github" /></a>
  </p>
  <p>
    <a href="https://deepwiki.com/duongductrong/Snapzy"><img alt="询问 DeepWiki" src="https://deepwiki.com/badge.svg" /></a>
    <a href="https://discord.gg/xkWDAuJkZu"><img alt="加入 Discord 社区" src="https://img.shields.io/badge/Discord-Join%20Community-5865F2?style=flat&amp;logo=discord&amp;logoColor=white" /></a>
    <a href="https://www.raycast.com/chkzz/snapzy"><img alt="Raycast 扩展" src="https://img.shields.io/badge/Raycast-Extension-FF6363?style=flat&amp;logo=raycast&amp;logoColor=white" /></a>
    <a href="#featured-on"><img alt="推荐与收录" src="https://img.shields.io/badge/Featured%20On-Product%20Hunt%20%2B%20Unikorn-111827?style=flat&amp;logo=producthunt&amp;logoColor=white" /></a>
  </p>
  <p>
    <a href="https://github.com/sponsors/duongductrong"><img alt="GitHub Sponsors" src="https://img.shields.io/badge/Sponsor-%E2%9D%A4-ff69b4?style=flat&amp;logo=github" /></a>
    <a href="https://ko-fi.com/duongductrong"><img alt="通过 Ko-fi 赞助" src="https://img.shields.io/badge/Ko--fi-Donate-FF5E5B?style=flat&amp;logo=ko-fi&amp;logoColor=white" /></a>
  </p>
</div>

Snapzy 是一款原生 macOS 菜单栏应用，用于截图、录屏、标注和编辑。需要 macOS 13.0 或更高版本。

<a id="install"></a>

## 安装

~~~bash
brew install --cask snapzy
~~~

或安装指定版本：

~~~bash
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/v2.1.0/install.sh | bash
~~~

你也可以[下载发布版本](https://github.com/duongductrong/Snapzy/releases)。将 Snapzy.app 移到 /Applications（“应用程序”文件夹），启动后按提示授予“屏幕录制”权限。如果 macOS 要求，请重新启动 Snapzy。麦克风和摄像头权限仅在录制时使用对应输入源才需要。Snapzy 已签名并通过 Apple 公证。

<a id="uninstall"></a>

## 卸载

~~~bash
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/master/uninstall.sh | bash
~~~

卸载过程中，脚本会询问是否删除 Application Support 文件夹，其中可能包含临时截图和录屏文件。输入 n 即可保留该文件夹。如果只想重置权限而不卸载，请运行：

~~~bash
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/master/reset-permissions.sh | bash
~~~

<a id="quick-start"></a>

## 快速上手

1. 按 ⇧⌘4 截取区域，或按 ⇧⌘3 截取全屏。
2. 在快速访问（Quick Access）卡片中复制、标注、编辑、拖拽或上传截图结果。
3. 打开历史记录（History），查找并重新使用最近的截图、视频和 GIF。

<a id="what-snapzy-can-do"></a>

## 功能一览

- **截图**
  - 截取全屏、选定区域、应用窗口或界面中的智能元素（Smart Element）。可截取已打开的第三方菜单栏弹出窗口；也可将滚动内容拼接成一张长图，并实时预览。
  - 使用内置的 Apple Vision OCR，或你配置的 OpenAI 兼容接口识别文字。用实时放大镜拾取像素颜色，并复制为 HEX、RGB、HSL、HSB、CMYK、OKLCH 或 SwiftUI 格式；提取主体（抠图），并可选择安全自动裁剪。
  - 使用屏幕标尺（Screen Ruler）测量屏幕上的间距和尺寸：悬停在边缘之间、拖出自动贴合内容的框、固定并复制测量值，或保存绘有测量结果的截图。
- **录屏**
  - 将整个屏幕或单个应用录制为视频，可选录入系统音频和麦克风，也可保存为 GIF。
  - 添加摄像头画面（支持 iPhone 连续互通相机）、鼠标点击与按键高亮，或在屏幕上实时标注。
- **标注与编辑**
  - 添加箭头、形状、文字、水印、模糊和像素化效果。在本地检测并遮蔽敏感信息。
  - 用测量工具（`U`）测量图片中的距离和尺寸：测量结果可编辑，并随图片一起导出。
  - 裁剪图片、移除背景、制作 3D 样机展示。剪辑视频片段，添加缩放片段或变速片段，并使用“跟随鼠标”（Follow Mouse）让光标始终保持在画面中。
- **快速访问与历史记录**
  - 在悬浮的快速访问卡片上直接复制、编辑、拖拽或上传截图；将截图固定到屏幕上。
  - 按文件名、类型或时间搜索截图、视频和 GIF，并在编辑器中重新打开。
- **云端上传**
  - 从快速访问、标注（Annotate）、视频编辑器（Video Editor）或历史记录中手动上传到 AWS S3、Cloudflare R2 或 Google Drive。
  - 文件直接上传到你选择的服务商。Snapzy 不会在截图后自动上传，也不会经由自己的服务器中转文件。
- **应用语言**：支持 macOS 原生的按应用设置语言，共 10 种语言：英语、越南语、简体中文、繁体中文、西班牙语、日语、韩语、俄语、法语和德语。

<a id="shortcuts"></a>

## 快捷键

| 操作                                                    | 快捷键    |
| ------------------------------------------------------- | --------- |
| 全屏截图                                                | `⇧⌘3`     |
| 区域截屏                                                | `⇧⌘4`     |
| ↳ 切换手动选区/应用窗口模式（`Application Capture`）    | `A`       |
| 重复上次区域截图                                        | `⌃⌘⇧4`    |
| 截图并标注                                              | `⇧⌘7`     |
| 截取当前窗口                                            | `⇧⌘9`     |
| 滚动截屏                                                | `⇧⌘6`     |
| 屏幕录制（开始/停止）                                   | `⇧⌘5`     |
| 暂停/恢复录制（可选，建议设为 `⌘⇧Space`）               | _未设置_  |
| 识别文字（OCR）                                         | `⇧⌘2`     |
| 提取主体（抠图）                                        | `⇧⌘1`     |
| 智能元素截取                                            | `⌥⇧4`     |
| 测量屏幕（屏幕标尺）                                    | `⌥⇧M`     |
| 打开标注                                                | `⇧⌘A`     |
| 打开视频编辑器                                          | `⇧⌘E`     |
| 打开云端上传窗口                                        | `⇧⌘L`     |
| 显示快捷键列表                                          | `⇧⌘K`     |
| 显示/隐藏历史记录面板                                   | `⇧⌘H`     |

<a id="quick-access-card-actions"></a>

## 快速访问卡片操作

将鼠标悬停在快速访问卡片上，然后按下对应按键。仅在指针位于卡片上方时生效。

| 操作 | 快捷键 |
| ---- | ------ |
| 复制 | `⌘C` |
| 保存 / 打开 | `⌘S` |
| 编辑 | `⌘E` |
| 上传到云端 | `⌘U` |
| 将截图固定到屏幕 | `⌘P` |
| 删除 | `⌘⌫` |
| 关闭 | `⌘W` |

<a id="command-line-tools"></a>

## 命令行工具

`snapzy` 命令行工具位于 `/Applications/Snapzy.app/Contents/Helpers/snapzy`。在 **偏好设置 → 命令行** 中点击 **安装**，即可将其添加到 `PATH`。

访问权限按调用方应用分别授予。除 `snapzy status` 外，所有命令都需要调用方应用已获批准；批准后，该应用后续调用命令时不会再重复弹出提示。

~~~bash
snapzy list windows --app Safari
snapzy capture window --app Safari --max-dimension 1568 -o shot.png
snapzy capture area --rect 0,0,800,600 -o area.png
snapzy measure window --app Safari --at 24,180 --box 0,0,800,60
~~~

参见 [CLI 参考文档](docs/CLI.md)。

<a id="automation"></a>

## 自动化

Snapzy 注册了 `snapzy://` URL Scheme，启动器和自动化工具（例如 [Raycast 扩展](https://www.raycast.com/chkzz/snapzy)、Alfred 或自定义脚本）可以借此触发截图操作。你可以在 **偏好设置 → 高级 → URL Scheme 集成** 中开启或关闭此功能。

| 操作                 | URL                                |
| -------------------- | ---------------------------------- |
| 全屏截图             | `snapzy://capture/fullscreen`      |
| 区域截屏             | `snapzy://capture/area`            |
| 重复区域截图         | `snapzy://capture/repeat-area`     |
| 延迟区域截图         | `snapzy://capture/delayed`         |
| 应用窗口截屏         | `snapzy://capture/application`     |
| 截取当前窗口         | `snapzy://capture/active-window`   |
| 截图并标注           | `snapzy://capture/area-annotate`   |
| 滚动截屏             | `snapzy://capture/scrolling`       |
| 识别文字（OCR）      | `snapzy://capture/ocr`             |
| 智能元素截取         | `snapzy://capture/smart-element`   |
| 提取主体（抠图）     | `snapzy://capture/object-cutout`   |
| 屏幕录制             | `snapzy://record/screen`           |
| 应用窗口录屏         | `snapzy://record/application`      |
| 打开标注             | `snapzy://open/annotate`           |
| 拼图                 | `snapzy://open/combine`            |
| 打开视频编辑器       | `snapzy://open/video-editor`       |
| 打开云端上传窗口     | `snapzy://open/cloud-uploads`      |
| 打开截图历史记录     | `snapzy://open/history`            |
| 取色                 | `snapzy://tools/pick-color`        |
| 测量屏幕             | `snapzy://tools/measure`           |
| 显示快捷键列表       | `snapzy://show/shortcuts`          |
| 打开偏好设置         | `snapzy://settings`                |
| 打开偏好设置的指定标签页 | `snapzy://settings?tab=annotate` |

`snapzy://open/combine` 会打开图片选择器。自动化工具可通过重复传入 `file` 参数（两个或以上经过 URL 编码的本地路径）来跳过选择器：

~~~bash
open 'snapzy://open/combine?file=/tmp/first.png&file=/tmp/second.png'
~~~

详情参见 [快捷键与 URL Scheme](docs/SHORTCUTS.md)。

<a id="security-and-privacy"></a>

## 安全与隐私

Snapzy 不在沙盒中运行，而是以启动它的用户账户权限运行。它启用了 macOS 强化运行时（Hardened Runtime），使用 Developer ID 签名并通过 Apple 公证；库验证（Library Validation）保持开启，因此只能加载由 Snapzy 或 Apple 签名的代码。截图和录屏保存在本地，只有在你主动操作时才会上传到你自己的 AWS S3、Cloudflare R2 或 Google Drive。内置 OCR 使用 Apple Vision 在设备端完成；如果你配置了自定义的 OpenAI 兼容 OCR 接口，OCR 请求会包含截图图像并发送到该接口。Snapzy 不收集任何遥测数据。

云存储凭据、OAuth 令牌和自定义 OCR 的 API 密钥仅存储在 macOS 钥匙串中。可选的云存储凭据保护密码会经过 SHA-256 哈希处理，绝不会以明文保存。云存储凭据只能通过手动的、使用口令加密的导出/导入进行迁移，自定义 OCR 的 API 密钥不会包含在配置导出和凭据导出中。可移植的 TOML 配置文件只包含偏好设置，不包含敏感凭据、截图与上传历史、缓存、已批准的 CLI 调用方应用以及安全范围书签（security-scoped bookmark）。网络请求细节和完整安全策略请参见 [SECURITY.md](SECURITY.md)，可移植设置请参见 [配置指南](docs/CONFIGURATION.md)。

如需报告安全漏洞，请通过 [GitHub Security Advisory](https://github.com/duongductrong/Snapzy/security/advisories/new) 提交，或私下联系维护者。报告方式详见 [SECURITY.md](SECURITY.md)。

<a id="more-details"></a>

## 更多文档

以下详细文档目前仅提供英文版。

- [截图与 OCR](docs/CAPTURE.md) · [滚动截屏](docs/SCROLLING_CAPTURE.md) · [录屏](docs/RECORDING.md)
- [标注](docs/ANNOTATE.md) · [视频编辑器](docs/VIDEO_EDITOR.md) · [快速访问](docs/QUICK_ACCESS.md) · [历史记录](docs/HISTORY.md)
- [云端上传](docs/CLOUD.md) · [快捷键与 URL Scheme](docs/SHORTCUTS.md) · [CLI](docs/CLI.md)
- [配置与偏好设置](docs/CONFIGURATION.md) · [偏好设置参考](docs/PREFERENCES.md) · [更新与诊断](docs/UPDATES.md)
- [开发](docs/DEVELOPMENT.md) · [构建与打包](docs/BUILD.md) · [文档导航](docs/README.md)
- [OCR 基准测试结果与方法](docs/OCR_BENCHMARK.md)

<a id="contributing"></a>

## 参与贡献

欢迎贡献！提交 Pull Request 前请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

<a id="contributors"></a>

## 贡献者

感谢所有为 Snapzy 做出贡献的人！

<a href="https://github.com/duongductrong/Snapzy/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=duongductrong/Snapzy" />
</a>

<a id="featured-on"></a>

## 推荐与收录

<p>
  <a href="https://www.producthunt.com/products/snapzy?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-snapzy" target="_blank" rel="noopener noreferrer"><img alt="Snapzy - Think CleanShot X, but open-source and developer-friendly | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1097629&amp;theme=light&amp;t=1773585048784"></a>
  <a href="https://unikorn.vn/p/snapzy?ref=embed-snapzy" target="_blank"><img src="https://unikorn.vn/api/widgets/badge/snapzy?theme=light" alt="Snapzy trên Unikorn.vn" style="width: 250px; height: 54px;" width="250" height="54" /></a>
</p>

<a id="star-history"></a>

## Star 历史

<a href="https://www.star-history.com/?repos=duongductrong%2FSnapzy&type=date&logscale=&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&theme=dark&logscale&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&logscale&legend=top-left" />
   <img alt="Star 历史图表" src="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&logscale&legend=top-left" />
 </picture>
</a>

<a id="acknowledgments"></a>

## 致谢

Snapzy 的灵感来自 [CleanShot X](https://cleanshot.com/)，一款功能强大的 macOS 截图与录屏应用。

<a id="license"></a>

## 许可证

BSD 3-Clause 许可证。详见 [LICENSE](LICENSE)。
