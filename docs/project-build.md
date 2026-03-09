# Manual Build Guide

Build Snapzy from source on your local machine.

## Prerequisites

- macOS 14.0+
- Xcode 15.0+
- Command Line Tools: `xcode-select --install`

## Quick Build (Xcode)

```bash
open Snapzy.xcodeproj
```

Press ⌘R to build and run.

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
  --window-size 600 400 \
  --icon-size 100 \
  --app-drop-link 450 200 \
  --icon "Snapzy.app" 150 200 \
  "Snapzy.dmg" \
  "./exported_app/Snapzy.app"
```

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
