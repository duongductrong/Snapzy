# ClaudeShot

A modern macOS screenshot application designed for efficiency and productivity. ClaudeShot enables quick screen captures with advanced annotation tools and floating screenshot management.

## Features

- **Screen Capture**: Capture fullscreen or specific screen areas using macOS ScreenCaptureKit
- **Annotation Tools**: Comprehensive drawing toolkit with multiple annotation types
- **Quick Access**: Manage captured screenshots as floating cards with quick access
- **Keyboard Shortcuts**: Customizable shortcuts for rapid capture workflows
- **Multi-Display Support**: Works seamlessly across multiple monitors with Retina resolution

## Architecture

ClaudeShot follows a modular SwiftUI architecture organized into core functionality and feature modules:

```
Core/
├── ScreenCaptureManager      - ScreenCaptureKit integration
├── AreaSelectionWindow       - Interactive area selection
└── KeyboardShortcutManager   - Shortcut management

Features/
├── Annotate/                - Annotation canvas, tools, and export
├── QuickAccess/             - Quick access cards and panel management
└── Preferences/             - Settings and user preferences
```

## Requirements

- macOS 14.0+
- Xcode 15.0+
- Swift 5.9+

## Building

1. Clone the repository
2. Open `ClaudeShot.xcodeproj` in Xcode
3. Build and run (⌘R)

## Permissions

ClaudeShot requires Screen Recording permission to capture screenshots. The app will prompt you on first launch or when requesting permission via System Preferences > Privacy & Security > Screen Recording.

## License

[Add your license here]
