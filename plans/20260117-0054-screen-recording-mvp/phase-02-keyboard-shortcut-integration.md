# Phase 2: Keyboard Shortcut Integration

## Context
- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** None (can run parallel with Phase 1)
- **Scout:** [Codebase Analysis](./scout/scout-01-codebase-analysis.md)

## Overview
| Field | Value |
|-------|-------|
| Date | 2026-01-17 |
| Priority | P1 - High |
| Status | pending |
| Effort | 1-2 hours |

Add `Cmd+Shift+5` global shortcut for screen recording. Update KeyboardShortcutManager, ShortcutsSettingsView, and OnboardingView.

## Key Insights
1. Existing `KeyboardShortcutManager` uses Carbon `RegisterEventHotKey` - proven pattern
2. `ShortcutAction` enum needs new `.recordScreen` case
3. `ShortcutConfig` already has `.defaultFullscreen` and `.defaultArea` - add `.defaultRecording`
4. Settings UI uses `ShortcutRecorderView` component - reusable

## Requirements

### Functional
- [x] Register `Cmd+Shift+5` as default screen recording shortcut
- [x] Add shortcut customization in Preferences > Shortcuts
- [x] Display shortcut in Onboarding flow
- [x] Trigger recording flow when shortcut pressed

### Non-Functional
- Shortcut must work globally (any app focused)
- Persist custom shortcut to UserDefaults
- Reset to Defaults button includes recording shortcut

## Architecture

```
KeyboardShortcutManager
├── recordingShortcut: ShortcutConfig  (NEW)
├── recordingHotkeyRef: EventHotKeyRef? (NEW)
├── recordingHotkeyID (NEW)
└── ShortcutAction.recordScreen (NEW)

ShortcutsSettingsView
└── Add ShortcutRecorderView for "Record Screen"

ShortcutsView (Onboarding)
└── Display "Cmd+Shift+5 for recording"
```

## Related Code Files
| File | Modification |
|------|--------------|
| `ZapShot/Core/KeyboardShortcutManager.swift` | Add recording shortcut |
| `ZapShot/Features/Preferences/Tabs/ShortcutsSettingsView.swift` | Add UI row |
| `ZapShot/Features/Onboarding/Views/ShortcutsView.swift` | Update text |

## Implementation Steps

### Step 1: Update KeyboardShortcutManager.swift

**Add default config:**
```swift
/// Cmd + Shift + 5
static let defaultRecording = ShortcutConfig(
  keyCode: UInt32(kVK_ANSI_5),
  modifiers: UInt32(cmdKey | shiftKey)
)
```

**Add action case:**
```swift
enum ShortcutAction {
  case captureFullscreen
  case captureArea
  case recordScreen  // NEW
}
```

**Add properties to manager:**
```swift
private(set) var recordingShortcut: ShortcutConfig
private var recordingHotkeyRef: EventHotKeyRef?
private let recordingHotkeyID = EventHotKeyID(signature: OSType(0x5A53_4633), id: 3)  // "ZSF3"
private let recordingShortcutKey = "recordingShortcut"
```

**Update init:**
```swift
recordingShortcut = .defaultRecording
// In loadShortcuts():
if let recordingData = UserDefaults.standard.data(forKey: recordingShortcutKey),
   let config = try? decoder.decode(ShortcutConfig.self, from: recordingData) {
  recordingShortcut = config
}
```

**Add setter:**
```swift
func setRecordingShortcut(_ config: ShortcutConfig) {
  let wasEnabled = isEnabled
  if wasEnabled { disable() }
  recordingShortcut = config
  saveShortcuts()
  if wasEnabled { enable() }
}
```

**Update registerShortcuts():**
```swift
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
```

**Update handleHotkey():**
```swift
case recordingHotkeyID.id:
  delegate?.shortcutTriggered(.recordScreen)
```

**Update unregisterAllShortcuts():**
```swift
if let ref = recordingHotkeyRef {
  UnregisterEventHotKey(ref)
  recordingHotkeyRef = nil
}
```

### Step 2: Update ShortcutsSettingsView.swift

**Add state:**
```swift
@State private var recordingShortcut: ShortcutConfig

// In init():
_recordingShortcut = State(initialValue: KeyboardShortcutManager.shared.recordingShortcut)
```

**Add UI row in Section("Capture"):**
```swift
ShortcutRecorderView(
  label: "Record Screen",
  shortcut: $recordingShortcut,
  onShortcutChanged: { manager.setRecordingShortcut($0) }
)
```

**Update resetToDefaults():**
```swift
recordingShortcut = .defaultRecording
manager.setRecordingShortcut(.defaultRecording)
```

### Step 3: Update ShortcutsView.swift (Onboarding)

**Update subtitle text:**
```swift
Text("Do you want to assign shortcuts to ZapShot?\n\n" +
     "\u{21E7}\u{2318}3 - Fullscreen\n" +
     "\u{21E7}\u{2318}4 - Area\n" +
     "\u{21E7}\u{2318}5 - Record Screen")
  .vsBody()
  .multilineTextAlignment(.center)
  .frame(maxWidth: 320)
```

### Step 4: Handle shortcut in app

**In ScreenCaptureViewModel or AppDelegate:**
```swift
extension ScreenCaptureViewModel: KeyboardShortcutDelegate {
  func shortcutTriggered(_ action: ShortcutAction) {
    switch action {
    case .captureFullscreen:
      captureFullscreen()
    case .captureArea:
      captureArea()
    case .recordScreen:
      startRecordingFlow()  // NEW - triggers selection overlay
    }
  }
}
```

## Todo
- [ ] Add ShortcutConfig.defaultRecording
- [ ] Add ShortcutAction.recordScreen
- [ ] Add recordingShortcut property to manager
- [ ] Register/unregister recording hotkey
- [ ] Update ShortcutsSettingsView
- [ ] Update OnboardingView
- [ ] Wire up shortcut to recording flow

## Success Criteria
1. `Cmd+Shift+5` triggers recording flow globally
2. Shortcut customizable in Preferences
3. Reset to Defaults restores Cmd+Shift+5
4. Onboarding displays all three shortcuts
5. Shortcut persists across app restarts

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Conflict with macOS screenshot | Low | Medium | macOS uses Cmd+Shift+5 for its tool - user may need to disable in System Prefs |
| Hotkey registration fails | Low | Low | Log error, show in settings |

## Security Considerations
- No sensitive data involved
- Follows existing permission patterns

## Next Steps
After completion, recording shortcut will trigger selection overlay. Phase 3 (Toolbar UI) and Phase 4 (Active Recording) handle subsequent flow.

## Unresolved Questions
1. Should we warn user about macOS Cmd+Shift+5 conflict in onboarding?
