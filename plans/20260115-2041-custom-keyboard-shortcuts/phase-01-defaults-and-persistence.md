# Phase 1: Update Defaults & Add Persistence

**Status:** 🟡 Pending
**Priority:** High

## Context

- Current defaults: ⌘3 / ⌘4
- Target defaults: ⌘⇧3 / ⌘⇧4 (matches macOS screenshot conventions)
- No persistence currently - shortcuts reset on app restart

## Related Files

- `ZapShot/Core/KeyboardShortcutManager.swift`

## Implementation Steps

### 1.1 Update Default Shortcuts
- [ ] Change `defaultFullscreen` modifiers to `cmdKey | shiftKey`
- [ ] Change `defaultArea` modifiers to `cmdKey | shiftKey`

### 1.2 Add Codable Conformance to ShortcutConfig
- [ ] Add `Codable` conformance to `ShortcutConfig`
- [ ] Ensure proper encoding/decoding of keyCode and modifiers

### 1.3 Add UserDefaults Persistence
- [ ] Create `saveShortcuts()` method
- [ ] Create `loadShortcuts()` method
- [ ] Call `loadShortcuts()` in init
- [ ] Call `saveShortcuts()` when shortcuts are updated

### 1.4 Define UserDefaults Keys
- [ ] Add constants for keys: `fullscreenShortcut`, `areaShortcut`

## Success Criteria

- Default shortcuts are ⌘⇧3 and ⌘⇧4
- Custom shortcuts persist across app restarts
- Build compiles without errors
