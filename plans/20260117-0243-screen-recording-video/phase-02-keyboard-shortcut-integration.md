# Phase 2: Keyboard Shortcut Integration

## Context Links
- [Main Plan](./plan.md)
- [Phase 1: Core Recording Engine](./phase-01-core-recording-engine.md)
- [Codebase Analysis](./scout/scout-01-codebase-analysis.md)

## Overview
Add recording keyboard shortcut (Cmd+Shift+5) to KeyboardShortcutManager, add "Record Screen" menu item to menu bar, extend AreaSelectionController with SelectionMode.

## Requirements
- R1: Cmd+Shift+5 triggers recording area selection
- R2: Menu bar shows "Record Screen" option
- R3: AreaSelectionController supports screenshot vs recording mode
- R4: After area selection in recording mode, show toolbar instead of capturing

## Architecture

### Flow Diagram
```
User presses Cmd+Shift+5
    |
    v
KeyboardShortcutManager.handleHotkey(recordVideo)
    |
    v
ScreenCaptureViewModel.startRecordingFlow()
    |
    v
AreaSelectionController.startSelection(mode: .recording)
    |
    v
User selects area
    |
    v
Completion callback with (rect, mode)
    |
    v
Show RecordingToolbarWindow (Phase 3)
```

## Related Code Files

### Modify
| File | Changes |
|------|---------|
| `ZapShot/Core/KeyboardShortcutManager.swift` | Add recordVideo action, recording shortcut |
| `ZapShot/Core/AreaSelectionWindow.swift` | Add SelectionMode enum |
| `ZapShot/App/ZapShotApp.swift` | Add Record Screen menu item |
| `ZapShot/Core/ScreenCaptureViewModel.swift` | Add startRecordingFlow method |

## Implementation Steps

### Step 1: Add recordVideo to ShortcutAction enum
File: `ZapShot/Core/KeyboardShortcutManager.swift`

```swift
/// Shortcut action types
enum ShortcutAction {
    case captureFullscreen
    case captureArea
    case recordVideo  // ADD
}
```

### Step 2: Add default recording shortcut
File: `ZapShot/Core/KeyboardShortcutManager.swift`

```swift
// Add to ShortcutConfig
/// Cmd + Shift + 5
static let defaultRecording = ShortcutConfig(
    keyCode: UInt32(kVK_ANSI_5),
    modifiers: UInt32(cmdKey | shiftKey)
)
```

### Step 3: Add recording shortcut property and hotkey ref
File: `ZapShot/Core/KeyboardShortcutManager.swift`

```swift
// Add properties
private(set) var recordingShortcut: ShortcutConfig

private var recordingHotkeyRef: EventHotKeyRef?

// Add hotkey ID
private let recordingHotkeyID = EventHotKeyID(signature: OSType(0x5A53_4633), id: 3)  // "ZSF3"

// Add UserDefaults key
private let recordingShortcutKey = "recordingShortcut"
```

### Step 4: Update init to load recording shortcut
```swift
private init() {
    fullscreenShortcut = .defaultFullscreen
    areaShortcut = .defaultArea
    recordingShortcut = .defaultRecording  // ADD
    loadShortcuts()
    setupEventHandler()

    if UserDefaults.standard.bool(forKey: shortcutsEnabledKey) {
        enable()
    }
}
```

### Step 5: Update saveShortcuts
```swift
private func saveShortcuts() {
    let encoder = JSONEncoder()
    if let fullscreenData = try? encoder.encode(fullscreenShortcut) {
        UserDefaults.standard.set(fullscreenData, forKey: fullscreenShortcutKey)
    }
    if let areaData = try? encoder.encode(areaShortcut) {
        UserDefaults.standard.set(areaData, forKey: areaShortcutKey)
    }
    // ADD
    if let recordingData = try? encoder.encode(recordingShortcut) {
        UserDefaults.standard.set(recordingData, forKey: recordingShortcutKey)
    }
}
```

### Step 6: Update loadShortcuts
```swift
private func loadShortcuts() {
    let decoder = JSONDecoder()
    // ... existing code ...

    // ADD
    if let recordingData = UserDefaults.standard.data(forKey: recordingShortcutKey),
       let config = try? decoder.decode(ShortcutConfig.self, from: recordingData) {
        recordingShortcut = config
    }
}
```

### Step 7: Add setRecordingShortcut method
```swift
/// Update recording shortcut
func setRecordingShortcut(_ config: ShortcutConfig) {
    let wasEnabled = isEnabled
    if wasEnabled { disable() }
    recordingShortcut = config
    saveShortcuts()
    if wasEnabled { enable() }
}
```

### Step 8: Update registerShortcuts
```swift
private func registerShortcuts() {
    // ... existing fullscreen and area registration ...

    // Register recording shortcut
    let recordingID = recordingHotkeyID
    RegisterEventHotKey(
        recordingShortcut.keyCode,
        recordingShortcut.modifiers,
        recordingID,
        GetApplicationEventTarget(),
        0,
        &recordingHotkeyRef
    )
}
```

### Step 9: Update unregisterAllShortcuts
```swift
private func unregisterAllShortcuts() {
    // ... existing code ...

    if let ref = recordingHotkeyRef {
        UnregisterEventHotKey(ref)
        recordingHotkeyRef = nil
    }
}
```

### Step 10: Update handleHotkey
```swift
private func handleHotkey(id: UInt32) {
    switch id {
    case fullscreenHotkeyID.id:
        delegate?.shortcutTriggered(.captureFullscreen)
    case areaHotkeyID.id:
        delegate?.shortcutTriggered(.captureArea)
    case recordingHotkeyID.id:  // ADD
        delegate?.shortcutTriggered(.recordVideo)
    default:
        break
    }
}
```

### Step 11: Add SelectionMode to AreaSelectionWindow
File: `ZapShot/Core/AreaSelectionWindow.swift`

```swift
/// Mode for area selection
enum SelectionMode {
    case screenshot
    case recording
}

/// Callback type with mode
typealias AreaSelectionCompletionWithMode = (CGRect?, SelectionMode) -> Void
```

### Step 12: Update AreaSelectionController
File: `ZapShot/Core/AreaSelectionWindow.swift`

```swift
@MainActor
final class AreaSelectionController: NSObject {
    private var overlayWindows: [AreaSelectionWindow] = []
    private var completion: AreaSelectionCompletion?
    private var completionWithMode: AreaSelectionCompletionWithMode?  // ADD
    private var selectionMode: SelectionMode = .screenshot  // ADD
    private var activeWindow: AreaSelectionWindow?
    private var localEscapeMonitor: Any?
    private var globalEscapeMonitor: Any?

    /// Start area selection mode (legacy)
    func startSelection(completion: @escaping AreaSelectionCompletion) {
        startSelection(mode: .screenshot) { rect, _ in
            completion(rect)
        }
    }

    /// Start area selection with mode
    func startSelection(mode: SelectionMode, completion: @escaping AreaSelectionCompletionWithMode) {
        self.selectionMode = mode
        self.completionWithMode = completion

        for screen in NSScreen.screens {
            let window = AreaSelectionWindow(screen: screen)
            window.selectionDelegate = self
            overlayWindows.append(window)
            window.orderFrontRegardless()
        }

        // ... escape key monitoring (same as before) ...
    }

    func completeSelection(rect: CGRect, from window: AreaSelectionWindow) {
        closeAllWindows()
        completionWithMode?(rect, selectionMode)
        completionWithMode = nil
    }

    func cancelSelection() {
        closeAllWindows()
        completionWithMode?(nil, selectionMode)
        completionWithMode = nil
    }
}
```

### Step 13: Update ScreenCaptureViewModel
File: `ZapShot/Core/ScreenCaptureViewModel.swift`

Add method to handle recording flow:
```swift
/// Start recording area selection flow
func startRecordingFlow() {
    guard hasPermission else {
        requestPermission()
        return
    }

    let controller = AreaSelectionController()
    controller.startSelection(mode: .recording) { [weak self] rect, mode in
        guard let rect = rect else { return }

        Task { @MainActor in
            // Will be implemented in Phase 3
            self?.showRecordingToolbar(for: rect)
        }
    }
}

private func showRecordingToolbar(for rect: CGRect) {
    // Placeholder - implemented in Phase 3
    print("Show recording toolbar for rect: \(rect)")
}
```

### Step 14: Update delegate to handle recordVideo
File: `ZapShot/Core/ScreenCaptureViewModel.swift`

```swift
extension ScreenCaptureViewModel: KeyboardShortcutDelegate {
    func shortcutTriggered(_ action: ShortcutAction) {
        switch action {
        case .captureFullscreen:
            captureFullscreen()
        case .captureArea:
            captureArea()
        case .recordVideo:  // ADD
            startRecordingFlow()
        }
    }
}
```

### Step 15: Add Record Screen menu item
File: `ZapShot/App/ZapShotApp.swift`

```swift
struct MenuBarContentView: View {
    @ObservedObject var viewModel: ScreenCaptureViewModel

    var body: some View {
        Group {
            // Capture Actions
            Button {
                viewModel.captureArea()
            } label: {
                Label("Capture Area", systemImage: "crop")
            }
            .keyboardShortcut("4", modifiers: [.command, .shift])
            .disabled(!viewModel.hasPermission)

            Button {
                viewModel.captureFullscreen()
            } label: {
                Label("Capture Fullscreen", systemImage: "rectangle.dashed")
            }
            .keyboardShortcut("3", modifiers: [.command, .shift])
            .disabled(!viewModel.hasPermission)

            Divider()

            // ADD Record Screen
            Button {
                viewModel.startRecordingFlow()
            } label: {
                Label("Record Screen", systemImage: "record.circle")
            }
            .keyboardShortcut("5", modifiers: [.command, .shift])
            .disabled(!viewModel.hasPermission)

            Divider()

            // ... rest unchanged ...
        }
    }
}
```

## Todo List
- [ ] Add `recordVideo` case to ShortcutAction enum
- [ ] Add `defaultRecording` static config (Cmd+Shift+5)
- [ ] Add `recordingShortcut` property and `recordingHotkeyRef`
- [ ] Add `recordingHotkeyID` constant
- [ ] Update `saveShortcuts()` and `loadShortcuts()`
- [ ] Add `setRecordingShortcut()` method
- [ ] Update `registerShortcuts()` to register recording hotkey
- [ ] Update `unregisterAllShortcuts()` to unregister recording hotkey
- [ ] Update `handleHotkey()` to dispatch recordVideo
- [ ] Add `SelectionMode` enum to AreaSelectionWindow.swift
- [ ] Add `startSelection(mode:completion:)` method
- [ ] Add `startRecordingFlow()` to ScreenCaptureViewModel
- [ ] Update KeyboardShortcutDelegate handler for recordVideo
- [ ] Add "Record Screen" menu item with Cmd+Shift+5

## Success Criteria
1. Cmd+Shift+5 triggers recording area selection
2. Menu bar shows "Record Screen" with correct shortcut
3. Area selection works in recording mode
4. Completion callback receives correct mode
5. Recording shortcut is persisted across app launches

## Risk Assessment
| Risk | Impact | Mitigation |
|------|--------|------------|
| Shortcut conflict with system | Low | Cmd+Shift+5 is available (system uses it for screenshot panel) |
| Breaking existing area selection | Medium | Keep legacy completion signature |
| Menu item not updating state | Low | Use viewModel.hasPermission for disabled state |
