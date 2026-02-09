# Phase 4: Transparent Drawing Overlay Window

- **Date**: 2026-02-09
- **Priority**: High (Core feature)
- **Status**: Pending

## Overview
Transparent NSWindow covering the recording area where users draw annotations. Annotations rendered via CoreGraphics (reusing AnnotationRenderer). This window is VISIBLE to ScreenCaptureKit and appears in the recorded video.

## Critical Insight
**ScreenCaptureKit captures by display region, not by app.** Our app (Snapzy) is excluded from capture via `excludingApplications`. But we NEED this overlay to be captured. Solution options:

### Option A: Separate helper process (complex)
Create a helper XPC service that owns the overlay window → not excluded from capture.

### Option B: Use `exceptingWindows` (preferred)
The capture filter uses `excludingApplications` + `exceptingWindows`. We add the overlay window to `exceptingWindows` so it's included despite our app being excluded.

**Chosen: Option B** — ScreenCaptureKit's `exceptingWindows` parameter re-includes specific windows from excluded apps. We just need to find the overlay's `SCWindow` and add it to the exception list.

## Requirements
1. Transparent NSWindow covering recording rect exactly
2. Handles mouse events when annotation tool != selection
3. Pass-through mouse events when tool == selection
4. Renders completed annotations + in-progress strokes via AnnotationRenderer
5. Must be included in ScreenCaptureKit capture via `exceptingWindows`
6. Window level: between recording area and toolbar (`.floating + 1` or `.statusBar`)

## Architecture

### New File: `Snapzy/Features/Recording/Annotation/RecordingAnnotationOverlayWindow.swift` (~180 lines)
```swift
@MainActor
class RecordingAnnotationOverlayWindow: NSWindow {
  let annotationState: RecordingAnnotationState
  private var canvasView: RecordingAnnotationCanvasView!

  // Toggle mouse interactivity based on tool
  var isDrawingMode: Bool {
    didSet { ignoresMouseEvents = !isDrawingMode }
  }
}
```

### New File: `Snapzy/Features/Recording/Annotation/RecordingAnnotationCanvasView.swift` (~180 lines)
NSView handling mouse events + rendering:
```swift
class RecordingAnnotationCanvasView: NSView {
  // Mouse tracking
  var isDrawing = false
  var drawStart: CGPoint = .zero
  var currentPath: [CGPoint] = []

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    // Clear background (transparent)
    context.clear(bounds)
    // Draw all annotations
    let renderer = AnnotationRenderer(context: context)
    for annotation in state.annotations {
      renderer.draw(annotation)
    }
    // Draw in-progress stroke
    if isDrawing {
      renderer.drawCurrentStroke(...)
    }
  }

  override func mouseDown(with event: NSEvent) { ... }
  override func mouseDragged(with event: NSEvent) { ... }
  override func mouseUp(with event: NSEvent) {
    // Use AnnotationFactory to create annotation
    if let annotation = AnnotationFactory.createAnnotation(...) {
      state.annotations.append(annotation)
    }
  }
}
```

## Coordinate System
- Overlay window positioned exactly over recording rect
- Mouse coordinates relative to window (no complex transforms needed)
- No scaling — 1:1 screen coordinates
- No Y-flip needed (NSView uses bottom-left origin, same as AnnotationItem)

## Mouse Event Flow
```
Tool == selection → ignoresMouseEvents = true (pass-through)
Tool != selection → intercept mouse events for drawing
mouseDown → record start point, isDrawing = true
mouseDragged → append to currentPath, setNeedsDisplay
mouseUp → AnnotationFactory.createAnnotation → append to state
```

## ScreenCaptureKit Integration
In `ScreenRecordingManager.prepareRecording()`:
```swift
// Find overlay window's SCWindow
let content = try await SCShareableContent.current
let overlayWindow = content.windows.first {
  $0.windowID == overlayNSWindow.windowNumber
}
// Add to exceptingWindows
let filter = SCContentFilter(
  display: display,
  excludingApplications: excludedApps,
  exceptingWindows: existingExceptions + [overlayWindow]
)
```

## Implementation Steps
1. Create `RecordingAnnotationOverlayWindow` with transparent config
2. Create `RecordingAnnotationCanvasView` with mouse handling
3. Implement AnnotationRenderer integration for drawing
4. Implement pass-through toggle (ignoresMouseEvents)
5. Test that overlay appears in ScreenCaptureKit capture
6. Handle overlay window positioning to match recording rect

## Success Criteria
- Annotations drawn on overlay visible in recorded video
- Pass-through works when selection tool active
- Drawing works for all 7 tools
- No visual artifacts (fully transparent background)
