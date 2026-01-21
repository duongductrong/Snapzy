# Keyboard Shortcut Recording for macOS SwiftUI

## Overview
Research on implementing keyboard shortcut recording and global hotkeys in SwiftUI macOS apps.

## 1. Existing ZapShot Implementation

ZapShot already has:
- `KeyboardShortcutManager.swift` - Carbon-based global hotkey registration
- `ShortcutRecorderView.swift` - SwiftUI shortcut recorder component
- `ShortcutConfig` - Codable struct for storing shortcuts

### Current ShortcutConfig
```swift
struct ShortcutConfig: Equatable, Codable {
    let keyCode: UInt32
    let modifiers: UInt32

    var displayString: String {
        // Returns formatted string like "⌘⇧4"
    }
}
```

## 2. Global Hotkey Approaches

### Carbon API (Current - Works but Deprecated)
```swift
RegisterEventHotKey(keyCode, modifiers, hotkeyID,
                    GetApplicationEventTarget(), 0, &hotkeyRef)
```
- Still functional in macOS 14+
- Used by many production apps

### sindresorhus/KeyboardShortcuts (Recommended Alternative)
```swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureArea = Self("captureArea")
    static let captureFullscreen = Self("captureFullscreen")
}

// In SwiftUI
KeyboardShortcuts.Recorder("Capture Area:", name: .captureArea)
```
- Sandboxed, Mac App Store compatible
- Built-in conflict detection
- Automatic UserDefaults persistence

### CGEventTap (Low-level)
```swift
let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
    callback: callback,
    userInfo: nil
)
```
- Requires Input Monitoring permission
- More control but complex setup

## 3. Current ShortcutRecorderView Pattern

```swift
struct ShortcutRecorderView: View {
    let label: String
    @Binding var shortcut: ShortcutConfig
    let onShortcutChanged: (ShortcutConfig) -> Void

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack {
            Text(label)
            Button {
                startRecording()
            } label: {
                Text(isRecording ? "Press keys..." : shortcut.displayString)
            }
        }
    }

    private func startRecording() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let newShortcut = ShortcutConfig(from: event) {
                shortcut = newShortcut
                onShortcutChanged(newShortcut)
                stopRecording()
            }
            return nil
        }
    }
}
```

## 4. Modifier Symbol Display

```swift
static func modifiersToSymbols(_ modifiers: UInt32) -> String {
    var symbols: [String] = []
    if modifiers & UInt32(cmdKey) != 0 { symbols.append("⌘") }
    if modifiers & UInt32(shiftKey) != 0 { symbols.append("⇧") }
    if modifiers & UInt32(optionKey) != 0 { symbols.append("⌥") }
    if modifiers & UInt32(controlKey) != 0 { symbols.append("⌃") }
    return symbols.joined()
}
```

## 5. Recommendations for Preferences

1. **Reuse existing components**: `ShortcutRecorderView` and `KeyboardShortcutManager` are well-implemented
2. **Extend ShortcutAction enum** for new shortcut types (recording, window capture, etc.)
3. **Add shortcut conflict detection** when recording new shortcuts
4. **Consider adding "Reset to Defaults" button** for shortcuts section

## Required Permissions
- Input Monitoring (for global hotkeys outside app)
- Already handled via Carbon API in current implementation

## Sources
- [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
- [Apple CGEventTap Documentation](https://developer.apple.com/documentation/coregraphics)
- ZapShot existing codebase analysis
