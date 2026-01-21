# Phase 4: Shortcuts Tab Implementation

## Context

- [Main Plan](../plan.md)
- [Phase 3: Quick Access Tab](./phase-03-quick-access-tab.md)
- [Keyboard Shortcuts Research](../research/researcher-02-keyboard-shortcuts-recording.md)

## Overview

Implement Shortcuts settings tab reusing existing ShortcutRecorderView and KeyboardShortcutManager.

## Key Insights

- ShortcutRecorderView already handles recording mode, escape cancel, modifier requirement
- KeyboardShortcutManager persists shortcuts via JSONEncoder to UserDefaults
- Need to extend ShortcutAction enum for future actions (window capture, recording, etc.)
- Add "Reset to Defaults" button for user convenience

## Requirements

1. List of configurable shortcuts with labels and recorders
2. Current shortcuts: Fullscreen capture, Area capture
3. Future-proof: Easy to add more shortcuts
4. Reset to Defaults button

## Architecture

```
ShortcutsSettingsView
  ├── Form
  │   ├── Section: Capture
  │   │   ├── ShortcutRow: Capture Fullscreen
  │   │   └── ShortcutRow: Capture Area
  │   ├── Section: (Future) Recording
  │   └── Section: (Future) Quick Actions
  └── HStack
      └── Button: Reset to Defaults
```

## Related Code Files

| File | Purpose |
|------|---------|
| `ZapShot/Features/Preferences/Tabs/ShortcutsSettingsView.swift` | Main view |
| `ZapShot/Core/ShortcutRecorderView.swift` | Existing recorder |
| `ZapShot/Core/KeyboardShortcutManager.swift` | Existing manager |

## Implementation Steps

### Step 1: Create ShortcutsSettingsView

```swift
// ZapShot/Features/Preferences/Tabs/ShortcutsSettingsView.swift
import SwiftUI

struct ShortcutsSettingsView: View {
    @State private var fullscreenShortcut: ShortcutConfig
    @State private var areaShortcut: ShortcutConfig

    private let manager = KeyboardShortcutManager.shared

    init() {
        _fullscreenShortcut = State(initialValue: KeyboardShortcutManager.shared.fullscreenShortcut)
        _areaShortcut = State(initialValue: KeyboardShortcutManager.shared.areaShortcut)
    }

    var body: some View {
        Form {
            Section("Capture") {
                ShortcutRecorderView(
                    label: "Capture Fullscreen",
                    shortcut: $fullscreenShortcut,
                    onShortcutChanged: { manager.setFullscreenShortcut($0) }
                )

                ShortcutRecorderView(
                    label: "Capture Area",
                    shortcut: $areaShortcut,
                    onShortcutChanged: { manager.setAreaShortcut($0) }
                )
            }

            Section {
                Text("Click a shortcut to record new keys. Press Esc to cancel.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Reset to Defaults") { resetToDefaults() }
                    .padding()
            }
        }
    }

    private func resetToDefaults() {
        fullscreenShortcut = .defaultFullscreen
        areaShortcut = .defaultArea
        manager.setFullscreenShortcut(.defaultFullscreen)
        manager.setAreaShortcut(.defaultArea)
    }
}
```

### Step 2: Enhance ShortcutRecorderView layout for Form

Modify existing ShortcutRecorderView to work better in Form context:

```swift
// Update in ShortcutRecorderView.swift - make label flexible
struct ShortcutRecorderView: View {
    let label: String
    @Binding var shortcut: ShortcutConfig
    let onShortcutChanged: (ShortcutConfig) -> Void

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button { startRecording() } label: {
                Text(isRecording ? "Press keys..." : shortcut.displayString)
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 100)
            }
            .buttonStyle(ShortcutButtonStyle(isRecording: isRecording))
        }
    }
    // ... rest unchanged
}
```

## Todo List

- [ ] Create ShortcutsSettingsView with Form layout
- [ ] Add Reset to Defaults button
- [ ] Test shortcut recording in preferences context
- [ ] Verify shortcuts update KeyboardShortcutManager
- [ ] Test reset restores default shortcuts

## Success Criteria

- [x] All shortcuts display current key combinations
- [x] Clicking shortcut enters recording mode
- [x] New shortcuts register with KeyboardShortcutManager
- [x] Reset to Defaults restores original shortcuts
- [x] Escape cancels recording without changes

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Shortcut conflicts with system | Warn user if known conflict detected |
| Recording mode stuck | Escape always cancels, click outside stops |

## Security Considerations

- Shortcuts stored in UserDefaults (app-sandboxed)
- No elevated permissions required for recording

## Next Steps

Proceed to [Phase 5: Placeholder Tabs](./phase-05-placeholder-tabs.md)
