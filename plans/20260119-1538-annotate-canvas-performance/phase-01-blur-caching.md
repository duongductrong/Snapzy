# Phase 1: Blur Effect Caching

**Status: ✅ COMPLETED**
**Date Completed: 2026-01-19**

## Objective
Cache pixelated blur regions as CGImage to avoid per-frame recomputation.

## Current Problem
`BlurEffectRenderer.drawPixelatedRegion()` executes expensive operations every frame:
- Creates CGImage from NSImage (line 33)
- Reads raw pixel data via CFDataGetBytePtr (lines 92-97)
- Nested loops sampling pixels O(rows * cols) (lines 103-132)
- Called for EVERY blur annotation on EVERY draw cycle

## Solution
Render blur once when annotation created/resized, cache as CGImage, blit cached image during draw.

## Implementation Steps

### Step 1: Add cached image to AnnotationItem
File: `ZapShot/Features/Annotate/Models/AnnotationItem.swift`

```swift
struct AnnotationItem: Identifiable, Equatable {
    // ... existing properties ...

    /// Cached rendered content for expensive effects (blur)
    var cachedImage: CGImage?
    var cacheNeedsUpdate: Bool = true

    // Exclude from Equatable (cache is derived state)
    static func == (lhs: AnnotationItem, rhs: AnnotationItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.type == rhs.type &&
        lhs.bounds == rhs.bounds &&
        lhs.properties == rhs.properties
    }
}
```

### Step 2: Create BlurCacheManager
File: `ZapShot/Features/Annotate/Canvas/BlurCacheManager.swift` (NEW)

```swift
import AppKit
import CoreGraphics

/// Manages cached blur images for annotation items
final class BlurCacheManager {
    private var cache: [UUID: CGImage] = [:]

    /// Get or create cached blur image
    func getCachedBlur(
        for annotation: AnnotationItem,
        sourceImage: NSImage,
        pixelSize: CGFloat = BlurEffectRenderer.defaultPixelSize
    ) -> CGImage? {
        // Return cached if valid
        if let cached = cache[annotation.id], !annotation.cacheNeedsUpdate {
            return cached
        }

        // Render to offscreen context
        guard let rendered = renderBlurToImage(
            bounds: annotation.bounds,
            sourceImage: sourceImage,
            pixelSize: pixelSize
        ) else { return nil }

        cache[annotation.id] = rendered
        return rendered
    }

    /// Invalidate cache for annotation (call on bounds change)
    func invalidate(id: UUID) {
        cache.removeValue(forKey: id)
    }

    /// Clear all cache
    func clearAll() {
        cache.removeAll()
    }

    private func renderBlurToImage(
        bounds: CGRect,
        sourceImage: NSImage,
        pixelSize: CGFloat
    ) -> CGImage? {
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        guard width > 0, height > 0 else { return nil }

        // Create bitmap context
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Translate to local coordinates
        context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)

        // Render blur
        BlurEffectRenderer.drawPixelatedRegion(
            in: context,
            sourceImage: sourceImage,
            region: bounds,
            pixelSize: pixelSize
        )

        return context.makeImage()
    }
}
```

### Step 3: Integrate cache into AnnotationRenderer
File: `ZapShot/Features/Annotate/Canvas/AnnotationRenderer.swift`

Modify `drawBlur` method:

```swift
// Add property
var blurCacheManager: BlurCacheManager?

private func drawBlur(bounds: CGRect, annotationId: UUID) {
    guard let sourceImage = sourceImage else {
        BlurEffectRenderer.drawBlurPreview(in: context, region: bounds, strokeColor: NSColor.gray.cgColor)
        return
    }

    // Try cached version first
    if let cacheManager = blurCacheManager,
       let annotation = annotations?.first(where: { $0.id == annotationId }),
       let cachedImage = cacheManager.getCachedBlur(for: annotation, sourceImage: sourceImage) {
        context.draw(cachedImage, in: bounds)
        return
    }

    // Fallback to direct render
    BlurEffectRenderer.drawPixelatedRegion(in: context, sourceImage: sourceImage, region: bounds)
}
```

### Step 4: Update DrawingCanvasNSView
File: `ZapShot/Features/Annotate/Canvas/CanvasDrawingView.swift`

```swift
final class DrawingCanvasNSView: NSView {
    // Add cache manager
    private let blurCacheManager = BlurCacheManager()

    // In draw(_:) method, pass cache to renderer
    let renderer = AnnotationRenderer(
        context: context,
        editingTextId: state.editingTextAnnotationId,
        sourceImage: state.sourceImage,
        blurCacheManager: blurCacheManager  // NEW
    )

    // Invalidate cache when bounds change
    // In updateAnnotationBounds handling:
    if case .blur = annotation.type {
        blurCacheManager.invalidate(id: annotation.id)
    }
}
```

### Step 5: Invalidate on resize/move end
In `mouseUp` after resize/drag completes, mark blur cache for update:

```swift
// After resize ends
if isResizingAnnotation, let selectedId = state.selectedAnnotationId {
    if let annotation = state.annotations.first(where: { $0.id == selectedId }),
       case .blur = annotation.type {
        blurCacheManager.invalidate(id: selectedId)
    }
}
```

## Testing Checklist
- [ ] Blur renders correctly on creation
- [ ] Cached blur displays identically to direct render
- [ ] Moving blur annotation is smooth (no per-frame computation)
- [ ] Resizing blur updates correctly after mouseUp
- [ ] Multiple blur regions render without conflict
- [ ] Memory usage stable (no leak from cached images)

## Success Metrics
- Frame time during blur drag: <5ms (was ~30-50ms)
- CPU spike eliminated during blur movement
- Profile confirms `drawPixelatedRegion` only called on create/resize-end

## Rollback
Remove `BlurCacheManager`, revert `AnnotationRenderer` changes. No other code affected.

## Risk Assessment
- **LOW** - Additive change, fallback to direct render if cache fails
- Cache invalidation must be correct to avoid stale renders
