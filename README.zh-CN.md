<div align="center">
  <img src="./banner.png" width="200" height="200" alt="Snapzy 横幅" />

  <h1>Snapzy</h1>
  <p><strong>在菜单栏中完成原生 macOS 截图、录屏、标注与编辑。</strong></p>

  <p>
    Built with <a href="https://developer.apple.com/xcode/swiftui/">SwiftUI</a>,
    <a href="https://developer.apple.com/documentation/appkit">AppKit</a>,
    <a href="https://developer.apple.com/documentation/screencapturekit">ScreenCaptureKit</a>,
    <a href="https://developer.apple.com/documentation/vision">Vision</a>, and
    <a href="https://sparkle-project.org/">Sparkle</a>.
  </p>

  <p>
    <a href="./README.md">🇺🇸 English</a> •
    <a href="./README.vi.md">🇻🇳 Tiếng Việt</a> •
    <a href="./README.zh-CN.md">🇨🇳 简体中文</a>
  </p>

  <p>
    <a href="#features">功能</a> •
    <a href="#install">安装</a> •
    <a href="#shortcuts">快捷键</a> •
    <a href="#build-from-source">从源码构建</a> •
    <a href="#documentation">文档</a> •
    <a href="#community">社区</a> •
    <a href="#security">安全</a> •
    <a href="#contributing">贡献</a>
  </p>

  <p>
    <a href="https://deepwiki.com/duongductrong/Snapzy"><img alt="询问 DeepWiki" src="https://deepwiki.com/badge.svg" /></a>
    <a href="https://discord.gg/6CRdUKaC"><img alt="加入 Discord 社区" src="https://img.shields.io/badge/Discord-Join%20Community-5865F2?style=flat&amp;logo=discord&amp;logoColor=white" /></a>
    <a href="#featured-on"><img alt="已收录平台" src="https://img.shields.io/badge/Featured%20On-Product%20Hunt%20%2B%20Unikorn-111827?style=flat&amp;logo=producthunt&amp;logoColor=white" /></a>
  </p>
</div>

<a id="features"></a>

## 功能

- **截图**：支持全屏或选区截图，并可在手动选区/应用窗口模式间切换（`Application Capture`，默认 `A`）；同时支持带实时拼接预览的滚动截图、OCR 文字提取、透明背景对象抠图并可选安全自动裁剪、窗口阴影保留（macOS 14+）、多格式导出（PNG/JPG/WebP）、隐藏桌面图标/小组件，以及录屏时快速截图
- **屏幕录制**：支持视频或 GIF 导出、系统音频 + 麦克风、鼠标点击高亮、按键覆盖层、屏幕实时标注、记住上次区域、GIF 尺寸调整，以及用于 Follow Mouse 编辑的 Smart Camera 元数据
- **标注编辑器**：提供形状、箭头、文本、填充矩形、模糊/像素化、编号、裁剪、去背景与感知裁剪区域的自动裁剪、3D 渲染器模拟背景、缩放/平移（触控板捏合 + 键盘）、拖拽到其他应用，以及可配置工具快捷键
- **截图后设置**：按模式分别配置保存、Quick Access、复制到剪贴板和标注动作矩阵，并为去背景提供独立的全局自动裁剪开关（默认开启）
- **视频编辑器**：可视化时间线 + 帧条裁剪、自动聚焦的缩放片段（Follow Mouse）、壁纸背景 + 留白、自定义导出尺寸、动态图 GIF 查看器，以及撤销/重做
- **Quick Access**：每次截图后弹出的悬浮面板，提供复制、编辑、拖拽到应用、打开和删除操作
- **快捷键**：为截图、录制和标注工具提供完全可配置的全局快捷键，支持逐项启用/停用和系统冲突检测
- **引导流程**：首次使用时提供启动页、语言选择、权限引导和快捷键配置
- **本地化**：应用已提供 🇺🇸 English、🇻🇳 Vietnamese、🇨🇳 Simplified Chinese、🇹🇼 Traditional Chinese、🇪🇸 Spanish、🇯🇵 Japanese、🇰🇷 Korean、🇷🇺 Russian、🇫🇷 French 和 🇩🇪 German，并支持 macOS 原生按应用选择语言
- **云上传**：坚持隐私优先的自带存储方案，支持 AWS S3 或 Cloudflare R2，不经过第三方服务器；可从 Quick Access 或 Annotate 手动上传；凭据存储于 macOS Keychain，可选密码保护；支持手动加密导入/导出凭据，便于在另一台 Mac 上快速配置；同时提供上传历史、可配置自动过期（1–90 天或永久）、生命周期规则和自定义域名支持
- **更新与诊断**：内置 Sparkle 应用更新、崩溃报告和缓存管理
- **平台特性**：菜单栏应用、浅色/深色/跟随系统主题，以及带安全文件访问书签的 App Sandbox

<a id="install"></a>

## 安装

> 需要 **macOS 13.0** 或更高版本。

### Homebrew

```bash
brew tap duongductrong/snapzy https://github.com/duongductrong/Snapzy
brew install --cask snapzy
```

### Shell 脚本

```bash
# 安装指定版本
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/v1.7.0/install.sh | bash
```

### 下载发行版

1. 打开 [Releases](https://github.com/duongductrong/Snapzy/releases)
2. 下载最新打包应用资源，通常为 `Snapzy-v<version>.dmg`
3. 将 `Snapzy.app` 移动到 `/Applications`
4. 启动 Snapzy
5. 当 macOS 在 System Settings 中提示时，授予 Screen Recording 权限
6. 如果 macOS 提示，请在授予 Screen Recording 后重新启动 Snapzy
7. 如果你想在录屏中录制人声，也请授予 Microphone 权限

## 卸载

若要彻底移除 Snapzy、重置所有权限并清理应用数据：

```bash
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/master/uninstall.sh | bash
```

如果你已经 clone 了仓库，也可以直接运行：

```bash
./uninstall.sh
```

该脚本会从 `/Applications` 中移除应用，删除偏好设置和缓存，并重置 TCC 权限（Screen Recording、Microphone、Accessibility）。权限变更可能需要注销或重启后才会完全生效。

<a id="shortcuts"></a>

## 快捷键

| 操作                                                 | 快捷键 |
| ---------------------------------------------------- | ------ |
| 全屏截图                                             | `⇧⌘3`  |
| 选区截图                                             | `⇧⌘4`  |
| ↳ 切换手动选区/应用窗口模式（`Application Capture`） | `A`    |
| 滚动截图                                             | `⇧⌘6`  |
| 屏幕录制                                             | `⇧⌘5`  |
| OCR 文字识别                                         | `⇧⌘2`  |
| 对象抠图截图                                         | `⇧⌘1`  |
| 打开标注编辑器                                       | `⇧⌘A`  |
| 打开视频编辑器                                       | `⇧⌘E`  |
| 打开云上传                                           | `⇧⌘L`  |
| 显示快捷键列表                                       | `⇧⌘K`  |

<a id="build-from-source"></a>

## 从源码构建

> 需要 **Xcode 15.0+** 和 Command Line Tools（`xcode-select --install`）。

1. 克隆仓库：

```bash
git clone https://github.com/duongductrong/Snapzy.git
cd Snapzy
```

2. 打开项目：

```bash
open Snapzy.xcodeproj
```

3. 使用 `Cmd+R` 构建并运行

你也可以在终端中构建：

```bash
xcodebuild -project Snapzy.xcodeproj -scheme Snapzy -configuration Debug build
```

关于发行版打包的更多细节，请参阅 [docs/project-build.md](docs/project-build.md)。

<a id="documentation"></a>

## 文档

- [询问 DeepWiki（交互式文档助手）](https://deepwiki.com/duongductrong/Snapzy)
- [面向开发者和 agent 的文档索引](docs/README.md)
- [项目结构与运行时架构](docs/project-structure.md)
- [截图、录制与编辑流程](docs/capture-flow.md)
- [项目构建指南](docs/project-build.md)
- [发布与更新工作流](docs/project-workflow.md)
- [本地 Sparkle 更新测试](docs/local-update-testing.md)

<a id="community"></a>

## 社区

- 加入 Snapzy Discord 社区，获取支持、反馈与讨论：[https://discord.gg/6CRdUKaC](https://discord.gg/6CRdUKaC)

<a id="featured-on"></a>

## 收录平台

<p>
  <a href="https://www.producthunt.com/products/snapzy?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-snapzy" target="_blank" rel="noopener noreferrer"><img alt="Snapzy - 可以把它理解成更偏开发者、更开源友好的 CleanShot X | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1097629&amp;theme=light&amp;t=1773585048784"></a>
  <a href="https://unikorn.vn/p/snapzy?ref=embed-snapzy" target="_blank"><img src="https://unikorn.vn/api/widgets/badge/snapzy?theme=light" alt="Snapzy on Unikorn.vn" style="width: 250px; height: 54px;" width="250" height="54" /></a>
</p>

## Benchmark

### OCR

基准测试日期：2026 年 4 月 19 日。README 中的 OCR 数据来自可复现的 runner `scripts/ocr_readme_benchmark.swift`，测试语料为干净的合成 UI/article text 换行文本，覆盖 `10 种支持语言`，每种语言 `12 个样本`。`Character accuracy` 是主要指标，`exact match` 采用严格计算，此语料上的 `no-output` 比例在下表所有语言中均为 `0%`。

| 语言 | Character Accuracy | Exact Match |
| --- | ---: | ---: |
| English | 100.0% | 100.0% |
| Vietnamese | 100.0% | 100.0% |
| Simplified Chinese | 99.3% | 75.0% |
| Traditional Chinese | 99.0% | 66.7% |
| Spanish | 99.9% | 91.7% |
| Japanese | 99.4% | 66.7% |
| Korean | 99.7% | 83.3% |
| Russian | 100.0% | 100.0% |
| French | 99.3% | 33.3% |
| German | 99.8% | 75.0% |

真实截图中的表现可能低于这组语料，尤其是在包含 emoji、低对比度页脚、特殊标点、渐变背景、模糊效果或装饰性很强的字体时。

<a id="security"></a>

## 安全

Snapzy 在 macOS App Sandbox 中运行，仅请求最小必要 entitlement。网络请求仅用于 Sparkle 更新检查，以及用户主动发起到自己 S3/R2 bucket 的云上传，数据不会发送到第三方服务器。云凭据只保存在 macOS Keychain 中，并可额外通过可选密码保护（SHA-256 哈希，绝不以明文存储）；凭据仅能通过用户提供归档口令保护的手动加密导出/导入流程转移。Snapzy 不收集任何遥测数据。

如果你需要报告安全漏洞，请使用 [GitHub Security Advisory](https://github.com/duongductrong/Snapzy/security/advisories/new) 或私下联系维护者。完整细节见 [SECURITY.md](SECURITY.md)。

<a id="contributing"></a>

## 贡献

欢迎贡献代码。提交 pull request 前请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

## Star 历史

<a href="https://www.star-history.com/?repos=duongductrong%2FSnapzy&type=date&logscale=&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&theme=dark&logscale&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&logscale&legend=top-left" />
   <img alt="Star 历史图表" src="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&logscale&legend=top-left" />
 </picture>
</a>

## 许可证

BSD 3-Clause License。详见 [LICENSE](LICENSE)。
