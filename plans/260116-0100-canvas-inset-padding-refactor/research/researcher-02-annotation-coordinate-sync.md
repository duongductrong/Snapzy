# Annotation Coordinate Synchronization

## Executive Summary

Annotations must be stored in image-relative coordinates (not display coordinates) to maintain consistency between canvas display and export. Transformation functions handle conversion between coordinate systems.

## Key Findings

### 1. Layered Coordinate Systems

- **Image Coordinates**: Raw pixel positions on original image (0,0 to imageWidth,imageHeight)
- **Display Coordinates**: Positions on scaled/padded canvas view
- **Export Coordinates**: Final output positions (may include padding offset)

### 2. Coordinate Transformation

**Image to Display (for rendering on canvas):**
```swift
func imageToDisplay(point: CGPoint, scale: CGFloat, offset: CGPoint) -> CGPoint {
    CGPoint(
        x: point.x * scale + offset.x,
        y: point.y * scale + offset.y
    )
}
```

**Display to Image (for user input):**
```swift
func displayToImage(point: CGPoint, scale: CGFloat, offset: CGPoint) -> CGPoint {
    CGPoint(
        x: (point.x - offset.x) / scale,
        y: (point.y - offset.y) / scale
    )
}
```

### 3. Current ZapShot Implementation Analysis

Current code stores annotations in display coordinates matching image size. The exporter offsets by padding. This works because:
- Annotations are drawn relative to image frame
- Export adds padding offset to all annotation coordinates

### 4. Inset Padding Impact

With inset padding, the display scale changes but image coordinates stay same:
- Container size: fixed
- Available space: container - (padding * 2)
- Display scale: availableSpace / imageSize
- Annotations: still stored relative to original image size

### 5. WYSIWYG Export Strategy

Option A (Current): Export at original image size + padding
- Image exports at full resolution
- Annotations offset by padding value

Option B (Inset): Export matches display proportions
- Calculate export size based on aspect ratio
- Scale annotations proportionally

## Implementation Recommendation

For inset padding refactor:
1. Keep annotation storage in image-relative coordinates
2. Modify display to apply additional scaling based on available space
3. Exporter continues to work unchanged (original image + padding)

```swift
// Canvas display
let displayScale = min(
    availableWidth / imageWidth,
    availableHeight / imageHeight
)

// Annotations drawn at: annotationPoint * displayScale
// But STORED at: original image coordinates

// Export renders at: original image size + padding
// Annotations offset by padding (existing logic works)
```

## Coordinate Flow Diagram

```
User Input → Display Coords → ÷ displayScale → Image Coords (stored)
                                                      ↓
Export ← Image Coords + padding offset ← Image Coords (retrieved)
```

## Unresolved Questions

- Whether to support different export sizes (1x, 2x, etc.)
- Handling annotations that extend beyond image bounds
