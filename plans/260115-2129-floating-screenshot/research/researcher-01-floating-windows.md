# macOS Floating Window Implementation - Research Report

## Executive Summary

This report covers macOS floating window patterns for screenshot preview features. Key findings include NSWindow configuration for always-on-top panels, SwiftUI hosting in NSWindow, focus behavior management, and animation patterns.

## Key Findings

### 1. NSWindow Floating Panel Configuration

```swift
class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Floating configuration
        self.level = .floating  // Above normal windows
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false  // Stay visible when app loses focus
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true

        // Collection behavior for spaces
        self.collectionBehavior = [
            .canJoinAllSpaces,      // Visible on all spaces
            .stationary,            // Don't move with space switches
            .fullScreenAuxiliary    // Work with fullscreen apps
        ]
    }

    override var canBecomeKey: Bool { false }  // Don't steal focus
    override var canBecomeMain: Bool { false }
}
```

### 2. NSWindow Level Options

| Level | Use Case |
|-------|----------|
| `.floating` | Standard floating panels |
| `.modalPanel` | Above floating windows |
| `.screenSaver` | Above everything except alerts |
| `.statusBar` | Menu bar level |

For screenshot previews, `.floating` is ideal - visible but not intrusive.

### 3. SwiftUI Hosting in NSWindow

```swift
class FloatingWindowController {
    private var window: NSPanel?

    func showFloatingView<Content: View>(_ content: Content, at position: NSPoint) {
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 300)

        let panel = FloatingPanel(contentRect: hostingView.frame)
        panel.contentView = hostingView
        panel.setFrameOrigin(position)
        panel.orderFrontRegardless()

        self.window = panel
    }
}
```

### 4. Non-Focus-Stealing Windows

Key properties to prevent focus theft:
- `styleMask: .nonactivatingPanel` - Won't activate app
- `canBecomeKey: false` - Won't become key window
- `canBecomeMain: false` - Won't become main window
- Use `orderFrontRegardless()` instead of `makeKeyAndOrderFront()`

### 5. Mouse Tracking Without Focus

```swift
// Enable mouse events without being key window
panel.acceptsMouseMovedEvents = true
panel.ignoresMouseEvents = false

// Add tracking area to content view
let trackingArea = NSTrackingArea(
    rect: view.bounds,
    options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved],
    owner: view,
    userInfo: nil
)
view.addTrackingArea(trackingArea)
```

### 6. Position Anchoring Patterns

```swift
enum FloatingPosition {
    case topLeft, topRight, bottomLeft, bottomRight, custom(NSPoint)

    func calculateOrigin(for size: NSSize, on screen: NSScreen) -> NSPoint {
        let frame = screen.visibleFrame
        let padding: CGFloat = 20

        switch self {
        case .topLeft:
            return NSPoint(x: frame.minX + padding, y: frame.maxY - size.height - padding)
        case .topRight:
            return NSPoint(x: frame.maxX - size.width - padding, y: frame.maxY - size.height - padding)
        case .bottomLeft:
            return NSPoint(x: frame.minX + padding, y: frame.minY + padding)
        case .bottomRight:
            return NSPoint(x: frame.maxX - size.width - padding, y: frame.minY + padding)
        case .custom(let point):
            return point
        }
    }
}
```

### 7. Animation for Card Appearance

```swift
// SwiftUI animation for new cards
struct FloatingCard: View {
    @State private var appeared = false

    var body: some View {
        CardContent()
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.8)
            .offset(y: appeared ? 0 : 20)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    appeared = true
                }
            }
    }
}
```

## Implementation Recommendations

1. Use `NSPanel` with `.nonactivatingPanel` for non-intrusive floating
2. Host SwiftUI views via `NSHostingView`
3. Set `.floating` level - high enough but not obnoxious
4. Use `.activeAlways` tracking areas for hover without focus
5. Animate card appearance with spring animations for polish

## Common Pitfalls

- Using `makeKeyAndOrderFront()` steals focus - use `orderFrontRegardless()`
- Forgetting `hidesOnDeactivate = false` causes window to disappear
- Not setting `collectionBehavior` properly breaks multi-space behavior

## Timestamp

2026-01-15 21:30:00 UTC
