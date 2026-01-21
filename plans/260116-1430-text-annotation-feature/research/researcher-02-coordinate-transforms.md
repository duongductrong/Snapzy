# Research: Coordinate Transformations for Scalable Annotations

**Date:** 2026-01-16

## 1. Existing Pattern in ZapShot

Annotations store coordinates in **image space** (original image pixels). Display transforms using `displayScale`.

```swift
// Storage (image coords)
annotation.bounds = CGRect(x: 100, y: 50, width: 150, height: 24)

// Display (screen coords)
let displayBounds = CGRect(
  x: bounds.x * displayScale,
  y: bounds.y * displayScale,
  width: bounds.width * displayScale,
  height: bounds.height * displayScale
)
```

## 2. Font Size Scaling Strategy

**Option A: Scale font with displayScale** (Recommended)
- Store fontSize in image coords (e.g., 16pt at 1:1)
- Render at fontSize (context already scaled)
- Consistent with other annotations

**Option B: Fixed visual size**
- Divide fontSize by displayScale when rendering
- Text stays same screen size regardless of zoom
- Inconsistent with arrows/shapes

**Recommendation:** Option A - font scales with image like other annotations.

## 3. SwiftUI Overlay Positioning

```swift
// Convert image bounds to display position
let displayX = annotation.bounds.origin.x * scale + imageOffset.x
let displayY = annotation.bounds.origin.y * scale + imageOffset.y

TextField(...)
  .frame(width: annotation.bounds.width * scale)
  .position(x: displayX + (annotation.bounds.width * scale) / 2,
            y: displayY + (annotation.bounds.height * scale) / 2)
```

## 4. Coordinate Spaces in SwiftUI

```swift
GeometryReader { geometry in
  // geometry.size = container size
  // Use .local coordinate space for overlay positioning

  overlay
    .coordinateSpace(name: "canvas")
}
```

## 5. Text Bounds Auto-Sizing

Calculate text size at image scale, store in image coords:

```swift
func calculateTextBounds(text: String, fontSize: CGFloat, at point: CGPoint) -> CGRect {
  let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: fontSize)
  ]
  let size = (text as NSString).size(withAttributes: attributes)
  return CGRect(x: point.x, y: point.y - size.height, width: size.width + 8, height: size.height + 4)
}
```

## 6. Export Considerations

Export renders at 1:1 (no displayScale). Text draws correctly since:
- Bounds in image coords
- Font size in image coords
- Renderer uses stored values directly
