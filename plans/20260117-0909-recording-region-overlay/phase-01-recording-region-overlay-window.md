# Phase 01: Recording Region Overlay Window

## Context
- **Parent Plan**: [plan.md](./plan.md)
- **Dependencies**: None
- **Reference Docs**: README.md

## Overview
- **Date**: 2026-01-17
- **Description**: Create persistent overlay window that shows dimmed screen with highlighted recording region
- **Priority**: High
- **Implementation Status**: Not Started
- **Review Status**: Pending

## Key Insights
1. Existing `AreaSelectionOverlayView` in `AreaSelectionWindow.swift` already implements the exact drawing logic needed (dimmed background + clear rect + white border)
2. New overlay must be mouse-passthrough to not interfere with user interaction
3. Window level must be below `RecordingToolbarWindow` (.floating) but above normal windows
4. Must exclude overlay from screen recording capture - use `.floating` level which ScreenCaptureKit excludes by default

## Requirements
1. Show dimmed overlay (40% black) covering all screens
2. Highlight selected recording region with clear area + white border
3. Do not capture mouse events (passthrough)
4. Stay visible from `showToolbar()` until `cleanup()`
5. Support multi-monitor setups
6. Do not appear in the recorded video

## Architecture

```swift
// New file: RecordingRegionOverlayWindow.swift

RecordingRegionOverlayWindow : NSWindow
├── Properties
│   ├── highlightRect: CGRect (in screen coordinates)
│   └── overlayView: RecordingRegionOverlayView
├── Configuration
│   ├── styleMask: .borderless
│   ├── level: .floating (below toolbar, excluded from capture)
│   ├── ignoresMouseEvents: true
│   └── collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]
└── Methods
    └── updateHighlightRect(_:) - for future resizing support

RecordingRegionOverlayView : NSView
├── Properties
│   ├── highlightRect: CGRect
│   ├── dimColor: NSColor.black.withAlphaComponent(0.4)
│   └── borderColor: NSColor.white
└── Methods
    └── draw(_:) - draws dim + clear rect + border
```

## Related Code Files

| File | Action | Purpose |
|------|--------|---------|
| `ZapShot/Features/Recording/RecordingRegionOverlayWindow.swift` | Create | New overlay window + view |
| `ZapShot/Features/Recording/RecordingCoordinator.swift` | Modify | Add overlay management |
| `ZapShot/Core/AreaSelectionWindow.swift` | Reference | Drawing pattern to follow |

## Implementation Steps

### Step 1: Create RecordingRegionOverlayWindow.swift

```swift
// Location: ZapShot/Features/Recording/RecordingRegionOverlayWindow.swift

import AppKit

/// Overlay window showing the recording region highlight
@MainActor
final class RecordingRegionOverlayWindow: NSWindow {

  private let overlayView: RecordingRegionOverlayView

  init(screen: NSScreen, highlightRect: CGRect) {
    self.overlayView = RecordingRegionOverlayView(
      frame: screen.frame,
      highlightRect: highlightRect
    )

    super.init(
      contentRect: screen.frame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )

    configureWindow()
    contentView = overlayView
  }

  private func configureWindow() {
    isOpaque = false
    backgroundColor = .clear
    level = .floating
    ignoresMouseEvents = true
    hasShadow = false
    isReleasedWhenClosed = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
  }

  func updateHighlightRect(_ rect: CGRect) {
    overlayView.highlightRect = rect
    overlayView.needsDisplay = true
  }
}

/// View that draws the dimmed overlay with highlighted region
final class RecordingRegionOverlayView: NSView {

  var highlightRect: CGRect

  private let dimColor = NSColor.black.withAlphaComponent(0.4)
  private let borderColor = NSColor.white
  private let borderWidth: CGFloat = 2.0

  init(frame: CGRect, highlightRect: CGRect) {
    self.highlightRect = highlightRect
    super.init(frame: frame)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    // Draw dim overlay
    dimColor.setFill()
    bounds.fill()

    // Convert screen coords to view coords
    guard let window = window else { return }
    let windowFrame = window.frame
    let localRect = CGRect(
      x: highlightRect.origin.x - windowFrame.origin.x,
      y: highlightRect.origin.y - windowFrame.origin.y,
      width: highlightRect.width,
      height: highlightRect.height
    )

    // Clear the highlight area
    NSColor.clear.setFill()
    localRect.fill(using: .copy)

    // Draw border around highlight
    let borderPath = NSBezierPath(rect: localRect)
    borderPath.lineWidth = borderWidth
    borderColor.setStroke()
    borderPath.stroke()
  }
}
```

### Step 2: Modify RecordingCoordinator.swift

Add overlay management to existing coordinator:

```swift
// Add property after line 21:
private var regionOverlayWindows: [RecordingRegionOverlayWindow] = []

// Add to showToolbar(for:) after line 33 (after creating toolbarWindow):
showRegionOverlay(for: rect)

// Add new method after showToolbar():
private func showRegionOverlay(for rect: CGRect) {
  for screen in NSScreen.screens {
    let overlay = RecordingRegionOverlayWindow(screen: screen, highlightRect: rect)
    overlay.orderFrontRegardless()
    regionOverlayWindows.append(overlay)
  }
}

// Modify cleanup() - add before line 149:
for overlay in regionOverlayWindows {
  overlay.close()
}
regionOverlayWindows.removeAll()
```

## Todo List
- [ ] Create `RecordingRegionOverlayWindow.swift` file
- [ ] Add `RecordingRegionOverlayView` class
- [ ] Add `regionOverlayWindows` property to `RecordingCoordinator`
- [ ] Add `showRegionOverlay(for:)` method
- [ ] Call overlay creation in `showToolbar(for:)`
- [ ] Add overlay cleanup in `cleanup()`
- [ ] Test single monitor
- [ ] Test multi-monitor
- [ ] Verify overlay not captured in recording

## Success Criteria
1. ✅ Overlay appears immediately after area selection
2. ✅ Selected region is clearly highlighted with white border
3. ✅ Rest of screen is dimmed at 40% opacity
4. ✅ Mouse clicks pass through overlay
5. ✅ Overlay visible during pre-record and recording phases
6. ✅ Overlay closes when recording stops/cancels
7. ✅ Overlay does not appear in recorded video
8. ✅ Works on all connected monitors

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Overlay captured in recording | High | Use `.floating` level - ScreenCaptureKit excludes by default |
| Mouse events blocked | High | Set `ignoresMouseEvents = true` |
| Performance impact | Low | Simple drawing, no animations |

## Security Considerations
- No user input handling
- No network access
- No file system access
- Pure UI overlay - minimal security surface

## Next Steps
After implementation:
1. Manual testing on single and multi-monitor setups
2. Verify overlay exclusion from recording
3. Consider adding subtle animation to border (future enhancement)
