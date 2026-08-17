# Manual Build Guide

Build Snapzy from source on your local machine.

> If you only need first-time local setup and a basic debug run, start with [DEVELOPMENT.md](DEVELOPMENT.md).

## Prerequisites

- macOS 13.0+
- Xcode 15.0+
- Command Line Tools: `xcode-select --install`

## Quick Build (Xcode)

```bash
open Snapzy.xcodeproj
```

Press ⌘R to build and run.

## Regenerate App Icon Assets

After editing `Snapzy/SnapzyIcon.icon` in Icon Composer, regenerate the padded macOS asset catalog before building a release:

```bash
brew install imagemagick # one-time dependency if magick is missing
scripts/generate-app-icon-assets.sh
```

The script renders the `.icon` package with Icon Composer's bundled `ictool`, then centers the rendered artwork in an 832 × 832 px box on a 1024 × 1024 px transparent canvas. This preserves the Icon Composer artwork while keeping Finder/Dock margins consistent with other macOS apps.

If you only have a manually exported Icon Composer PNG, use:

```bash
scripts/generate-app-icon-assets.sh --source-png /path/to/IconComposerExport.png
```

For other projects, copy `scripts/generate-icon-composer-appiconset.sh` and run it directly:

```bash
./generate-icon-composer-appiconset.sh /path/to/MyIcon.icon
```

By default it writes `AppIcon.appiconset` next to the input `.icon` package. To target an existing asset catalog:

```bash
./generate-icon-composer-appiconset.sh /path/to/MyIcon.icon \
  --appiconset /path/to/Assets.xcassets/AppIcon.appiconset
```

## Command Line Build

### Development Build

```bash
xcodebuild -project Snapzy.xcodeproj -scheme Snapzy -configuration Debug build
```

Output: `~/Library/Developer/Xcode/DerivedData/Snapzy-*/Build/Products/Debug/Snapzy.app`

### Release Build (Unsigned)

```bash
xcodebuild -project Snapzy.xcodeproj \
  -scheme Snapzy \
  -configuration Release \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  build
```

### Release Archive (Signed)

Requires Apple Developer account.

```bash
# 1. Create archive
xcodebuild -project Snapzy.xcodeproj \
  -scheme Snapzy \
  -configuration Release \
  archive -archivePath Snapzy.xcarchive

# 2. Export app bundle
xcodebuild -exportArchive \
  -archivePath Snapzy.xcarchive \
  -exportPath ./exported_app \
  -exportOptionsPlist ExportOptions.plist
```

### Create DMG

After exporting, create distributable DMG:

```bash
# Using create-dmg (brew install create-dmg)
create-dmg \
  --volname "Snapzy" \
  --background "assets/dmg-background.png" \
  --window-size 660 400 \
  --icon-size 120 \
  --icon "Snapzy.app" 180 170 \
  --app-drop-link 480 170 \
  --no-internet-enable \
  "Snapzy.dmg" \
  "./exported_app/Snapzy.app"
```

## Plugin Packages

The plugin subsystem consists of local Swift packages:

| Piece | What it is |
| --- | --- |
| `Packages/SnapzyPluginProtocol` | Binary protocol framing, IPC message models, and shared memory blob table |
| `Packages/SnapzyPluginSDK` | Swift Native Plugin SDK (`SnapzyPlugin`, `CommandContext`), test harnesses (`FakeHost`, `PluginHarness`), and `snapzy-plugin` CLI |
| `Packages/SnapzyPluginAPI` | Extension points and vocabulary (commands, documents, capability identifiers) |
| `Packages/PluginKit` | Vendored plugin foundation: manifests, capabilities, registries, lifecycle |

**Plugins are not bundled into the app.** They run as isolated, sandboxed native Swift child processes and are installed into `~/Library/Application Support/Snapzy/Plugins/`.

## Build Locations

| Build Type | Location |
|------------|----------|
| Debug | `DerivedData/Snapzy-*/Build/Products/Debug/` |
| Release | `DerivedData/Snapzy-*/Build/Products/Release/` |
| Archive | `./Snapzy.xcarchive` |
| Export | `./exported_app/Snapzy.app` |

## Troubleshooting

### "archive not found" Error

You used `build` instead of `archive`. The `build` command outputs to DerivedData, not `.xcarchive`.

```bash
# Wrong
xcodebuild ... build
xcodebuild -exportArchive -archivePath Snapzy.xcarchive ...  # Fails!

# Correct
xcodebuild ... archive -archivePath Snapzy.xcarchive
xcodebuild -exportArchive -archivePath Snapzy.xcarchive ...  # Works!
```

### Code Signing Issues

For local testing without signing:

```bash
xcodebuild ... CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO build
```

### Clean Build

```bash
xcodebuild -project Snapzy.xcodeproj -scheme Snapzy clean
rm -rf ~/Library/Developer/Xcode/DerivedData/Snapzy-*
```
