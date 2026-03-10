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
    <a href="#contributing">Contributing</a>
  </p>
</div>

## Features

- Capture fullscreen or selected-area screenshots
- Extract on-screen text with OCR capture
- Record screen as video or GIF
- Capture system audio and optional microphone input
- Annotate images with shapes, text, blur, crop, counters, and mockup backgrounds
- Edit recordings with trim, zoom, wallpaper backgrounds, and Follow Mouse support
- Launch from the menu bar with global shortcuts and Quick Access actions
- Hide desktop icons/widgets during capture and get in-app updates via Sparkle

## Requirements

- macOS 13.0+
- Xcode 15.0+ for local builds
- Command Line Tools: `xcode-select --install`

## Install

### Download a release

1. Go to [Releases](https://github.com/duongductrong/Snapzy/releases)
2. Download the latest packaged app asset, typically `Snapzy-<version>.zip`
3. Unzip the archive and move `Snapzy.app` to `/Applications`
4. Launch Snapzy
5. Grant Screen Recording permission when prompted in System Settings
6. Grant Microphone permission too if you want voice input in recordings

## Build from source

1. Clone the repository:

```bash
git clone https://github.com/duongductrong/Snapzy.git
cd Snapzy
```

2. Create the local Xcode config expected by the project:

```bash
cp Snapzy/Config/Secrets.xcconfig.example Snapzy/Config/Secrets.xcconfig
```

3. The example file satisfies Xcode, but the built-in licensing flow expects real Polar values. Add valid credentials in `Snapzy/Config/Secrets.xcconfig`, or adapt the licensing flow for your local build
4. Open the project:

```bash
open Snapzy.xcodeproj
```

5. Build and run with `Cmd+R`

You can also build from the terminal:

```bash
xcodebuild -project Snapzy.xcodeproj -scheme Snapzy -configuration Debug build
```

For release packaging details, see [docs/project-build.md](docs/project-build.md).

## Documentation

- [Project build guide](docs/project-build.md)
- [Project structure](docs/project-structure.md)
- [Release workflow](docs/project-workflow.md)

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## Star history

<a href="https://www.star-history.com/#duongductrong/Snapzy&Date">
  <picture>
    <source
      media="(prefers-color-scheme: dark)"
      srcset="https://api.star-history.com/svg?repos=duongductrong/Snapzy&type=Date&theme=dark"
    />
    <source
      media="(prefers-color-scheme: light)"
      srcset="https://api.star-history.com/svg?repos=duongductrong/Snapzy&type=Date"
    />
    <img
      alt="Star History Chart"
      src="https://api.star-history.com/svg?repos=duongductrong/Snapzy&type=Date"
    />
  </picture>
</a>

## License

MIT. See [LICENSE](LICENSE).
