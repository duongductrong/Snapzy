<div align="center">
  <img src="./banner.png" width="200" height="200" alt="Snapzy banner" />

  <h1>Snapzy</h1>
  <p><strong>Native macOS screenshots, recording, annotation, and editing from the menu bar.</strong></p>

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
    <a href="#features">Features</a> •
    <a href="#install">Install</a> •
    <a href="#shortcuts">Shortcuts</a> •
    <a href="#development">Development</a> •
    <a href="#documentation">Documentation</a> •
    <a href="#community">Community</a> •
    <a href="#security">Security</a> •
    <a href="#contributing">Contributing</a>
  </p>

  <p>
    <a href="https://deepwiki.com/duongductrong/Snapzy"><img alt="Ask DeepWiki" src="https://deepwiki.com/badge.svg" /></a>
    <a href="https://discord.gg/6CRdUKaC"><img alt="Join Discord Community" src="https://img.shields.io/badge/Discord-Join%20Community-5865F2?style=flat&amp;logo=discord&amp;logoColor=white" /></a>
    <a href="#featured-on"><img alt="Featured On" src="https://img.shields.io/badge/Featured%20On-Product%20Hunt%20%2B%20Unikorn-111827?style=flat&amp;logo=producthunt&amp;logoColor=white" /></a>
  </p>
</div>

## Features

- **Screenshot**: fullscreen or selected-area capture with manual/application window mode toggle (`Application Capture`, default `A`), scrolling capture with live stitched preview, OCR text extraction, transparent object cutout capture with optional safe auto-crop, window shadow capture (macOS 14+), multi-format export (PNG/JPG/WebP), hide desktop icons/widgets, quick screenshot during recording
- **Screen Recording**: video or GIF output, system audio + microphone, mouse click highlights, keystroke overlays, live on-screen annotations, remember last area, GIF resizing, Smart Camera metadata for Follow Mouse edits
- **Annotation Editor**: shapes, arrows, text, watermarks, filled rectangles, blur/pixelate, counters, crop, remove background with crop-aware auto-crop support, mockup backgrounds with 3D renderer, zoom/pan (pinch + keyboard), drag-to-app, configurable tool shortcuts
- **After Capture Settings**: per-mode action matrix for save, Quick Access, clipboard copy, and annotate plus a separate global remove-background auto-crop toggle (enabled by default)
- **Video Editor**: trim with visual timeline + frame strip, zoom segments with auto-focus (Follow Mouse), wallpaper backgrounds + padding, custom export dimensions, animated GIF viewer, undo/redo
- **Quick Access**: floating panel after every capture with copy, edit, drag-to-app, open, and delete actions
- **Capture History**: floating history panel + full browser for recent screenshots, videos, and GIFs with type/time filters, filename search, quick copy/open/delete actions, one-click reopen in Annotate or Video Editor, configurable panel layout, and retention policies
- **Shortcuts**: fully configurable global shortcuts for capture, recording, and annotation tools, with per-shortcut on/off control and system conflict detection
- **Onboarding**: splash screen, first-run language selection, guided permissions setup, and shortcut configuration for first-time users
- **Localization**: 🇺🇸 English, 🇻🇳 Vietnamese, 🇨🇳 Simplified Chinese, 🇹🇼 Traditional Chinese, 🇪🇸 Spanish, 🇯🇵 Japanese, 🇰🇷 Korean, 🇷🇺 Russian, 🇫🇷 French, and 🇩🇪 German app localization with native macOS per-app language support
- **Cloud Upload**: privacy-first bring-your-own-storage via AWS S3 or Cloudflare R2 — no third-party servers, manual upload from Quick Access for screenshots, videos, and GIFs, or from Annotate for screenshots, credentials stored in the macOS Keychain with optional password protection, manual encrypted credential import/export for faster setup on another Mac, upload history, configurable auto-expiration (1–90 days or permanent), lifecycle rules, custom domain support
- **Updates & Diagnostics**: in-app updates via Sparkle, crash reporting, cache management
- **Platform**: menu-bar app, appearance theming (light/dark/system), App Sandbox with secure file-access bookmarks

## Install

> Requires **macOS 13.0** or later.

### Homebrew

```bash
brew tap duongductrong/snapzy https://github.com/duongductrong/Snapzy
brew install --cask snapzy
```

### Shell script

```bash
# Install a specific version
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/v1.9.6/install.sh | bash
```

### Download a release

1. Go to [Releases](https://github.com/duongductrong/Snapzy/releases)
2. Download the latest packaged app asset, typically `Snapzy-v<version>.dmg`
3. Move `Snapzy.app` to `/Applications`
4. Launch Snapzy
5. Grant Screen Recording permission when prompted in System Settings
6. Re-launch Snapzy after granting Screen Recording if macOS asks for it
7. Grant Microphone permission too if you want voice input in recordings

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

## Shortcuts

| Action                                                  | Shortcut |
| ------------------------------------------------------- | -------- |
| Fullscreen screenshot                                   | `⇧⌘3`    |
| Area screenshot                                         | `⇧⌘4`    |
| ↳ Toggle manual/app window mode (`Application Capture`) | `A`      |
| Scrolling screenshot                                    | `⇧⌘6`    |
| Screen recording                                        | `⇧⌘5`    |
| OCR text capture                                        | `⇧⌘2`    |
| Object cutout capture                                   | `⇧⌘1`    |
| Open Annotate                                           | `⇧⌘A`    |
| Open Video Editor                                       | `⇧⌘E`    |
| Open Cloud Uploads                                      | `⇧⌘L`    |
| Show shortcuts list                                     | `⇧⌘K`    |

## Development

For local setup, source builds, and first-time development workflow, start with [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

If you need archive, export, or DMG packaging commands, see [docs/BUILD.md](docs/BUILD.md). If you want the contribution workflow, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Documentation

- [Ask DeepWiki (interactive docs assistant)](https://deepwiki.com/duongductrong/Snapzy)
- [Docs map for humans and agents](docs/README.md)
- [Project structure and runtime architecture](docs/STRUCTURE.md)
- [Capture, recording, and editing flows](docs/CAPTURE.md)
- [Build and packaging guide](docs/BUILD.md)
- [Release and update workflow](docs/RELEASES.md)
- [Local Sparkle update testing](docs/UPDATE_TESTING.md)

## Community

- Join the Snapzy Discord community for support, feedback, and discussion: [https://discord.gg/6CRdUKaC](https://discord.gg/6CRdUKaC)

## Featured On

<p>
  <a href="https://www.producthunt.com/products/snapzy?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-snapzy" target="_blank" rel="noopener noreferrer"><img alt="Snapzy - Think CleanShot X, but open-source and developer-friendly | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1097629&amp;theme=light&amp;t=1773585048784"></a>
  <a href="https://unikorn.vn/p/snapzy?ref=embed-snapzy" target="_blank"><img src="https://unikorn.vn/api/widgets/badge/snapzy?theme=light" alt="Snapzy trên Unikorn.vn" style="width: 250px; height: 54px;" width="250" height="54" /></a>
</p>

## Benchmark

### OCR

Benchmark date: April 19, 2026. Current OCR numbers come from `scripts/ocr_readme_benchmark.swift` on a clean synthetic wrapped UI/article-text corpus with `12 samples / language` across `10 supported languages`. `Character accuracy` is the primary signal, `exact match` is intentionally strict, and `no-output` on this corpus is `0%` for all languages below.

| Language | Character Accuracy | Exact Match |
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

Real-world screenshots can score lower, especially with emoji, low-contrast footers, unusual punctuation, gradients, blur, or decorative fonts.

## Security

Snapzy runs inside the macOS App Sandbox with minimal entitlements. Network requests are limited to Sparkle update checks and user-initiated cloud uploads to **your own** S3/R2 bucket — no data is ever sent to third-party servers. Cloud credentials are stored exclusively in the macOS Keychain, can be further protected with an optional password (SHA-256 hashed, never stored in plaintext), and can only be transferred via a manual encrypted export/import flow protected by a user-supplied archive passphrase. Snapzy collects no telemetry.

To report a vulnerability, please use a [GitHub Security Advisory](https://github.com/duongductrong/Snapzy/security/advisories/new) or contact the maintainer privately. See [SECURITY.md](SECURITY.md) for full details.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## Star History

<a href="https://www.star-history.com/?repos=duongductrong%2FSnapzy&type=date&logscale=&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&theme=dark&logscale&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&logscale&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&logscale&legend=top-left" />
 </picture>
</a>

## License

BSD 3-Clause License. See [LICENSE](LICENSE).
