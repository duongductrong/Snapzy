# Scout Report: ZapShot Codebase Analysis for Screen Recording MVP

## Core Components

### 1. AreaSelectionWindow
**Path:** `ZapShot/Core/AreaSelectionWindow/`
- `AreaSelectionWindow.swift` - NSWindow with `.borderless` style, `.screenSaver` level
- `AreaSelectionController.swift` - Manages selection lifecycle
- `AreaSelectionOverlayView.swift` - Handles mouse events, draws selection rect
- **Pattern:** Delegate-based (`AreaSelectionWindowDelegate`, `AreaSelectionOverlayViewDelegate`)
- **Key:** Uses `NSTrackingArea` for mouse tracking, Escape key monitoring

### 2. KeyboardShortcutManager
**Path:** `ZapShot/Core/KeyboardShortcutManager.swift`
- Uses `Carbon.HIToolbox` for global hotkeys (`RegisterEventHotKey`, `UnregisterEventHotKey`)
- `ShortcutConfig` struct with `keyCode`, `modifiers`, `displayString`
- Persists via `UserDefaults`
- Defaults: `Cmd+Shift+3` (fullscreen), `Cmd+Shift+4` (area)
- **Key:** `EventHandlerUPP` for global hotkey capture

### 3. ScreenCaptureManager
**Path:** `ZapShot/Core/ScreenCaptureManager.swift`
- Uses `ScreenCaptureKit` (`SCShareableContent`, `SCContentFilter`, `SCStreamConfiguration`)
- Methods: `captureFullscreen()`, `captureArea(rect:)`
- Permission handling: `hasPermission`, `requestPermission()`
- `CaptureResult`, `CaptureError` enums
- Uses `Combine` (`PassthroughSubject`) for events

## Features

### 4. FloatingScreenshot
**Path:** `ZapShot/Features/FloatingScreenshot/`
- `FloatingCardView.swift` - Screenshot thumbnail with hover actions (Copy, Save, Dismiss)
- `FloatingPanelController.swift` - Manages `FloatingPanel` (NSPanel subclass)
- `FloatingPosition` enum for positioning (e.g., `bottomRight`)
- **Pattern:** Double-tap opens annotation view
- **Key:** Reusable for video thumbnails with modified actions

### 5. Preferences/Settings
**Path:** `ZapShot/Features/Preferences/`
- `ShortcutsSettingsView.swift` - Tab for shortcut customization
- `ShortcutRecorderView.swift` - Custom shortcut recorder component
- Enable/disable toggles, Reset to Defaults button
- **Key:** Add new shortcut row for Screen Recording

### 6. OnboardingView
**Path:** `ZapShot/Features/Onboarding/Views/`
- `ShortcutsView.swift` - Displays shortcuts during onboarding
- Shows ⇧⌘3 and ⇧⌘4 with Yes/No options
- **Key:** Add ⇧⌘5 for screen recording

## App Structure

### 7. ZapShotApp
**Path:** `ZapShot/App/ZapShotApp.swift`
- `MenuBarExtra` implementation with system icon
- `MenuBarContentView` - Menu items (Capture Area, Fullscreen, Preferences, Quit)
- `WindowGroup(id: "onboarding")` for onboarding
- `Settings { PreferencesView() }` for preferences window

### 8. Window Management
- `AnnotateWindowController.swift` - Opens annotation window with NSHostingView
- `FloatingPanelController.swift` - Floating overlay panels
- **Pattern:** NSHostingView embeds SwiftUI in AppKit windows

## Files to Modify (Screen Recording MVP)

| File | Modification |
|------|-------------|
| `KeyboardShortcutManager.swift` | Add `Cmd+Shift+5` shortcut |
| `ShortcutsSettingsView.swift` | Add Screen Recording shortcut row |
| `ShortcutsView.swift` (Onboarding) | Display new shortcut |
| `ZapShotApp.swift` | Add "Record Screen" menu item, handle recording state |
| `FloatingCardView.swift` | Extend for video thumbnail routing |
| `FloatingPanelController.swift` | Support video thumbnail display |

## Files to Create

| File | Purpose |
|------|---------|
| `ScreenRecorderManager.swift` | SCStream, AVAssetWriter, audio handling |
| `RecordingToolbarView.swift` | Floating toolbar (Record, Mic, Cancel) |
| `RecordingToolbarController.swift` | Manage toolbar window |
| `RecordingTimerView.swift` | Optional floating timer during recording |
| `VideoEditorStubView.swift` | Placeholder for future video editor |
| `VideoThumbnailGenerator.swift` | Generate video preview thumbnail |

## Unresolved Questions
- Does existing `AreaSelectionWindow` support mode switching (screenshot vs recording)?
- Should `FloatingCardView` be generalized or create separate `VideoCardView`?
