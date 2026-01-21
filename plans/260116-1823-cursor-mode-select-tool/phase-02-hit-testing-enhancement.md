# Phase 02: Hit Testing Enhancement

## Context Links
- [Main Plan](./plan.md)
- [Previous: Phase 01](./phase-01-toolbar-integration.md)
- Related: `ZapShot/Features/Annotate/Canvas/CanvasDrawingView.swift`
- Related: `ZapShot/Features/Annotate/State/AnnotationItem.swift`

## Overview

| Field | Value |
|-------|-------|
| Date | 260116 |
| Description | Improve hit detection for non-rectangular annotations |
| Priority | High |
| Status | Pending |
| Effort | 1 day |

## Key Insights

1. **Current implementation uses bounds only** - `hitTestAnnotation` checks if point is inside `annotation.bounds` rectangle
2. **Inaccurate for lines/arrows** - A diagonal arrow has large bounding box with mostly empty space
3. **Path annotations need stroke tolerance** - Freehand paths need distance-based hit testing
4. **Ovals need ellipse math** - Point-in-ellipse calculation required
5. **Existing reverse iteration** - Already handles z-order correctly (topmost first)

## Requirements

### Functional
- [ ] Accurate hit detection for arrow annotations (line proximity)
- [ ] Accurate hit detection for line annotations (line proximity)
- [ ] Accurate hit detection for oval annotations (ellipse containment)
- [ ] Accurate hit detection for path/pencil annotations (polyline proximity)
- [ ] Accurate hit detection for highlight annotations (polyline proximity)
- [ ] Maintain existing behavior for rectangle, text, counter, blur (bounds-based OK)

### Non-Functional
- [ ] Hit tolerance of 8-10 points for thin strokes
- [ ] Performance: O(n) where n = annotation count (current behavior)
- [ ] No false positives on empty space within bounding box

## Architecture

### Hit Test Strategy by Annotation Type

| Type | Strategy | Tolerance |
|------|----------|-----------|
| rectangle | Bounds contains point | 0 (exact) |
| oval | Point-in-ellipse formula | 0 (exact) |
| arrow | Distance to line segment | strokeWidth + 6pt |
| line | Distance to line segment | strokeWidth + 6pt |
| path | Distance to polyline | strokeWidth + 6pt |
| highlight | Distance to polyline | strokeWidth * 3 + 6pt |
| text | Bounds contains point | 0 (exact) |
| counter | Distance to center | radius (12pt) |
| blur | Bounds contains point | 0 (exact) |

### Mathematical Formulas

**Point-to-line-segment distance**:
```
Given segment (x1,y1)-(x2,y2) and point (px,py):
1. Project point onto infinite line
2. Clamp to segment bounds
3. Return Euclidean distance to clamped point
```

**Point-in-ellipse**:
```
Given ellipse with center (cx,cy), radii (rx,ry):
((px-cx)/rx)^2 + ((py-cy)/ry)^2 <= 1
```

## Related Code Files

| File | Lines | Change Type |
|------|-------|-------------|
| `Canvas/CanvasDrawingView.swift` | 96-103 | Modify `hitTestAnnotation` |
| `State/AnnotationItem.swift` | - | Add `containsPoint(_:tolerance:)` method |

## Implementation Steps

### Step 1: Add Hit Test Extension to AnnotationItem

**File**: `ZapShot/Features/Annotate/State/AnnotationItem.swift`

Add extension after `AnnotationProperties` struct:

```swift
// MARK: - Hit Testing

extension AnnotationItem {
  /// Check if point hits this annotation with appropriate tolerance
  func containsPoint(_ point: CGPoint, baseTolerance: CGFloat = 6) -> Bool {
    let tolerance = baseTolerance + properties.strokeWidth / 2

    switch type {
    case .rectangle, .blur:
      return bounds.contains(point)

    case .oval:
      return pointInEllipse(point, in: bounds)

    case .arrow(let start, let end), .line(let start, let end):
      return distanceToSegment(point, from: start, to: end) <= tolerance

    case .path(let points), .highlight(let points):
      let adjustedTolerance = type.isHighlight ? tolerance * 3 : tolerance
      return distanceToPolyline(point, points: points) <= adjustedTolerance

    case .text:
      return bounds.contains(point)

    case .counter:
      let center = CGPoint(x: bounds.midX, y: bounds.midY)
      let radius: CGFloat = 12 + baseTolerance
      return hypot(point.x - center.x, point.y - center.y) <= radius
    }
  }

  // MARK: - Geometry Helpers

  private func pointInEllipse(_ point: CGPoint, in rect: CGRect) -> Bool {
    let cx = rect.midX
    let cy = rect.midY
    let rx = rect.width / 2
    let ry = rect.height / 2

    guard rx > 0, ry > 0 else { return false }

    let dx = (point.x - cx) / rx
    let dy = (point.y - cy) / ry
    return (dx * dx + dy * dy) <= 1
  }

  private func distanceToSegment(_ point: CGPoint, from start: CGPoint, to end: CGPoint) -> CGFloat {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = dx * dx + dy * dy

    guard lengthSquared > 0 else {
      return hypot(point.x - start.x, point.y - start.y)
    }

    // Project point onto line, clamped to segment
    var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
    t = max(0, min(1, t))

    let projX = start.x + t * dx
    let projY = start.y + t * dy

    return hypot(point.x - projX, point.y - projY)
  }

  private func distanceToPolyline(_ point: CGPoint, points: [CGPoint]) -> CGFloat {
    guard points.count >= 2 else {
      if let first = points.first {
        return hypot(point.x - first.x, point.y - first.y)
      }
      return .infinity
    }

    var minDistance: CGFloat = .infinity
    for i in 0..<(points.count - 1) {
      let dist = distanceToSegment(point, from: points[i], to: points[i + 1])
      minDistance = min(minDistance, dist)
    }
    return minDistance
  }
}
```

### Step 2: Update hitTestAnnotation in CanvasDrawingView

**File**: `ZapShot/Features/Annotate/Canvas/CanvasDrawingView.swift`

```swift
// Before (lines 96-103)
private func hitTestAnnotation(at point: CGPoint) -> AnnotationItem? {
  for annotation in state.annotations.reversed() {
    if annotation.bounds.contains(point) {
      return annotation
    }
  }
  return nil
}

// After
private func hitTestAnnotation(at point: CGPoint) -> AnnotationItem? {
  for annotation in state.annotations.reversed() {
    // Quick bounds check first (optimization)
    let expandedBounds = annotation.bounds.insetBy(dx: -10, dy: -10)
    guard expandedBounds.contains(point) else { continue }

    // Precise hit test
    if annotation.containsPoint(point) {
      return annotation
    }
  }
  return nil
}
```

### Step 3: Update selectAnnotation in AnnotateState

**File**: `ZapShot/Features/Annotate/State/AnnotateState.swift`

```swift
// Before (lines 178-188)
func selectAnnotation(at point: CGPoint) -> AnnotationItem? {
  // Find annotation at point (in reverse order to select topmost)
  for annotation in annotations.reversed() {
    if annotation.bounds.contains(point) {
      selectedAnnotationId = annotation.id
      return annotation
    }
  }
  selectedAnnotationId = nil
  return nil
}

// After
func selectAnnotation(at point: CGPoint) -> AnnotationItem? {
  // Find annotation at point (in reverse order to select topmost)
  for annotation in annotations.reversed() {
    // Quick bounds check first
    let expandedBounds = annotation.bounds.insetBy(dx: -10, dy: -10)
    guard expandedBounds.contains(point) else { continue }

    // Precise hit test
    if annotation.containsPoint(point) {
      selectedAnnotationId = annotation.id
      return annotation
    }
  }
  selectedAnnotationId = nil
  return nil
}
```

## Todo List

- [ ] Add `containsPoint(_:tolerance:)` to AnnotationItem extension
- [ ] Add `pointInEllipse` helper method
- [ ] Add `distanceToSegment` helper method
- [ ] Add `distanceToPolyline` helper method
- [ ] Update `hitTestAnnotation` in CanvasDrawingView
- [ ] Update `selectAnnotation` in AnnotateState
- [ ] Test arrow selection accuracy
- [ ] Test line selection accuracy
- [ ] Test oval selection accuracy
- [ ] Test path/pencil selection accuracy
- [ ] Test counter selection accuracy
- [ ] Verify rectangle/text/blur still work correctly

## Success Criteria

1. Clicking near (within 6-10pt) a thin arrow line selects it
2. Clicking in empty space within arrow bounding box does NOT select
3. Oval selection only triggers inside ellipse shape
4. Freehand path selection works along the stroke
5. Counter selection works within circle area
6. Rectangle/text/blur maintain bounds-based selection
7. No performance degradation with 50+ annotations

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Edge cases with very small annotations | Medium | Low | Minimum 20pt size enforced in resize |
| Performance with many path points | Low | Medium | Bounds pre-check optimization |
| Float precision issues | Low | Low | Use standard CGFloat math |

## Security Considerations

None - geometry calculations with no external data.

## Next Steps

After completing this phase:
1. Proceed to [Phase 03: Property Binding](./phase-03-property-binding.md)
2. Selection accuracy enables meaningful property editing
