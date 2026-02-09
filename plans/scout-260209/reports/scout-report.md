# Recording Annotation Overlay Keyboard Event Handling - Scout Report

## Summary

Found complete implementation of recording annotation overlay keyboard event handling. Key finding: **RecordingAnnotationCanvasView has keyboard event handlers but NO first responder setup**, while **RecordingAnnotationOverlayWindow sets canBecomeKey=true but doesn't call makeFirstResponder**.

## 1. RecordingAnnotationOverlayWindow

**File**: `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Recording/Annotation/RecordingAnnotationOverlayWindow.swift`

### Configuration
- **Window level**: `NSWindow.Level.floating.rawValue + 1` (between overlay and toolbar)
- **Initial mouse state**: `ignoresMouseEvents = true` (pass-through in selection mode)
- **First responder capability**: `override var canBecomeKey: Bool { true }`
- **Main window**: `override var canBecomeMain: Bool { false }`

### Mouse Event Toggling
Lines 57-74 observe tool changes:
```swift
toolCancellable = annotationState.$selectedTool
  .receive(on: RunLoop.main)
  .sink { [weak self] tool in
    let isSelection = (tool == .selection)
    self.ignoresMouseEvents = isSelection
    if !isSelection { self.makeKeyAndOrderFront(nil) }  // ← Makes key but not first responder
  }
```

**Issue**: Calls `makeKeyAndOrderFront` but never calls `window.makeFirstResponder(canvasView)` to direct keyboard events to canvas.

## 2. RecordingAnnotationToolbarWindow

**File**: `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Recording/Annotation/RecordingAnnotationToolbarWindow.swift`

### Configuration
- **Window level**: `.popUpMenu` (above overlay)
- **First responder**: `override var canBecomeKey: Bool { true }`
- **Anchoring**: Child window of `RecordingToolbarWindow` (lines 210-214)
- **Positioning**: Popover-style with arrow, anchors to annotate button

### Show/Hide Logic
Lines 126-136 toggle visibility:
```swift
enabledCancellable = annotationState.$isAnnotationEnabled
  .receive(on: RunLoop.main)
  .sink { [weak self] enabled in
    if enabled {
      self?.showPopover()
    } else {
      self?.detachFromAnchor()
      self?.orderOut(nil)
    }
  }
```

## 3. RecordingAnnotationCanvasView

**File**: `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Recording/Annotation/RecordingAnnotationCanvasView.swift`

### First Responder Setup
Line 33: `override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }`

**Missing**: No `acceptsFirstResponder` override (defaults to false for NSView)

### Keyboard Event Handler
Lines 131-153:
```swift
override func keyDown(with event: NSEvent) {
  // Tool shortcuts using AnnotateShortcutManager
  if let char = event.characters?.lowercased().first {
    let tools = RecordingAnnotationState.availableTools
    if let matchedTool = shortcutManager.tool(for: char),
       tools.contains(matchedTool) {
      state.selectedTool = matchedTool
      needsDisplay = true
      return
    }
  }

  switch event.keyCode {
  case 51, 117:  // Delete / Forward Delete
    state.deleteSelected()
    needsDisplay = true
  case 53:  // Escape — deselect
    state.selectedAnnotationId = nil
    needsDisplay = true
  default:
    super.keyDown(with: event)
  }
}
```

**Handles**: Tool shortcuts (p/h/a/r/e/l), Delete, Escape
**Doesn't handle**: Arrow keys for nudging (unlike CanvasDrawingView which has arrow key nudging)

## 4. RecordingCoordinator

**File**: `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Recording/RecordingCoordinator.swift`

### Annotation Setup
Lines 523-557 create overlay windows:
```swift
private func setupAnnotationOverlay(for rect: CGRect) {
  let annotationState = window.annotationState
  
  // Create overlay window
  let overlayWindow = RecordingAnnotationOverlayWindow(
    recordingRect: rect,
    annotationState: annotationState
  )
  overlayWindow.orderFrontRegardless()
  annotationOverlayWindow = overlayWindow
  
  // Create toolbar window
  let toolbarWin = RecordingAnnotationToolbarWindow(annotationState: annotationState)
  toolbarWin.anchorWindow = window
  toolbarWin.anchorButtonCenterXOffset = window.annotateButtonCenterXOffset
  annotationToolbarWindow = toolbarWin
  
  // Update toolbar position when button offset changes
  window.onAnnotateButtonOffsetChanged = { [weak toolbarWin] offset in
    toolbarWin?.anchorButtonCenterXOffset = offset
    if annotationState.isAnnotationEnabled {
      toolbarWin?.positionRelativeToAnchor()
    }
  }
  
  // Start cleanup timer
  annotationState.startCleanupTimer()
  
  // Add to ScreenCaptureKit exceptingWindows
  Task {
    await recorder.addExceptedWindow(windowID: overlayWindow.overlayWindowID)
  }
}
```

**Missing**: No `makeFirstResponder` call after creating overlay window.

### Escape Key Monitoring
Lines 121-137 global/local NSEvent monitors:
```swift
private func setupEscapeMonitors() {
  localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
    if event.keyCode == 53 {  // Escape key
      self?.handleEscapeKey()
      return nil
    }
    return event
  }
  
  globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
    if event.keyCode == 53 {
      DispatchQueue.main.async {
        self?.handleEscapeKey()
      }
    }
  }
}
```

**Purpose**: Stop recording confirmation, not annotation overlay keyboard handling.

## 5. NSEvent Monitors (All Files)

### RecordingCoordinator.swift
- Lines 122-128: Local monitor for Escape (keyCode 53)
- Lines 130-136: Global monitor for Escape
- **Purpose**: Recording stop/cancel confirmation

### No other NSEvent monitors found for annotation overlay

## 6. IgnoresMouseEvents Toggle Pattern

### RecordingAnnotationOverlayWindow.swift
Lines 59-66:
```swift
toolCancellable = annotationState.$selectedTool
  .sink { [weak self] tool in
    let isSelection = (tool == .selection)
    self.ignoresMouseEvents = isSelection
    if !isSelection { self.makeKeyAndOrderFront(nil) }
  }
```

**Pattern**: 
- Selection tool → `ignoresMouseEvents = true` (pass-through)
- Drawing tools → `ignoresMouseEvents = false` + `makeKeyAndOrderFront`

## Comparison: CanvasDrawingView vs RecordingAnnotationCanvasView

### CanvasDrawingView (Annotate feature)
**File**: `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Annotate/Canvas/CanvasDrawingView.swift`

Lines 89-186:
- **First responder**: `override var acceptsFirstResponder: Bool { true }`
- **Keyboard handlers**: Delete, Escape, Enter, Arrow keys (4 directions), Undo/Redo (Cmd+Z/Shift+Cmd+Z), Tool shortcuts
- **Arrow key nudging**: Lines 128-158 with Shift modifier (1px vs 10px)
- **Crop support**: Escape cancels crop, Enter applies crop

### RecordingAnnotationCanvasView (Recording feature)
- **First responder**: Missing `acceptsFirstResponder` override
- **Keyboard handlers**: Delete, Escape, Tool shortcuts only
- **No arrow key nudging**
- **No crop support**

## Root Cause Analysis

### Why keyboard events aren't working:

1. **RecordingAnnotationCanvasView missing `acceptsFirstResponder`**
   - Defaults to `false` for NSView
   - Window can become key, but view won't accept responder chain

2. **RecordingAnnotationOverlayWindow never calls `makeFirstResponder`**
   - Calls `makeKeyAndOrderFront` on tool change (line 65)
   - Never calls `window.makeFirstResponder(canvasView)`

3. **RecordingCoordinator doesn't set up responder chain**
   - Creates overlay window (line 528)
   - Orders front (line 532)
   - Never establishes first responder

## Unresolved Questions

1. Should RecordingAnnotationCanvasView support arrow key nudging like CanvasDrawingView?
2. Should RecordingCoordinator call `makeFirstResponder` after creating overlay, or should overlay window handle it internally?
3. Do NSEvent monitors interfere with canvas keyboard events when overlay is active?
