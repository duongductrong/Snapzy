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
    <a href="#install">Install</a> •
    <a href="#uninstall">Uninstall</a> •
    <a href="#quick-start">Quick Start</a> •
    <a href="#what-snapzy-can-do">What Snapzy can do</a> •
    <a href="#shortcuts">Shortcuts</a> •
    <a href="#quick-access-card-actions">Quick Access card actions</a> •
    <a href="#command-line-tools">Command line tools</a> •
    <a href="#automation">Automation</a> •
    <a href="#security-and-privacy">Security and privacy</a> •
    <a href="#more-details">More details</a> •
    <a href="#contributing">Contributing</a> •
    <a href="#contributors">Contributors</a> •
    <a href="#featured-on">Featured On</a> •
    <a href="#star-history">Star History</a> •
    <a href="#acknowledgments">Acknowledgments</a> •
    <a href="#license">License</a>
  </p>

  <p>
    <a href="https://github.com/duongductrong/Snapzy/stargazers"><img alt="GitHub Stars" src="https://img.shields.io/github/stars/duongductrong/Snapzy?style=flat&amp;logo=github" /></a>
    <a href="https://github.com/duongductrong/Snapzy/network/members"><img alt="GitHub Forks" src="https://img.shields.io/github/forks/duongductrong/Snapzy?style=flat&amp;logo=github" /></a>
    <a href="https://github.com/duongductrong/Snapzy/releases"><img alt="GitHub Downloads" src="https://img.shields.io/github/downloads/duongductrong/Snapzy/total?style=flat&amp;logo=github" /></a>
  </p>
  <p>
    <a href="https://deepwiki.com/duongductrong/Snapzy"><img alt="Ask DeepWiki" src="https://deepwiki.com/badge.svg" /></a>
    <a href="https://discord.gg/xkWDAuJkZu"><img alt="Join Discord Community" src="https://img.shields.io/badge/Discord-Join%20Community-5865F2?style=flat&amp;logo=discord&amp;logoColor=white" /></a>
    <a href="https://www.raycast.com/chkzz/snapzy"><img alt="Raycast Extension" src="https://img.shields.io/badge/Raycast-Extension-FF6363?style=flat&amp;logo=raycast&amp;logoColor=white" /></a>
    <a href="#featured-on"><img alt="Featured On" src="https://img.shields.io/badge/Featured%20On-Product%20Hunt%20%2B%20Unikorn-111827?style=flat&amp;logo=producthunt&amp;logoColor=white" /></a>
  </p>
  <p>
    <a href="https://github.com/sponsors/duongductrong"><img alt="GitHub Sponsors" src="https://img.shields.io/badge/Sponsor-%E2%9D%A4-ff69b4?style=flat&amp;logo=github" /></a>
    <a href="https://ko-fi.com/duongductrong"><img alt="Ko-fi Donate" src="https://img.shields.io/badge/Ko--fi-Donate-FF5E5B?style=flat&amp;logo=ko-fi&amp;logoColor=white" /></a>
  </p>
</div>

Snapzy is a native macOS menu-bar app for screenshots, screen recording, annotation, and editing. Requires macOS 13.0 or later.

## Install

~~~bash
brew install --cask snapzy
~~~

Or install a specific version:

~~~bash
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/v2.1.0/install.sh | bash
~~~

You can also [download a release](https://github.com/duongductrong/Snapzy/releases). Move Snapzy.app to /Applications, launch it, and grant Screen Recording permission when prompted. Relaunch if macOS asks. Microphone and Camera permissions are needed only for those recording inputs. Snapzy is signed and notarized by Apple.

## Uninstall

~~~bash
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/master/uninstall.sh | bash
~~~

During uninstall, the script asks whether to delete the Application Support folder, which can contain temporary captures and recordings. Answer n to keep that folder. To reset permissions without uninstalling, use:

~~~bash
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/master/reset-permissions.sh | bash
~~~

## Quick Start

1. Press ⇧⌘4 to capture an area or ⇧⌘3 for a fullscreen screenshot.
2. Use the Quick Access card to copy, annotate, edit, drag, or upload the result.
3. Open History to find and reuse recent screenshots, videos, and GIFs.

## What Snapzy can do

- **Capture**
  - Capture the full screen, a selected area, an app window, or a Smart Element. Capture already-open third-party menu-bar popovers; stitch scrolling content into one image with a live preview.
  - Extract text with built-in Apple Vision OCR or a configured OpenAI-compatible endpoint. Pick a pixel with the live loupe and copy it as HEX, RGB, HSL, HSB, CMYK, OKLCH, or SwiftUI; cut out a subject with optional safe auto-crop.
- **Record**
  - Record the screen or an app as video with optional system audio and microphone input, or save a recording as a GIF.
  - Add a camera overlay, including iPhone Continuity Camera, mouse-click and keystroke highlights, or live annotations.
- **Annotate and edit**
  - Add arrows, shapes, text, watermarks, blur, and pixelation. Detect and redact sensitive data on-device.
  - Crop images, remove backgrounds, and create 3D mockups. Trim clips, add zoom or speed segments, and use Follow Mouse to keep the cursor in view.
- **Quick Access and History**
  - Copy, edit, drag, or upload captures from their floating Quick Access cards; pin screenshots on screen.
  - Search screenshots, videos, and GIFs by filename, type, or time, then reopen them in the editors.
- **Cloud Upload**
  - Manually upload from Quick Access, Annotate, Video Editor, or History to AWS S3, Cloudflare R2, or Google Drive.
  - Uploads go directly to the selected provider. Snapzy does not auto-upload after capture or relay files through its own servers.
- **App localization**: Native macOS per-app language support in 10 languages: English, Vietnamese, Simplified Chinese, Traditional Chinese, Spanish, Japanese, Korean, Russian, French, and German.

## Shortcuts

| Action                                                   | Shortcut |
| -------------------------------------------------------- | -------- |
| Fullscreen screenshot                                    | `⇧⌘3`    |
| Area screenshot                                          | `⇧⌘4`    |
| ↳ Toggle manual/app window mode (`Application Capture`) | `A`      |
| Repeat last area screenshot                              | `⌃⌘⇧4`   |
| Area screenshot + inline annotate                        | `⇧⌘7`    |
| Active Window Capture                                    | `⌘⇧9`    |
| Scrolling screenshot                                     | `⇧⌘6`    |
| Screen recording (start/stop toggle)                     | `⇧⌘5`    |
| Pause/Resume recording (optional, recommended `⌘⇧Space`) | _unset_  |
| OCR text capture                                         | `⇧⌘2`    |
| Object cutout capture                                    | `⇧⌘1`    |
| Smart element capture                                    | `⌥⇧4`    |
| Open Annotate                                            | `⇧⌘A`    |
| Open Video Editor                                        | `⇧⌘E`    |
| Open Cloud Uploads                                       | `⇧⌘L`    |
| Show shortcuts list                                      | `⇧⌘K`    |
| History panel toggle                                     | `⌘⇧H`    |

## Quick Access card actions

Hover a Quick Access card, then press the key. Active only while the pointer is over a card.

| Action | Shortcut |
| ------ | -------- |
| Copy | `⌘C` |
| Save / Open | `⌘S` |
| Edit | `⌘E` |
| Upload to cloud | `⌘U` |
| Pin screenshot to screen | `⌘P` |
| Delete | `⌘⌫` |
| Close | `⌘W` |

## Command line tools

The `snapzy` helper is at `/Applications/Snapzy.app/Contents/Helpers/snapzy`. Add it to your `PATH` from **Settings → Command Line → Install**.

Access is approved per calling app. All commands other than `snapzy status` require an approved caller app; after approval, that app can use later commands without repeated prompts.

~~~bash
snapzy list windows --app Safari
snapzy capture window --app Safari --max-dimension 1568 -o shot.png
snapzy capture area --rect 0,0,800,600 -o area.png
~~~

See the [CLI reference](docs/CLI.md).

## Automation

Snapzy registers the `snapzy://` URL scheme so launchers and automation tools (such as the [Raycast Extension](https://www.raycast.com/chkzz/snapzy), Alfred, or custom scripts) can trigger capture actions. This integration can be toggled on or off under **Settings → Advanced → URL Scheme integration**.

| Action                 | URL                                |
| ---------------------- | ---------------------------------- |
| Fullscreen screenshot  | `snapzy://capture/fullscreen`      |
| Area screenshot        | `snapzy://capture/area`            |
| Repeat area screenshot | `snapzy://capture/repeat-area`     |
| Delayed area screenshot | `snapzy://capture/delayed`        |
| Application window     | `snapzy://capture/application`     |
| Active window          | `snapzy://capture/active-window`   |
| Area annotate          | `snapzy://capture/area-annotate`   |
| Scrolling screenshot   | `snapzy://capture/scrolling`       |
| OCR text capture       | `snapzy://capture/ocr`             |
| Smart element capture  | `snapzy://capture/smart-element`   |
| Object cutout capture  | `snapzy://capture/object-cutout`   |
| Screen recording       | `snapzy://record/screen`           |
| Application recording  | `snapzy://record/application`      |
| Open Annotate          | `snapzy://open/annotate`            |
| Combine images         | `snapzy://open/combine`             |
| Open Video Editor      | `snapzy://open/video-editor`        |
| Open Cloud Uploads     | `snapzy://open/cloud-uploads`       |
| Open Capture History   | `snapzy://open/history`             |
| Pick color             | `snapzy://tools/pick-color`         |
| Show shortcuts list    | `snapzy://show/shortcuts`           |
| Open Settings          | `snapzy://settings`                 |
| Open Settings tab      | `snapzy://settings?tab=annotate`    |

`snapzy://open/combine` opens the image picker. Automation tools can skip the picker by passing two or more URL-encoded local paths as repeated `file` parameters:

~~~bash
open 'snapzy://open/combine?file=/tmp/first.png&file=/tmp/second.png'
~~~

See [Shortcuts and URL scheme](docs/SHORTCUTS.md) for details.

## Security and privacy

Snapzy is not sandboxed and runs with the privileges of the user account that launched it. It uses the macOS Hardened Runtime, Developer ID signing, and Apple notarization; library validation stays enabled so only code signed by Snapzy or Apple can load. Captures and recordings are stored locally, and users initiate uploads to their own AWS S3, Cloudflare R2, or Google Drive storage. Built-in OCR uses Apple Vision on-device; if a custom OpenAI-compatible OCR endpoint is configured, OCR requests include the captured image and are sent to that endpoint. Snapzy collects no telemetry.

Cloud credentials, OAuth tokens, and custom OCR API keys are stored exclusively in the macOS Keychain. The optional cloud-credential protection password is SHA-256 hashed and never stored in plaintext. Cloud credentials can be transferred only through a manual, passphrase-encrypted export/import, and custom OCR API keys are excluded from configuration and credential exports. The portable TOML configuration contains preferences only; it excludes secrets, capture and upload history, caches, CLI approvals, and security-scoped bookmarks. See [SECURITY.md](SECURITY.md) for network-request details and the full security policy, and the [configuration guide](docs/CONFIGURATION.md) for portable settings.

To report a vulnerability, use a [GitHub Security Advisory](https://github.com/duongductrong/Snapzy/security/advisories/new) or contact the maintainer privately. See [SECURITY.md](SECURITY.md) for reporting details.

## More details

- [Capture and OCR](docs/CAPTURE.md) · [Scrolling capture](docs/SCROLLING_CAPTURE.md) · [Recording](docs/RECORDING.md)
- [Annotate](docs/ANNOTATE.md) · [Video Editor](docs/VIDEO_EDITOR.md) · [Quick Access](docs/QUICK_ACCESS.md) · [History](docs/HISTORY.md)
- [Cloud Upload](docs/CLOUD.md) · [Shortcuts and URL scheme](docs/SHORTCUTS.md) · [CLI](docs/CLI.md)
- [Configuration and preferences](docs/CONFIGURATION.md) · [Preferences reference](docs/PREFERENCES.md) · [Updates and diagnostics](docs/UPDATES.md)
- [Development](docs/DEVELOPMENT.md) · [Build and packaging](docs/BUILD.md) · [Docs map](docs/README.md)
- [OCR benchmark results and methodology](docs/OCR_BENCHMARK.md)

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## Contributors

Thanks to all the people who contribute to Snapzy!

<a href="https://github.com/duongductrong/Snapzy/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=duongductrong/Snapzy" />
</a>

## Featured On

<p>
  <a href="https://www.producthunt.com/products/snapzy?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-snapzy" target="_blank" rel="noopener noreferrer"><img alt="Snapzy - Think CleanShot X, but open-source and developer-friendly | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1097629&amp;theme=light&amp;t=1773585048784"></a>
  <a href="https://unikorn.vn/p/snapzy?ref=embed-snapzy" target="_blank"><img src="https://unikorn.vn/api/widgets/badge/snapzy?theme=light" alt="Snapzy trên Unikorn.vn" style="width: 250px; height: 54px;" width="250" height="54" /></a>
</p>

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
