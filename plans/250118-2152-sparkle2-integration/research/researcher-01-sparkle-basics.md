# Sparkle 2 Basics Research Report

## Overview
Sparkle 2 is an open-source software update framework for macOS applications. It provides automatic updates with minimal configuration.

## Core Features
- Automatic background update checks
- User-initiated "Check for Updates" functionality
- Delta updates (download only changed bits)
- EdDSA cryptographic signing for security
- Supports DMG, ZIP, tar archives
- Release notes display (HTML/Markdown)
- Gentle update reminders

## Installation Methods

### Swift Package Manager (Recommended)
```
File → Add Packages → https://github.com/sparkle-project/Sparkle
```

### CocoaPods
```ruby
use_frameworks!
pod 'Sparkle'
```

### Manual
1. Download from GitHub releases
2. Drag Sparkle.framework into project
3. Set "Embed & Sign" in build settings

## Basic Setup Requirements
1. Add Sparkle framework to project
2. Configure Info.plist with feed URL and signing key
3. Instantiate updater (XIB or programmatic)
4. Create and host appcast feed
5. Sign update archives

## Key Differences from Sparkle 1.x
- EdDSA signatures (ed25519) replace DSA
- Improved sandboxing support via XPC
- Better SwiftUI compatibility
- SPUUpdater replaces SUUpdater
- SPUStandardUpdaterController for standard UI
- Enhanced security with code signing verification

## Required Info.plist Keys
| Key | Purpose |
|-----|---------|
| SUFeedURL | Appcast feed URL |
| SUPublicEDKey | EdDSA public key for verification |
| CFBundleVersion | Must increment for updates |

## Sources
- https://sparkle-project.org/documentation/
