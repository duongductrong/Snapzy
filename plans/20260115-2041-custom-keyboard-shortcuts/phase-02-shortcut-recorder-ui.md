# Phase 2: Shortcut Recorder UI

**Status:** 🟡 Pending
**Priority:** Medium

## Context

Users need a way to customize shortcuts. Standard approach: click a button, press desired key combo, it gets recorded.

## Related Files

- `ZapShot/ContentView.swift`
- `ZapShot/Core/KeyboardShortcutManager.swift`

## Implementation Steps

### 2.1 Create ShortcutRecorderView
- [ ] Create new SwiftUI view `ShortcutRecorderView`
- [ ] Display current shortcut in styled button
- [ ] Handle "recording" state when clicked
- [ ] Capture key events using `NSEvent.addLocalMonitorForEvents`
- [ ] Convert NSEvent to ShortcutConfig
- [ ] Callback when new shortcut recorded

### 2.2 Extend ShortcutConfig Key Mapping
- [ ] Add more key codes (A-Z, F1-F12, etc.)
- [ ] Create `init(from event: NSEvent)` convenience initializer

### 2.3 Update ContentView Settings
- [ ] Replace static Text displays with ShortcutRecorderView
- [ ] Wire up callbacks to update shortcuts in ViewModel
- [ ] ViewModel calls `KeyboardShortcutManager.setFullscreenShortcut()` etc.

### 2.4 Add Validation
- [ ] Prevent duplicate shortcuts
- [ ] Require at least one modifier key
- [ ] Show error state for invalid combos

## UI Design

```
┌─────────────────────────────────────┐
│ Keyboard Shortcuts                  │
├─────────────────────────────────────┤
│ ☑ Enable global shortcuts           │
│                                     │
│ Fullscreen: [  ⌘⇧3  ] ← clickable   │
│ Area:       [  ⌘⇧4  ] ← clickable   │
│                                     │
│ (Click to record new shortcut)      │
└─────────────────────────────────────┘
```

## Success Criteria

- Users can click shortcut button to enter recording mode
- Pressing key combo updates the shortcut
- Invalid combos show error feedback
- Changes persist immediately
