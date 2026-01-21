# Plan: Resize Select-Area Feature for Recording

**Date:** 2026-01-18
**Status:** Draft
**Complexity:** Medium

## Overview

Add edge and corner resize handles to the recording region overlay during the preparation phase, allowing users to resize the selected area before recording starts.

## Current State Analysis

- `RecordingRegionOverlayView` supports:
  - Drag inside selection → move region
  - Drag outside selection → create new selection
- Missing: resize capability via edge/corner handles

## Implementation Plan

### Task 1: Add ResizeHandle Enum and Constants

**File:** `ZapShot/Features/Recording/RecordingRegionOverlayWindow.swift`

Add enum and constants for resize handle detection:

```swift
/// Resize handle positions
enum ResizeHandle {
  case topLeft, top, topRight
  case left, right
  case bottomLeft, bottom, bottomRight
}

// Constants
private let handleHitSize: CGFloat = 10.0  // Hit detection area
private let handleVisualSize: CGFloat = 8.0  // Visual handle size
private let minimumSelectionSize: CGFloat = 50.0
```

### Task 2: Add Resize State Properties

**File:** `ZapShot/Features/Recording/RecordingRegionOverlayWindow.swift`

Add to `RecordingRegionOverlayView`:

```swift
// Resize state
private var isResizing = false
private var activeHandle: ResizeHandle?
private var resizeStartRect: CGRect = .zero
private var resizeStartPoint: CGPoint = .zero
```

### Task 3: Implement Handle Hit-Testing

**File:** `ZapShot/Features/Recording/RecordingRegionOverlayWindow.swift`

Add method to detect which handle (if any) is under cursor:

```swift
private func handleAt(point: CGPoint) -> ResizeHandle? {
  let rect = localHighlightRect()
  let hs = handleHitSize

  // Corner handles (check first, higher priority)
  if CGRect(x: rect.minX - hs, y: rect.maxY - hs, width: hs*2, height: hs*2).contains(point) { return .topLeft }
  if CGRect(x: rect.maxX - hs, y: rect.maxY - hs, width: hs*2, height: hs*2).contains(point) { return .topRight }
  if CGRect(x: rect.minX - hs, y: rect.minY - hs, width: hs*2, height: hs*2).contains(point) { return .bottomLeft }
  if CGRect(x: rect.maxX - hs, y: rect.minY - hs, width: hs*2, height: hs*2).contains(point) { return .bottomRight }

  // Edge handles
  if CGRect(x: rect.midX - hs, y: rect.maxY - hs, width: hs*2, height: hs*2).contains(point) { return .top }
  if CGRect(x: rect.midX - hs, y: rect.minY - hs, width: hs*2, height: hs*2).contains(point) { return .bottom }
  if CGRect(x: rect.minX - hs, y: rect.midY - hs, width: hs*2, height: hs*2).contains(point) { return .left }
  if CGRect(x: rect.maxX - hs, y: rect.midY - hs, width: hs*2, height: hs*2).contains(point) { return .right }

  return nil
}
```

### Task 4: Implement Cursor Feedback

**File:** `ZapShot/Features/Recording/RecordingRegionOverlayWindow.swift`

Add cursor helper and update `mouseMoved`:

```swift
private func cursorFor(handle: ResizeHandle) -> NSCursor {
  switch handle {
  case .topLeft, .bottomRight: return .resizeNorthwestSoutheast  // Custom or use arrow
  case .topRight, .bottomLeft: return .resizeNortheastSouthwest
  case .top, .bottom: return .resizeUpDown
  case .left, .right: return .resizeLeftRight
  }
}
```

Note: macOS doesn't have diagonal resize cursors built-in. Options:
- Use `NSCursor.arrow` with custom image
- Use `NSCursor.crosshair` as fallback
- Create custom cursor images

### Task 5: Update Mouse Event Handlers

**File:** `ZapShot/Features/Recording/RecordingRegionOverlayWindow.swift`

Modify `mouseDown`, `mouseDragged`, `mouseUp`, `mouseMoved`:

**mouseDown:**
```swift
// Check for resize handle first
if let handle = handleAt(point: point) {
  isResizing = true
  activeHandle = handle
  resizeStartRect = highlightRect
  resizeStartPoint = point
  return
}
// Existing drag/reselect logic...
```

**mouseDragged:**
```swift
if isResizing, let handle = activeHandle {
  let delta = CGPoint(x: point.x - resizeStartPoint.x, y: point.y - resizeStartPoint.y)
  let newRect = calculateResizedRect(handle: handle, delta: delta)
  overlayWindow.interactionDelegate?.overlay(overlayWindow, didResizeRegionTo: newRect)
  return
}
// Existing logic...
```

**mouseUp:**
```swift
if isResizing {
  isResizing = false
  activeHandle = nil
  overlayWindow.interactionDelegate?.overlayDidFinishResizing(overlayWindow)
  return
}
// Existing logic...
```

### Task 6: Implement Resize Calculation

**File:** `ZapShot/Features/Recording/RecordingRegionOverlayWindow.swift`

```swift
private func calculateResizedRect(handle: ResizeHandle, delta: CGPoint) -> CGRect {
  var rect = resizeStartRect
  let minSize = minimumSelectionSize

  switch handle {
  case .topLeft:
    rect.origin.x += delta.x
    rect.size.width -= delta.x
    rect.size.height += delta.y
  case .top:
    rect.size.height += delta.y
  case .topRight:
    rect.size.width += delta.x
    rect.size.height += delta.y
  case .left:
    rect.origin.x += delta.x
    rect.size.width -= delta.x
  case .right:
    rect.size.width += delta.x
  case .bottomLeft:
    rect.origin.x += delta.x
    rect.origin.y += delta.y
    rect.size.width -= delta.x
    rect.size.height -= delta.y
  case .bottom:
    rect.origin.y += delta.y
    rect.size.height -= delta.y
  case .bottomRight:
    rect.origin.y += delta.y
    rect.size.width += delta.x
    rect.size.height -= delta.y
  }

  // Enforce minimum size
  if rect.width < minSize { rect.size.width = minSize }
  if rect.height < minSize { rect.size.height = minSize }

  return rect
}
```

### Task 7: Update Delegate Protocol

**File:** `ZapShot/Features/Recording/RecordingRegionOverlayWindow.swift`

Add resize methods to `RecordingRegionOverlayDelegate`:

```swift
func overlay(_ overlay: RecordingRegionOverlayWindow, didResizeRegionTo rect: CGRect)
func overlayDidFinishResizing(_ overlay: RecordingRegionOverlayWindow)
```

### Task 8: Implement Delegate in RecordingCoordinator

**File:** `ZapShot/Features/Recording/RecordingCoordinator.swift`

```swift
func overlay(_ overlay: RecordingRegionOverlayWindow, didResizeRegionTo rect: CGRect) {
  updateSelectedRect(rect)
}

func overlayDidFinishResizing(_ overlay: RecordingRegionOverlayWindow) {
  // Optional: persist or log
}
```

### Task 9: Draw Visual Resize Handles

**File:** `ZapShot/Features/Recording/RecordingRegionOverlayWindow.swift`

Add to `draw(_:)` when `showBorder` is true:

```swift
private func drawResizeHandles(for rect: CGRect) {
  let size = handleVisualSize
  let halfSize = size / 2

  NSColor.white.setFill()

  let handlePositions: [CGPoint] = [
    CGPoint(x: rect.minX, y: rect.maxY),  // topLeft
    CGPoint(x: rect.midX, y: rect.maxY),  // top
    CGPoint(x: rect.maxX, y: rect.maxY),  // topRight
    CGPoint(x: rect.minX, y: rect.midY),  // left
    CGPoint(x: rect.maxX, y: rect.midY),  // right
    CGPoint(x: rect.minX, y: rect.minY),  // bottomLeft
    CGPoint(x: rect.midX, y: rect.minY),  // bottom
    CGPoint(x: rect.maxX, y: rect.minY),  // bottomRight
  ]

  for pos in handlePositions {
    let handleRect = CGRect(x: pos.x - halfSize, y: pos.y - halfSize, width: size, height: size)
    let path = NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2)
    path.fill()
  }
}
```

## File Changes Summary

| File | Changes |
|------|---------|
| `RecordingRegionOverlayWindow.swift` | Add ResizeHandle enum, state props, hit-testing, resize calc, cursor feedback, visual handles, update mouse handlers |
| `RecordingCoordinator.swift` | Implement new delegate methods for resize |

## Testing Checklist

- [ ] Resize from all 8 handles works correctly
- [ ] Minimum size constraint enforced
- [ ] Cursor changes on hover over handles
- [ ] Toolbar position updates during resize
- [ ] Resize handles hidden during recording
- [ ] Interaction disabled during recording

## Unresolved Questions

None - requirements are clear and implementation path is straightforward.
