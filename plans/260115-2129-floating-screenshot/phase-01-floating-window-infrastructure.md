# Phase 01: Floating Window Infrastructure

## Context

- [Main Plan](./plan.md)
- [Research: Floating Windows](./research/researcher-01-floating-windows.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 260115 |
| Description | Create NSPanel-based floating window infrastructure for hosting SwiftUI content |
| Priority | High |
| Status | `pending` |
| Estimated Effort | 2-3 hours |

## Requirements

1. **FloatingPanel class** - NSPanel subclass with correct configuration
2. **FloatingPanelController** - manages panel lifecycle, positioning, content hosting
3. **FloatingPosition enum** - screen corner positions with calculation logic
4. **Non-focus-stealing** - panel must not activate app or steal keyboard focus
5. **Multi-space support** - visible across all desktop spaces
6. **Mouse tracking** - enable hover detection without focus

## Architecture

```
FloatingPanelController
├── panel: FloatingPanel (NSPanel)
├── hostingView: NSHostingView<Content>
├── position: FloatingPosition
└── methods:
    ├── show<Content: View>(_ content: Content)
    ├── updateContent<Content: View>(_ content: Content)
    ├── updatePosition(_ position: FloatingPosition)
    ├── updateSize(_ size: CGSize)
    └── hide()

FloatingPanel (NSPanel subclass)
├── styleMask: [.borderless, .nonactivatingPanel]
├── level: .floating
├── collectionBehavior: [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
├── hidesOnDeactivate: false
├── canBecomeKey: false
└── canBecomeMain: false

FloatingPosition (enum)
├── topLeft
├── topRight
├── bottomLeft
├── bottomRight
└── calculateOrigin(for size: CGSize, on screen: NSScreen) -> CGPoint
```

## Related Files

| File | Action | Purpose |
|------|--------|---------|
| `ZapShot/Features/FloatingScreenshot/FloatingPanel.swift` | Create | NSPanel subclass |
| `ZapShot/Features/FloatingScreenshot/FloatingPanelController.swift` | Create | Panel management |
| `ZapShot/Features/FloatingScreenshot/FloatingPosition.swift` | Create | Position enum |

## Implementation Steps

### Step 1: Create FloatingPosition enum

```swift
// FloatingPosition.swift
enum FloatingPosition: String, CaseIterable, Codable {
    case topLeft, topRight, bottomLeft, bottomRight

    func calculateOrigin(for size: CGSize, on screen: NSScreen, padding: CGFloat = 20) -> CGPoint {
        let frame = screen.visibleFrame
        switch self {
        case .topLeft:
            return CGPoint(x: frame.minX + padding, y: frame.maxY - size.height - padding)
        case .topRight:
            return CGPoint(x: frame.maxX - size.width - padding, y: frame.maxY - size.height - padding)
        case .bottomLeft:
            return CGPoint(x: frame.minX + padding, y: frame.minY + padding)
        case .bottomRight:
            return CGPoint(x: frame.maxX - size.width - padding, y: frame.minY + padding)
        }
    }
}
```

### Step 2: Create FloatingPanel class

```swift
// FloatingPanel.swift
class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel()
    }

    private func configurePanel() {
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // Cards have own shadows
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

### Step 3: Create FloatingPanelController

```swift
// FloatingPanelController.swift
@MainActor
final class FloatingPanelController {
    private var panel: FloatingPanel?
    private var position: FloatingPosition = .bottomRight
    private let padding: CGFloat = 20

    func show<Content: View>(_ content: Content, size: CGSize) {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let origin = position.calculateOrigin(for: size, on: screen, padding: padding)
        let frame = NSRect(origin: origin, size: size)

        let panel = FloatingPanel(contentRect: frame)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hostingView
        panel.orderFrontRegardless()

        self.panel = panel
    }

    func updateContent<Content: View>(_ content: Content) {
        guard let panel = panel else { return }
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        panel.contentView = hostingView
    }

    func updatePosition(_ newPosition: FloatingPosition) {
        position = newPosition
        repositionPanel()
    }

    func updateSize(_ size: CGSize) {
        guard let panel = panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let origin = position.calculateOrigin(for: size, on: screen, padding: padding)
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: true)
    }

    func hide() {
        panel?.close()
        panel = nil
    }

    private func repositionPanel() {
        guard let panel = panel else { return }
        let size = panel.frame.size
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let origin = position.calculateOrigin(for: size, on: screen, padding: padding)
        panel.setFrameOrigin(origin)
    }
}
```

### Step 4: Create directory structure

Create `ZapShot/Features/FloatingScreenshot/` directory.

## Todo List

- [ ] Create `Features/FloatingScreenshot` directory
- [ ] Implement `FloatingPosition.swift`
- [ ] Implement `FloatingPanel.swift`
- [ ] Implement `FloatingPanelController.swift`
- [ ] Test panel appears at correct position
- [ ] Test panel does not steal focus
- [ ] Test panel visible across spaces
- [ ] Test mouse hover works without focus

## Success Criteria

1. Panel appears at configured screen corner
2. Panel stays above other windows (level = .floating)
3. Clicking panel does not activate ZapShot app
4. Panel visible when switching desktop spaces
5. Mouse events (hover) work without keyboard focus
6. Panel can be shown/hidden programmatically

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Panel steals focus on click | Medium | High | Ensure `.nonactivatingPanel` + `canBecomeKey = false` |
| Panel disappears on app deactivate | Medium | Medium | Set `hidesOnDeactivate = false` |
| Incorrect position calculation | Low | Low | Use `visibleFrame` not `frame` to respect menu bar/dock |
| Memory leak from panel | Low | Medium | Properly nil out panel in `hide()` |
