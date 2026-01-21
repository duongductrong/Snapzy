# Performance Optimization: Shortcut Response Time

**Date:** 2026-01-19
**Goal:** Eliminate delay when pressing Cmd+Shift+3/4/5 shortcuts
**Target:** <100ms perceived response time

---

## Problem Analysis

### Current Flow (Cmd+Shift+3 - Fullscreen)
1. Carbon hotkey event → `handleHotkey()` → `Task { @MainActor }` dispatch
2. `delegate?.shortcutTriggered(.captureFullscreen)`
3. `captureFullscreen()` → **200ms sleep** → `SCShareableContent.current` → capture

### Current Flow (Cmd+Shift+4 - Area Selection)
1. Carbon hotkey → delegate
2. `captureArea()` → `NSApp.hide(nil)`
3. **DispatchQueue.main.asyncAfter(0.2s)** delay
4. Create `AreaSelectionController`
5. Create `AreaSelectionWindow` for **each screen** (synchronously)
6. Set window level, configure, show

### Current Flow (Cmd+Shift+5 - Recording)
1. Carbon hotkey → delegate
2. `startRecordingFlow()` → permission check → `NSApp.hide(nil)`
3. **DispatchQueue.main.asyncAfter(0.2s)** delay
4. Create `AreaSelectionController`
5. Create overlay windows per screen

### Identified Bottlenecks

| Bottleneck | Location | Impact |
|------------|----------|--------|
| 200ms explicit sleep | `ScreenCaptureViewModel.swift:165` | High |
| 200ms asyncAfter delay | `ScreenCaptureViewModel.swift:191, 265` | High |
| Task { @MainActor } dispatch | `KeyboardShortcutManager.swift:313` | Low-Medium |
| Synchronous multi-screen window creation | `AreaSelectionController.startSelection()` | Medium |
| Window configuration overhead | `AreaSelectionWindow.init()` | Low |

---

## Implementation Plan

### Phase 1: Remove Artificial Delays

**File:** `ZapShot/Core/ScreenCaptureViewModel.swift`

#### Task 1.1: Remove 200ms sleep in captureFullscreen
- Line 165: Remove `try? await Task.sleep(nanoseconds: 200_000_000)`
- The delay was meant to "hide window before capture" but app is already menu bar only
- If needed, use 50ms max or rely on window ordering

#### Task 1.2: Reduce asyncAfter delays in captureArea
- Line 191: Change `deadline: .now() + 0.2` → `deadline: .now() + 0.05`
- Or use `DispatchQueue.main.async` if hiding is not strictly necessary

#### Task 1.3: Reduce asyncAfter delays in startRecordingFlow
- Line 265: Change `deadline: .now() + 0.2` → `deadline: .now() + 0.05`

---

### Phase 2: Optimize Hotkey Dispatch

**File:** `ZapShot/Core/KeyboardShortcutManager.swift`

#### Task 2.1: Remove unnecessary Task dispatch
- Lines 312-315: The Carbon handler already runs on main thread
- Replace `Task { @MainActor in ... }` with direct synchronous call
- Or use `DispatchQueue.main.async` for minimal overhead

```swift
// Current (adds task scheduling overhead):
Task { @MainActor in
  KeyboardShortcutManager.shared.handleHotkey(id: hotkeyID.id)
}

// Optimized (direct dispatch):
DispatchQueue.main.async {
  KeyboardShortcutManager.shared.handleHotkey(id: hotkeyID.id)
}
```

---

### Phase 3: Pre-warm Critical Components

**File:** `ZapShot/App/ZapShotApp.swift` or new `AppWarmup.swift`

#### Task 3.1: Pre-initialize singletons at app launch
- `ScreenCaptureManager.shared` - already lazy, trigger early
- `QuickAccessManager.shared` - already lazy, trigger early
- `RecordingCoordinator.shared` - trigger early

#### Task 3.2: Pre-check SCShareableContent permission
- Call `SCShareableContent.current` once at launch (background)
- Cache permission state to avoid async check on first capture

```swift
// In AppDelegate.applicationDidFinishLaunching:
Task.detached(priority: .utility) {
  _ = try? await SCShareableContent.current
  await MainActor.run {
    ScreenCaptureManager.shared.hasPermission = true
  }
}
```

---

### Phase 4: Lazy Window Pool (Optional - Advanced)

**File:** New `ZapShot/Core/WindowPool.swift`

#### Task 4.1: Pre-create reusable overlay windows
- Create `AreaSelectionWindow` instances at app launch (hidden)
- Reuse instead of recreating on each shortcut press
- Reset state between uses

**Trade-off:** Higher memory usage (~1-2MB per screen) vs faster response

```swift
@MainActor
final class OverlayWindowPool {
  static let shared = OverlayWindowPool()
  private var windows: [NSScreen: AreaSelectionWindow] = [:]

  func warmup() {
    for screen in NSScreen.screens {
      let window = AreaSelectionWindow(screen: screen)
      window.orderOut(nil)
      windows[screen] = window
    }
  }

  func acquire(for screen: NSScreen) -> AreaSelectionWindow {
    if let existing = windows[screen] {
      existing.reset()
      return existing
    }
    return AreaSelectionWindow(screen: screen)
  }
}
```

---

### Phase 5: Optimize Window Creation

**File:** `ZapShot/Core/AreaSelectionWindow.swift`

#### Task 5.1: Defer non-critical window setup
- Move tracking area setup to first mouse event
- Defer `makeFirstResponder` call

#### Task 5.2: Reduce collection behavior complexity
- Current: `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`
- Evaluate if all flags needed

---

## Implementation Order

1. **Phase 1** (Quick wins, highest impact) - ~30 min
2. **Phase 2** (Minor optimization) - ~15 min
3. **Phase 3** (Pre-warming) - ~30 min
4. **Phase 4** (Optional, if still slow) - ~1 hr
5. **Phase 5** (Micro-optimizations) - ~30 min

---

## Testing Criteria

- [ ] Cmd+Shift+3: Capture starts in <100ms
- [ ] Cmd+Shift+4: Selection overlay appears in <100ms
- [ ] Cmd+Shift+5: Recording selection appears in <100ms
- [ ] No regression in capture quality
- [ ] No regression in multi-monitor support
- [ ] Memory usage stable (no leaks from pooling)

---

## Files to Modify

| File | Changes |
|------|---------|
| `ZapShot/Core/ScreenCaptureViewModel.swift` | Remove/reduce delays |
| `ZapShot/Core/KeyboardShortcutManager.swift` | Optimize dispatch |
| `ZapShot/App/ZapShotApp.swift` | Add pre-warming |
| `ZapShot/Core/AreaSelectionWindow.swift` | Defer setup (optional) |
| `ZapShot/Core/WindowPool.swift` | New file (optional) |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Removing delays causes visual glitches | Test on multi-monitor setups; add minimal delay if needed |
| Pre-warming increases launch time | Use background tasks with low priority |
| Window pooling memory overhead | Monitor with Instruments; make it opt-in |
| Carbon handler thread safety | Use DispatchQueue.main.async for safety |

---

## Unresolved Questions

1. Is the 200ms delay in `captureFullscreen` still needed for any menu bar hiding?
2. Should window pooling be enabled by default or as a "performance mode" preference?
3. Are there any edge cases with multiple displays where delays prevent race conditions?
