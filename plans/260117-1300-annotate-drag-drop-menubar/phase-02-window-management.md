# Phase 02: Window Management

## Context

- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** [Phase 01: State Architecture](./phase-01-state-architecture.md)
- **Docs:** README.md, development-rules.md

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-17 |
| Priority | High |
| Status | Pending |
| Estimated Effort | 1 hour |

Extend AnnotateManager and AnnotateWindowController to support opening empty annotation windows without initial image.

## Key Insights

1. AnnotateManager uses ScreenshotItem.id as key for window tracking
2. Empty windows need synthetic ID since no ScreenshotItem exists
3. Window sizing currently based on image dimensions - need default for empty
4. Single empty window sufficient (reuse if already open)

## Requirements

1. Add `openEmptyAnnotation()` method to AnnotateManager
2. Create alternative AnnotateWindowController initializer for empty state
3. Define default window size for empty annotation window
4. Track empty window separately from screenshot-based windows
5. Support dynamic window resizing when image is loaded

## Architecture

```
AnnotateManager
├── windowControllers: [UUID: AnnotateWindowController]  // Existing
├── emptyWindowController: AnnotateWindowController?     // New
├── openAnnotation(for: ScreenshotItem)                  // Existing
├── openEmptyAnnotation()                                // New
└── closeAll()                                           // Update to include empty

AnnotateWindowController
├── init(item: ScreenshotItem)           // Existing
├── init()                               // New: empty window
├── state: AnnotateState
└── resizeToFitImage()                   // New: called after image load
```

## Related Code Files

| File | Purpose |
|------|---------|
| `ZapShot/Features/Annotate/AnnotateManager.swift` | Add openEmptyAnnotation method |
| `ZapShot/Features/Annotate/Window/AnnotateWindowController.swift` | Add empty initializer |

## Implementation Steps

### Step 1: Add empty window tracking to AnnotateManager

```swift
@MainActor
final class AnnotateManager {
    static let shared = AnnotateManager()

    private var windowControllers: [UUID: AnnotateWindowController] = [:]
    private var emptyWindowController: AnnotateWindowController?

    // ... existing code
}
```

### Step 2: Implement openEmptyAnnotation()

```swift
func openEmptyAnnotation() {
    // Reuse existing empty window if open
    if let existing = emptyWindowController {
        existing.showWindow()
        return
    }

    let controller = AnnotateWindowController()
    emptyWindowController = controller

    // Clear reference when window closes
    if let window = controller.window {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.emptyWindowController = nil
            }
        }
    }

    controller.showWindow()
}
```

### Step 3: Update closeAll()

```swift
func closeAll() {
    for controller in windowControllers.values {
        controller.window?.close()
    }
    windowControllers.removeAll()

    emptyWindowController?.window?.close()
    emptyWindowController = nil
}
```

### Step 4: Add empty initializer to AnnotateWindowController

```swift
init() {
    self.state = AnnotateState()  // Empty state

    // Default window size for empty canvas
    let screen = NSScreen.main ?? NSScreen.screens.first!
    let defaultWidth: CGFloat = 900
    let defaultHeight: CGFloat = 700

    let origin = NSPoint(
        x: (screen.frame.width - defaultWidth) / 2,
        y: (screen.frame.height - defaultHeight) / 2
    )

    let window = AnnotateWindow(
        contentRect: NSRect(origin: origin, size: NSSize(width: defaultWidth, height: defaultHeight))
    )

    super.init(window: window)
    setupContent()
}
```

### Step 5: Add window resize method

```swift
func resizeToFitImage() {
    guard let image = state.sourceImage,
          let window = window,
          let screen = window.screen ?? NSScreen.main else { return }

    let maxWidth = screen.frame.width * 0.8
    let maxHeight = screen.frame.height * 0.8
    let imageSize = image.size

    let scale = min(maxWidth / imageSize.width, maxHeight / imageSize.height, 1.0)
    let windowWidth = max(800, imageSize.width * scale + 280)
    let windowHeight = max(600, imageSize.height * scale + 120)

    let newFrame = NSRect(
        x: window.frame.midX - windowWidth / 2,
        y: window.frame.midY - windowHeight / 2,
        width: windowWidth,
        height: windowHeight
    )

    window.setFrame(newFrame, display: true, animate: true)
}
```

### Step 6: Subscribe to image changes for auto-resize

In setupContent or init, observe state.sourceImage changes:

```swift
private var cancellables = Set<AnyCancellable>()

private func setupContent() {
    let capturedState = self.state
    let mainView = AnnotateMainView(state: capturedState)
    window?.contentView = NSHostingView(rootView: mainView)

    // Auto-resize when image loaded
    state.$sourceImage
        .dropFirst()  // Skip initial value
        .compactMap { $0 }
        .first()  // Only resize once on first image
        .sink { [weak self] _ in
            self?.resizeToFitImage()
        }
        .store(in: &cancellables)
}
```

## Todo

- [ ] Add emptyWindowController property to AnnotateManager
- [ ] Implement openEmptyAnnotation() method
- [ ] Update closeAll() to handle empty window
- [ ] Add empty init() to AnnotateWindowController
- [ ] Add resizeToFitImage() method
- [ ] Add Combine subscription for auto-resize on image load
- [ ] Import Combine in AnnotateWindowController
- [ ] Test empty window opens correctly
- [ ] Test window resizes after image drop

## Success Criteria

1. `AnnotateManager.shared.openEmptyAnnotation()` opens annotation window
2. Empty window shows at centered 900x700 default size
3. Calling openEmptyAnnotation() twice reuses same window
4. Window resizes appropriately when image is loaded
5. closeAll() closes empty window too
6. Existing screenshot-based flow unaffected

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Window lifecycle issues | Medium | Medium | Proper notification cleanup |
| Memory leak from observers | Low | Medium | Use weak self in closures |
| Animation jank on resize | Low | Low | Use native animated resize |

## Security Considerations

- No additional security concerns for this phase

## Next Steps

After completion, proceed to [Phase 03: Drag-Drop Implementation](./phase-03-drag-drop-implementation.md)
