<div align="center">
  <img src="./banner.png" width="200" height="200" alt="Snapzy banner" />

  <h1>Snapzy</h1>
  <p><strong>Native macOS screenshots, recording, annotation, and editing from the menu bar.</strong></p>

  <p>
    <a href="https://trendshift.io/repositories/24550" target="_blank"><img src="https://trendshift.io/api/badge/repositories/24550" alt="duongductrong%2FSnapzy | Trendshift" style="width: 250px; height: 55px;" width="250" height="55"/></a>
  </p>

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
    <a href="./README.zh-CN.md">🇨🇳 简体中文</a> •
    <a href="./README.ja.md">🇯🇵 日本語</a>
  </p>

  <p>
    <a href="#features">Features</a> •
    <a href="#install">Install</a> •
    <a href="#raycast">Raycast</a> •
    <a href="#shortcuts">Shortcuts</a> •
    <a href="#development">Development</a> •
    <a href="#documentation">Documentation</a> •
    <a href="#community">Community</a> •
    <a href="#security">Security</a> •
    <a href="#contributing">Contributing</a> •
    <a href="#contributors">Contributors</a> •
    <a href="#acknowledgments">Acknowledgments</a>
  </p>

  <p>
    <a href="https://github.com/duongductrong/Snapzy/stargazers"><img alt="GitHub Stars" src="https://img.shields.io/github/stars/duongductrong/Snapzy?style=flat&amp;logo=github" /></a>
    <a href="https://github.com/duongductrong/Snapzy/network/members"><img alt="GitHub Forks" src="https://img.shields.io/github/forks/duongductrong/Snapzy?style=flat&amp;logo=github" /></a>
    <a href="https://github.com/duongductrong/Snapzy/releases"><img alt="GitHub Downloads" src="https://img.shields.io/github/downloads/duongductrong/Snapzy/total?style=flat&amp;logo=github" /></a>
  </p>
  <p>
    <a href="https://deepwiki.com/duongductrong/Snapzy"><img alt="Ask DeepWiki" src="https://deepwiki.com/badge.svg" /></a>
    <a href="https://discord.gg/xkWDAuJkZu"><img alt="Join Discord Community" src="https://img.shields.io/badge/Discord-Join%20Community-5865F2?style=flat&amp;logo=discord&amp;logoColor=white" /></a>
    <a href="https://www.raycast.com/chk/snapzy"><img alt="Raycast Extension" src="https://img.shields.io/badge/Raycast-Extension-FF6363?style=flat&amp;logo=raycast&amp;logoColor=white" /></a>
    <a href="#featured-on"><img alt="Featured On" src="https://img.shields.io/badge/Featured%20On-Product%20Hunt%20%2B%20Unikorn-111827?style=flat&amp;logo=producthunt&amp;logoColor=white" /></a>
  </p>
  <p>
    <a href="https://github.com/sponsors/duongductrong"><img alt="GitHub Sponsors" src="https://img.shields.io/badge/Sponsor-%E2%9D%A4-ff69b4?style=flat&amp;logo=github" /></a>
    <a href="https://ko-fi.com/duongductrong"><img alt="Ko-fi Donate" src="https://img.shields.io/badge/Ko--fi-Donate-FF5E5B?style=flat&amp;logo=ko-fi&amp;logoColor=white" /></a>
  </p>
</div>

## Features

- **Screenshot**: fullscreen or selected-area capture with manual/application window mode toggle (`Application Capture`, default `A`), including already open third-party menu-bar popovers that would normally close when capture begins (restored visually for selection and saved with transparent rounded corners), area capture with inline annotate (annotate before saving), scrolling capture with live stitched preview, OCR text extraction with Apple Vision or custom OpenAI-compatible endpoints and a native result notification, transparent object cutout capture with optional safe auto-crop, window shadow capture (macOS 14+), multi-format export (PNG/JPG/WebP), hide desktop icons/widgets, quick screenshot during recording
- **Screen Recording**: video or GIF output, system audio + microphone, mouse click highlights, keystroke overlays, live on-screen annotations, remember last area, GIF resizing, Smart Camera metadata for Follow Mouse edits
- **Annotation Editor**: shapes, arrows, text, watermarks, filled rectangles, blur/pixelate, automatic local sensitive-data redaction, OCR text extraction from the image context menu, counters, highlighter with text snapping (⌘ to bypass), crop with edge-snapping (⌘ to bypass) and one-key auto-crop to content (`A`), remove background with crop-aware auto-crop support, mockup backgrounds with 3D renderer, zoom/pan (pinch + keyboard), drag-to-app with optional keep-editing and editor reactivation behavior, configurable tool/action shortcuts
- **After Capture Settings**: per-mode action matrix for save, Quick Access, clipboard copy, and annotate plus a separate global remove-background auto-crop toggle (enabled by default)
- **Video Editor**: trim with visual timeline + frame strip, zoom segments with auto-focus (Follow Mouse), wallpaper backgrounds + padding, custom export dimensions, animated GIF viewer, undo/redo
- **Quick Access**: floating panel after every capture with copy, edit, drag-to-app, two-finger swipe dismiss, open, and delete actions
- **Capture History**: floating history panel + full browser for recent screenshots, videos, and GIFs with type/time filters, filename search, quick copy/open/delete actions, one-click reopen in Annotate or Video Editor, editable annotation restore for committed screenshot edits, configurable panel layout, and retention policies
- **Shortcuts**: fully configurable global shortcuts for capture, recording, and annotation tools, with per-shortcut on/off control and system conflict detection
- **Onboarding**: splash screen, first-run language selection, guided permissions setup, and shortcut configuration for first-time users
- **Localization**: 🇺🇸 English, 🇻🇳 Vietnamese, 🇨🇳 Simplified Chinese, 🇹🇼 Traditional Chinese, 🇪🇸 Spanish, 🇯🇵 Japanese, 🇰🇷 Korean, 🇷🇺 Russian, 🇫🇷 French, and 🇩🇪 German app localization with native macOS per-app language support
- **Cloud Upload**: privacy-first bring-your-own-storage via AWS S3 or Cloudflare R2 — no third-party servers, manual upload from Quick Access for screenshots, videos, and GIFs, or from Annotate for screenshots, credentials stored in the macOS Keychain with optional password protection, manual encrypted credential import/export for faster setup on another Mac, upload history, configurable auto-expiration (1–90 days or permanent), lifecycle rules, custom domain support
- **Advanced Settings**: TOML export/import, one-time config folder grant, debounced background sync, safe sync-before-open, and launch-time auto-apply for portable preferences, dotfiles, backup, and machine-to-machine setup via `~/.config/snapzy/config.toml`
- **Updates & Diagnostics**: in-app updates via Sparkle, problem reporting with diagnostic log bundles, cache management
- **Platform**: menu-bar app, appearance theming (light/dark/system), App Sandbox with secure file-access bookmarks

## Install

> Requires **macOS 13.0** or later.

### Homebrew

```bash
brew install --cask snapzy
```

### Shell script

```bash
# Install a specific version
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/v1.30.1/install.sh | bash
```

### Download a release

1. Go to [Releases](https://github.com/duongductrong/Snapzy/releases)
2. Download the latest packaged app asset, typically `Snapzy-v<version>.dmg`
3. Move `Snapzy.app` to `/Applications`
4. Launch Snapzy
5. Grant Screen Recording permission when prompted in System Settings
6. Re-launch Snapzy after granting Screen Recording if macOS asks for it
7. Grant Microphone permission too if you want voice input in recordings

> Snapzy is signed and notarized by Apple. macOS will open it without any extra steps.

## Uninstall

To completely remove Snapzy, reset all permissions, and clean up app data:

```bash
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/master/uninstall.sh | bash
```

Or if you cloned the repo:

```bash
./uninstall.sh
```

This will remove the app from `/Applications`, delete preferences and caches, and reset TCC permissions (Screen Recording, Microphone, Accessibility). You may need to log out or reboot for permission changes to fully take effect.

### Reset Permissions

If you only want to reset TCC permissions (Screen Recording, Microphone, Accessibility) without uninstalling the app:

```bash
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/master/reset-permissions.sh | bash
```

Or if you cloned the repo:

```bash
./reset-permissions.sh
```

## Raycast

Control Snapzy directly from Raycast using the official extension:

<a href="https://www.raycast.com/chkzz/snapzy" title="Install snapzy Raycast Extension"><img src="https://www.raycast.com/chkzz/snapzy/install_button@2x.png?v=1.1" height="64" style="height: 64px;" alt="" /></a>

## Shortcuts

| Action                                                  | Shortcut |
| ------------------------------------------------------- | -------- |
| Fullscreen screenshot                                   | `⇧⌘3`    |
| Area screenshot                                         | `⇧⌘4`    |
| ↳ Toggle manual/app window mode (`Application Capture`) | `A`      |
| Area screenshot + inline annotate                       | `⇧⌘7`    |
| Scrolling screenshot                                    | `⇧⌘6`    |
| Screen recording (start/stop toggle)                    | `⇧⌘5`    |
| Pause/Resume recording (optional, recommended `⌘⇧Space`) | _unset_  |
| OCR text capture                                        | `⇧⌘2`    |
| Object cutout capture                                   | `⇧⌘1`    |
| Smart element capture                                   | `⌥⇧4`    |
| Open Annotate                                           | `⇧⌘A`    |
| Open Video Editor                                       | `⇧⌘E`    |
| Open Cloud Uploads                                      | `⇧⌘L`    |
| Show shortcuts list                                     | `⇧⌘K`    |

## Automation

Snapzy registers the `snapzy://` URL scheme so launchers and automation tools (such as the [Raycast Extension](https://www.raycast.com/chk/snapzy), Alfred, or custom scripts) can trigger capture actions. This integration can be toggled on or off under **Settings -> Advanced -> URL Scheme integration**.

| Action                | URL                               |
| --------------------- | --------------------------------- |
| Fullscreen screenshot | `snapzy://capture/fullscreen`     |
| Area screenshot       | `snapzy://capture/area`           |
| Application window    | `snapzy://capture/application`    |
| Active window         | `snapzy://capture/active-window`  |
| Area annotate         | `snapzy://capture/area-annotate`  |
| Scrolling screenshot  | `snapzy://capture/scrolling`      |
| OCR text capture      | `snapzy://capture/ocr`            |
| Smart element capture | `snapzy://capture/smart-element`  |
| Object cutout capture | `snapzy://capture/object-cutout`  |
| Screen recording      | `snapzy://record/screen`          |
| Application recording | `snapzy://record/application`     |
| Open Annotate         | `snapzy://open/annotate`          |
| Combine images        | `snapzy://open/combine`           |
| Open Video Editor     | `snapzy://open/video-editor`      |
| Open Cloud Uploads    | `snapzy://open/cloud-uploads`     |
| Open Capture History  | `snapzy://open/history`           |
| Show shortcuts list   | `snapzy://show/shortcuts`         |
| Open Settings         | `snapzy://settings`               |
| Open Settings tab     | `snapzy://settings?tab=annotate`  |

`snapzy://open/combine` opens the image picker. Automation tools can skip the
picker by passing two or more URL-encoded local paths as repeated `file`
parameters:

```bash
open 'snapzy://open/combine?file=/tmp/first.png&file=/tmp/second.png'
```

## Development

For local setup, source builds, and first-time development workflow, start with [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

If you need archive, export, or DMG packaging commands, see [docs/BUILD.md](docs/BUILD.md). If you want the contribution workflow, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Documentation

- [Ask DeepWiki (interactive docs assistant)](https://deepwiki.com/duongductrong/Snapzy)
- [Docs map for humans and agents](docs/README.md)
- [Project structure and runtime architecture](docs/STRUCTURE.md)
- [App lifecycle, onboarding, and menu bar](docs/APP_LIFECYCLE.md)
- Capture: [screenshot flows](docs/CAPTURE.md) · [scrolling capture](docs/SCROLLING_CAPTURE.md) · [recording](docs/RECORDING.md) · [post-capture routing](docs/POST_CAPTURE.md)
- Editors: [Quick Access](docs/QUICK_ACCESS.md) · [capture history](docs/HISTORY.md) · [Annotate](docs/ANNOTATE.md) · [Video Editor](docs/VIDEO_EDITOR.md)
- Platform: [cloud upload](docs/CLOUD.md) · [shortcuts & URL scheme](docs/SHORTCUTS.md) · [settings reference](docs/PREFERENCES.md) · [updates & diagnostics](docs/UPDATES.md)
- [TOML configuration export/import](docs/CONFIGURATION.md)
- [Build and packaging guide](docs/BUILD.md)
- [Release and update workflow](docs/RELEASES.md)
- [Local Sparkle update testing](docs/UPDATE_TESTING.md)

## Community

- Join the Snapzy Discord community for support, feedback, and discussion: [https://discord.gg/xkWDAuJkZu](https://discord.gg/xkWDAuJkZu)

## Featured On

<p>
  <a href="https://www.producthunt.com/products/snapzy?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-snapzy" target="_blank" rel="noopener noreferrer"><img alt="Snapzy - Think CleanShot X, but open-source and developer-friendly | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1097629&amp;theme=light&amp;t=1773585048784"></a>
  <a href="https://unikorn.vn/p/snapzy?ref=embed-snapzy" target="_blank"><img src="https://unikorn.vn/api/widgets/badge/snapzy?theme=light" alt="Snapzy trên Unikorn.vn" style="width: 250px; height: 54px;" width="250" height="54" /></a>
</p>

## Benchmark

### OCR

Benchmark date: April 19, 2026. Current OCR numbers come from `scripts/run-ocr-readme-benchmark.sh` on a clean synthetic wrapped UI/article-text corpus with `12 samples / language` across `10 supported languages`. `Character accuracy` is the primary signal, `exact match` is intentionally strict, and `no-output` on this corpus is `0%` for all languages below.

| Language            | Character Accuracy | Exact Match |
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

Real-world screenshots can score lower, especially with emoji, low-contrast footers, unusual punctuation, gradients, blur, or decorative fonts.

## Security

Snapzy runs inside the macOS App Sandbox with minimal entitlements. Network requests are limited to Sparkle update checks, local loopback OAuth callback redirection, user-initiated cloud uploads to **your own** cloud storage (AWS S3, Cloudflare R2, or Google Drive), and optional user-initiated OCR model downloads from HTTPS/Hugging Face sources the user explicitly defines. Snapzy bundles no OCR models and its model catalog ships empty, so no model is referenced or fetched unless you add one. Model manifests are validated locally and importing metadata performs no download. The default built-in OCR engine runs entirely on-device; if you explicitly add a custom OCR endpoint in Settings, OCR requests (including the captured image) go to that endpoint. Cloud credentials and OAuth tokens are stored exclusively in the macOS Keychain, can be further protected with an optional password (SHA-256 hashed, never stored in plaintext), and can only be transferred via a manual encrypted export/import flow protected by a user-supplied archive passphrase. Custom OCR endpoint API keys are likewise stored only in the macOS Keychain and are never included in config or credential exports. Snapzy collects no telemetry.

To report a vulnerability, please use a [GitHub Security Advisory](https://github.com/duongductrong/Snapzy/security/advisories/new) or contact the maintainer privately. See [SECURITY.md](SECURITY.md) for full details.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## Contributors

Thanks to all the people who contribute to Snapzy!

<a href="https://github.com/duongductrong/Snapzy/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=duongductrong/Snapzy" />
</a>

## Star History

<a href="https://www.star-history.com/?repos=duongductrong%2FSnapzy&type=date&logscale=&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&theme=dark&logscale&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&logscale&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&logscale&legend=top-left" />
 </picture>
</a>

## Acknowledgments

Snapzy is inspired by [CleanShot X](https://cleanshot.com/), an advanced screenshot and screen recording application for macOS.

## License

BSD 3-Clause License. See [LICENSE](LICENSE).
