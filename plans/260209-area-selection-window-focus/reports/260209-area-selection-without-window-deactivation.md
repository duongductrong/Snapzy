# Research Report: Area Selection Without Window Deactivation/Blur

## Executive Summary

CleanShot X keeps background windows visually active (no blur/dimming of title bars, no inactive appearance) during area selection by using a **non-activating overlay** approach. The key technique: use `NSPanel` with `.nonactivatingPanel` style mask instead of `NSWindow`, combined with `canBecomeKey = false` and `canBecomeMain = false`. This prevents the overlay from stealing application activation, so background windows never enter "inactive" visual state (grey title bars, dimmed controls).

**Snapzy's current problem:** `AreaSelectionWindow` is an `NSWindow` (not `NSPanel`) with `canBecomeKey = true` and `canBecomeMain = true`. When it appears and calls `makeKeyAndOrderFront()`, it activates the Snapzy app, causing all other apps' windows to visually deactivate (blur/dim title bars). This is the exact behavior CleanShot X avoids.

## Research Methodology

- Sources consulted: 5+ (Gemini AI research, Apple documentation patterns, StackOverflow, web search results)
- Key search terms: NSPanel nonactivatingPanel, screenshot overlay focus stealing, CGEventTap mouse tracking, NSWindow.Level
- Codebase analysis: AreaSelectionWindow.swift, QuickAccessPanel.swift, RecordingRegionOverlayWindow.swift

## Key Findings

### 1. Root Cause in Snapzy

Current `AreaSelectionWindow` configuration (line 270-330):
```swift
// PROBLEM: Uses NSWindow, not NSPanel
final class AreaSelectionWindow: NSWindow {
    // PROBLEM: Both return true → steals focus
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(screen: NSScreen, pooled: Bool = false) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,  // PROBLEM: Missing .nonactivatingPanel
            backing: .buffered,
            defer: false
        )
        self.level = .screenSaver
        // ...
        // PROBLEM: This activates the app, deactivating all others
        self.makeKeyAndOrderFront(nil)
        self.makeMain()
    }
}
```

When `makeKeyAndOrderFront()` is called, macOS activates Snapzy app → all other apps' windows visually deactivate (grey title bars, dimmed appearance).

### 2. How CleanShot X Solves This

CleanShot X uses a **two-layer approach**:

| Component | Type | Purpose |
|-----------|------|---------|
| Overlay dimming layer | `NSPanel` + `.nonactivatingPanel` | Semi-transparent dim over screen, doesn't steal focus |
| Mouse event capture | `CGEventTap` or `NSEvent.addGlobalMonitorForEvents` | Captures mouse globally without window activation |

**Key properties that prevent focus stealing:**
1. `NSPanel` (not `NSWindow`) with `styleMask: [.borderless, .nonactivatingPanel]`
2. `canBecomeKey = false`
3. `canBecomeMain = false`
4. `isFloatingPanel = true`
5. High `NSWindow.Level` (`.screenSaver` or `.overlay`)
6. `orderFrontRegardless()` instead of `makeKeyAndOrderFront()`

### 3. The Non-Activating Panel Pattern

```swift
// CORRECT approach — background windows stay visually active
final class AreaSelectionPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .screenSaver
        self.isFloatingPanel = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

### 4. Mouse Event Challenge

With `canBecomeKey = false`, the panel won't receive keyboard events via responder chain. But mouse events work differently:

| Event Type | Works with nonactivating? | Notes |
|-----------|--------------------------|-------|
| `mouseDown/Dragged/Up` | YES | NSView receives these if `ignoresMouseEvents = false` |
| `mouseMoved` | YES | Via NSTrackingArea with `.activeAlways` |
| `keyDown` (Escape) | NO | Need `NSEvent.addGlobalMonitorForEvents` |
| `cursorUpdate` | YES | Via NSTrackingArea |

**Mouse events work fine** because `NSTrackingArea` with `.activeAlways` + `acceptsFirstMouse = true` ensures the view receives clicks and drags even without being key window.

**Keyboard events (Escape key)** must be handled via `NSEvent.addLocalMonitorForEvents` + `NSEvent.addGlobalMonitorForEvents` — which Snapzy already does correctly.

### 5. Snapzy Already Has the Pattern

`QuickAccessPanel.swift` already implements this correctly:
```swift
final class QuickAccessPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],  // ✅ Correct
            backing: .buffered,
            defer: false
        )
    }
    override var canBecomeKey: Bool { false }   // ✅ Correct
    override var canBecomeMain: Bool { false }   // ✅ Correct
}
```

## Comparative Analysis: NSWindow vs NSPanel

| Property | Current (NSWindow) | Required (NSPanel) |
|----------|-------------------|-------------------|
| Base class | `NSWindow` | `NSPanel` |
| styleMask | `.borderless` | `[.borderless, .nonactivatingPanel]` |
| canBecomeKey | `true` | `false` |
| canBecomeMain | `true` | `false` |
| isFloatingPanel | N/A | `true` |
| Show method | `makeKeyAndOrderFront()` | `orderFrontRegardless()` |
| Focus stealing | YES (causes blur) | NO (windows stay active) |
| Mouse events | Via responder chain | Via NSTrackingArea + acceptsFirstMouse |
| Keyboard events | Via responder chain | Via NSEvent monitors (already implemented) |

## Implementation Recommendations

### Required Changes

1. **Change `AreaSelectionWindow` from `NSWindow` to `NSPanel`**
2. **Add `.nonactivatingPanel` to styleMask**
3. **Set `canBecomeKey = false` and `canBecomeMain = false`**
4. **Add `isFloatingPanel = true`**
5. **Replace `makeKeyAndOrderFront()` with `orderFrontRegardless()`**
6. **Remove `makeMain()` call**

### Minimal diff:

```swift
// Before:
final class AreaSelectionWindow: NSWindow {
    super.init(
        contentRect: screen.frame,
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    // In activatePooledWindows():
    window.makeKeyAndOrderFront(nil)
    window.makeMain()
}

// After:
final class AreaSelectionWindow: NSPanel {
    super.init(
        contentRect: screen.frame,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    self.isFloatingPanel = true
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // In activatePooledWindows():
    window.orderFrontRegardless()
}
```

### Things that still work without changes:
- **Mouse tracking** — `NSTrackingArea` with `.activeAlways` already handles this
- **Mouse clicks** — `acceptsFirstMouse` already returns `true`
- **Escape key** — Already uses `NSEvent.addLocalMonitorForEvents` + `addGlobalMonitorForEvents`
- **Crosshair cursor** — Already uses `NSTrackingArea` with `.cursorUpdate`
- **CALayer rendering** — Unaffected by window type change

### Potential gotcha:
- `makeFirstResponder(overlayView)` in `becomeKey()` — with `canBecomeKey = false`, `becomeKey()` won't be called. But since mouse events are handled via NSTrackingArea/NSView mouse methods (not responder chain keyboard events), this is fine.

## Common Pitfalls

1. **Don't use `makeKeyAndOrderFront()`** — always use `orderFrontRegardless()` or `orderFront(nil)` for non-activating panels
2. **Don't set `canBecomeKey = true`** — this defeats the purpose of `.nonactivatingPanel`
3. **Don't forget `isFloatingPanel = true`** — reinforces non-activating behavior
4. **Don't worry about mouse events** — they work with `.activeAlways` tracking areas regardless of key window status

## Resources & References

### Official Documentation
- [NSPanel - Apple Developer](https://developer.apple.com/documentation/appkit/nspanel)
- [NSWindow.StyleMask.nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask/1644530-nonactivatingpanel)
- [NSTrackingArea](https://developer.apple.com/documentation/appkit/nstrackingarea)

### Community Resources
- [StackOverflow: NSPanel nonactivating focus](https://stackoverflow.com)
- [YouTube: NSPanel full-screen overlays in Swift (2024)](https://youtube.com)

## Unresolved Questions

1. **CGEventTap approach** — Could provide even more control by intercepting mouse events system-wide before they reach any app. Currently unnecessary since NSPanel+NSTrackingArea handles mouse events adequately. Worth investigating only if edge cases arise (e.g., certain full-screen apps not receiving mouse events properly).

2. **Multi-monitor behavior** — Need to verify that non-activating panels across multiple screens all receive mouse events correctly. Current pool architecture should work since each screen gets its own panel with its own tracking area.

3. **`RecordingRegionOverlayWindow`** — Also uses `NSWindow` with `canBecomeKey = true`. May need same treatment if it causes focus stealing during pre-record phase.
