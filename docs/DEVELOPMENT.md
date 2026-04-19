# Development

Set up Snapzy for local development and run it from source.

## Prerequisites

- macOS 13.0+
- Xcode 15.0+
- Command Line Tools: `xcode-select --install`

## Clone the repository

```bash
git clone https://github.com/duongductrong/Snapzy.git
cd Snapzy
```

## Open in Xcode

```bash
open Snapzy.xcodeproj
```

Build and run with `Cmd+R`.

## Build from the terminal

```bash
xcodebuild -project Snapzy.xcodeproj -scheme Snapzy -configuration Debug build
```

Output: `~/Library/Developer/Xcode/DerivedData/Snapzy-*/Build/Products/Debug/Snapzy.app`

## Related docs

- For archive, export, and DMG packaging commands, see [BUILD.md](BUILD.md).
- For release and appcast workflow, see [RELEASES.md](RELEASES.md).
