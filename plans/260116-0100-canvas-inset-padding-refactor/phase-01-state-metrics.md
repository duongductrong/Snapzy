# Phase 01: State Metrics & Scale Computation

## Objective

Add computed properties to `AnnotateState` for display metrics used by canvas and annotation views.

## File: `AnnotateState.swift`

### Add Computed Properties

```swift
// MARK: - Display Metrics (for inset padding layout)

/// Original image dimensions (points, not pixels)
var imageWidth: CGFloat { sourceImage.size.width }
var imageHeight: CGFloat { sourceImage.size.height }
var imageAspectRatio: CGFloat { imageWidth / imageHeight }

/// Calculate display scale for given container size
/// Image shrinks to fit within (container - padding*2)
func displayScale(for containerSize: CGSize, margin: CGFloat = 40) -> CGFloat {
    let availableWidth = containerSize.width - margin * 2
    let availableHeight = containerSize.height - margin * 2

    // Available space for image after padding
    let imageAreaWidth = max(availableWidth - padding * 2, 1)
    let imageAreaHeight = max(availableHeight - padding * 2, 1)

    let scaleX = imageAreaWidth / imageWidth
    let scaleY = imageAreaHeight / imageHeight

    return min(scaleX, scaleY, 1.0) // Don't scale up
}

/// Calculate image offset within container based on alignment
func imageOffset(for containerSize: CGSize, imageDisplaySize: CGSize, margin: CGFloat = 40) -> CGPoint {
    let availableWidth = containerSize.width - margin * 2
    let availableHeight = containerSize.height - margin * 2

    let extraWidth = availableWidth - padding * 2 - imageDisplaySize.width
    let extraHeight = availableHeight - padding * 2 - imageDisplaySize.height

    let xOffset: CGFloat
    let yOffset: CGFloat

    switch imageAlignment {
    case .center:
        xOffset = extraWidth / 2
        yOffset = extraHeight / 2
    case .topLeft:
        xOffset = 0
        yOffset = extraHeight
    case .topRight:
        xOffset = extraWidth
        yOffset = extraHeight
    case .bottomLeft:
        xOffset = 0
        yOffset = 0
    case .bottomRight:
        xOffset = extraWidth
        yOffset = 0
    }

    return CGPoint(x: xOffset, y: yOffset)
}
```

### Location in File

Insert after line 42 (`@Published var aspectRatio`) and before `// MARK: - Annotations`.

## Validation

- [ ] Properties compile without errors
- [ ] `displayScale` returns smaller values as padding increases
- [ ] `imageOffset` respects `imageAlignment` setting

## Dependencies

None - this phase is foundational.

## Next Phase

Phase 02 uses these metrics in `AnnotateCanvasView`.
