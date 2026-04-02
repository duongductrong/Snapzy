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
    <a href="#features">Features</a> •
    <a href="#install">Install</a> •
    <a href="#build-from-source">Build from source</a> •
    <a href="#documentation">Documentation</a> •
    <a href="#security">Security</a> •
    <a href="#contributing">Contributing</a>
  </p>

  <p>
    <a href="https://www.producthunt.com/products/snapzy?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-snapzy" target="_blank" rel="noopener noreferrer"><img alt="Snapzy - Think CleanShot X, but open-source and developer-friendly | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1097629&amp;theme=light&amp;t=1773585048784"></a>
    <a href="https://unikorn.vn/p/snapzy?ref=embed-snapzy" target="_blank"><img src="https://unikorn.vn/api/widgets/badge/snapzy?theme=light" alt="Snapzy trên Unikorn.vn" style="width: 250px; height: 54px;" width="250" height="54" /></a>
  </p>
</div>

## Features

- **Screenshot**: fullscreen or selected-area capture, OCR text extraction, transparent object cutout capture with optional safe auto-crop, window shadow capture (macOS 14+), multi-format export (PNG/JPG/WebP), hide desktop icons/widgets, quick screenshot during recording
- **Screen Recording**: video or GIF output, system audio + microphone, mouse click highlights, keystroke overlays, live on-screen annotations, remember last area, GIF resizing
- **Annotation Editor**: shapes, arrows, text, filled rectangles, blur/pixelate, counters, crop, remove background with crop-aware auto-crop support, mockup backgrounds with 3D renderer, zoom/pan (pinch + keyboard), drag-to-app, configurable tool shortcuts
- **After Capture Settings**: per-mode action matrix for screenshot/recording plus a separate global remove-background auto-crop toggle (enabled by default)
- **Video Editor**: trim with visual timeline + frame strip, zoom segments with auto-focus (Follow Mouse), wallpaper backgrounds + padding, custom export dimensions, animated GIF viewer, undo/redo
- **Quick Access**: floating panel after every capture with copy, edit, drag-to-app, open, and delete actions
- **Shortcuts**: fully configurable global shortcuts for capture, recording, and annotation tools, with per-shortcut on/off control and system conflict detection
- **Onboarding**: splash screen, guided permissions setup, and shortcut configuration for first-time users
- **Cloud Upload**: privacy-first bring-your-own-storage via AWS S3 or Cloudflare R2 — no third-party servers, credentials stored in the macOS Keychain with optional password protection, configurable auto-expiration (1–90 days or permanent), lifecycle rules, custom domain support
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
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/v1.5.1/install.sh | bash
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

## Build from source

> Requires **Xcode 15.0+** and Command Line Tools (`xcode-select --install`).

1. Clone the repository:

```bash
git clone https://github.com/duongductrong/Snapzy.git
cd Snapzy
```

2. Open the project:

```bash
open Snapzy.xcodeproj
```

3. Build and run with `Cmd+R`

You can also build from the terminal:

```bash
xcodebuild -project Snapzy.xcodeproj -scheme Snapzy -configuration Debug build
```

For release packaging details, see [docs/project-build.md](docs/project-build.md).

## Documentation

- [Project build guide](docs/project-build.md)
- [Project structure](docs/project-structure.md)
- [Release workflow](docs/project-workflow.md)

## Security

Snapzy runs inside the macOS App Sandbox with minimal entitlements. Network requests are limited to Sparkle update checks and user-initiated cloud uploads to **your own** S3/R2 bucket — no data is ever sent to third-party servers. Cloud credentials are stored exclusively in the macOS Keychain and can be further protected with an optional password (SHA-256 hashed, never stored in plaintext). Snapzy collects no telemetry.

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
