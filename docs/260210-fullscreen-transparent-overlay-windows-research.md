# Fullscreen Transparent Overlay Windows in macOS

**Research Date:** 2026-02-10
**Focus:** Swift/AppKit hybrid approaches for fullscreen overlays with transparency, blur, and animations

---

## 1. Creating Fullscreen Transparent NSWindow

### Pattern: Non-Activating Panel
Use `NSPanel` with `.nonactivatingPanel` to prevent background apps from deactivating/blurring.

```swift
final class OverlayWindow: NSPanel {
  init(screen: NSScreen) {
    super.init(
      contentRect: screen.frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    configureWindow()
  }

  private func configureWindow() {
    isFloatingPanel = true
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    ignoresMouseEvents = false
    acceptsMouseMovedEvents = true
    isReleasedWhenClosed = false
    hidesOnDeactivate = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    animationBehavior = .none  // Disable default animations
  }

  // Prevent focus stealing
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
```

**Key Properties:**
- `isFloatingPanel = true` - Stays above regular windows
- `backgroundColor = .clear` - Fully transparent base
- `.nonactivatingPanel` - Prevents background window deactivation
- `canBecomeKey/Main = false` - Never steals focus

---

## 2. Blur Effects with NSVisualEffectView

### Static Blur Overlay
```swift
let blurView = NSVisualEffectView(frame: window.contentView!.bounds)
blurView.material = .hudWindow  // or .popover, .menu, .sidebar
blurView.blendingMode = .behindWindow
blurView.state = .active
blurView.autoresizingMask = [.width, .height]
window.contentView?.addSubview(blurView)
```

### Animated Blur In/Out
```swift
// Blur In
blurView.alphaValue = 0
NSAnimationContext.runAnimationGroup { context in
  context.duration = 0.3
  context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
  blurView.animator().alphaValue = 1.0
}

// Blur Out
NSAnimationContext.runAnimationGroup { context in
  context.duration = 0.2
  blurView.animator().alphaValue = 0
} completionHandler: {
  window.orderOut(nil)
}
```

### SwiftUI Integration
```swift
struct BlurOverlayView: NSViewRepresentable {
  @Binding var isVisible: Bool

  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .hudWindow
    view.blendingMode = .behindWindow
    view.state = .active
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.3
      nsView.animator().alphaValue = isVisible ? 1.0 : 0.0
    }
  }
}
```

---

## 3. Window Level Hierarchy

macOS window levels (lowest to highest):

```swift
.normal              // 0 - Regular app windows
.floating            // 3 - Utility panels, stays above .normal
.statusBar           // 25 - Status bar level
.popUpMenu           // 101 - Popups, context menus
.screenSaver         // 1000 - Screen saver, area selection
.dock                // 20 - Dock level (read-only)

// Custom levels
NSWindow.Level(rawValue: Int)
```

**Pattern from codebase:**
```swift
// Area selection (above everything)
level = .screenSaver

// Recording overlay (above apps, below toolbar)
level = .floating

// Toolbar (above overlay)
level = .popUpMenu

// Annotation overlay (between overlay and toolbar)
level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
```

---

## 4. Opacity Animations

### NSWindow Fade In/Out
```swift
// Fade In
window.alphaValue = 0
window.orderFrontRegardless()  // Show without activation
NSAnimationContext.runAnimationGroup { context in
  context.duration = 0.25
  window.animator().alphaValue = 1.0
}

// Fade Out with completion
NSAnimationContext.runAnimationGroup { context in
  context.duration = 0.2
  window.animator().alphaValue = 0
} completionHandler: {
  window.orderOut(nil)
}
```

### Disable Default Animations
```swift
window.animationBehavior = .none  // Instant show/hide
```

---

## 5. Best Practices

### Performance Optimization
- **Window pooling:** Pre-allocate windows at launch, reuse via `orderFront/orderOut`
- **CALayer rendering:** Use `wantsLayer = true` and CAShapeLayer for 60fps updates
- **Disable implicit animations:** Set layer actions to `NSNull()`

```swift
layer.actions = ["position": NSNull(), "bounds": NSNull(), "path": NSNull()]
```

### Multi-Screen Support
```swift
// Create one overlay per screen
for screen in NSScreen.screens {
  let overlay = OverlayWindow(screen: screen)
  overlay.setFrame(screen.frame, display: false)
  overlay.orderFrontRegardless()
}

// Handle screen changes
NotificationCenter.default.addObserver(
  forName: NSApplication.didChangeScreenParametersNotification,
  object: nil,
  queue: .main
) { _ in
  refreshOverlays()
}
```

### Mouse Event Handling
```swift
// Pass-through mode (ignore all mouse events)
window.ignoresMouseEvents = true

// Interactive mode
window.ignoresMouseEvents = false
window.acceptsMouseMovedEvents = true

// Accept first click without activation
override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
```

### Cursor Management
```swift
override func cursorUpdate(with event: NSEvent) {
  NSCursor.crosshair.set()
}

override func resetCursorRects() {
  addCursorRect(bounds, cursor: .crosshair)
}
```

---

## Common Pitfalls

1. **Window stealing focus:** Use `NSPanel` + `.nonactivatingPanel`, not `NSWindow`
2. **Background apps blur:** Set `canBecomeKey/Main = false`
3. **Slow activation:** Pre-allocate windows, use `orderFrontRegardless()` not `makeKeyAndOrderFront()`
4. **Animation jank:** Use CALayer updates with disabled actions, not `needsDisplay`
5. **Multi-screen issues:** Listen to `didChangeScreenParametersNotification`

---

## References from Codebase

- `/Users/duongductrong/Developer/ZapShot/Snapzy/Core/AreaSelectionWindow.swift` - Window pooling, CALayer rendering
- `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Recording/RecordingRegionOverlayWindow.swift` - Non-activating panel pattern
- `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Recording/Annotation/RecordingAnnotationOverlayWindow.swift` - SwiftUI hybrid, window levels
