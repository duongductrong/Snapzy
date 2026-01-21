# Research Report: macOS Graphics Optimization for Annotation Apps

## Executive Summary
Optimizing macOS drawing apps requires leveraging Core Animation layers, caching strategies, and profiling with Instruments. Key focus areas: offscreen rendering, layer composition, and avoiding per-frame expensive operations.

## Key Findings

### 1. Core Graphics vs Metal
- **Core Graphics**: CPU-based rasterization, good for static/simple paths
- **Metal**: GPU-accelerated, required for real-time complex effects
- **Recommendation**: Use CG for shape drawing, Metal/cached bitmaps for blur

### 2. CALayer Optimization
- `shouldRasterize = true`: Caches layer as bitmap (good for static content)
- Flatten layer hierarchy for composition performance
- Use `drawsAsynchronously` for background rendering
- Separate layers: static annotations vs moving annotation

### 3. Offscreen Rendering Strategies
- **CGLayer**: Deprecated but still works for offscreen drawing
- **CGBitmapContext**: Create offscreen context, draw once, reuse
- **NSBitmapImageRep**: Cache rendered content as image

### 4. Caching Strategies
```swift
// Cache pattern for expensive renders
class CachedAnnotation {
    var cachedImage: CGImage?
    var needsRedraw: Bool = true

    func render(in context: CGContext) {
        if needsRedraw || cachedImage == nil {
            cachedImage = renderToImage()
            needsRedraw = false
        }
        context.draw(cachedImage!, in: bounds)
    }
}
```

### 5. Profiling with Instruments
- **Core Animation**: Check "Color Offscreen-Rendered" (yellow = bad)
- **Time Profiler**: Identify CPU hotspots in draw calls
- **Metal System Trace**: GPU utilization for Metal rendering
- **Allocations**: Memory pressure from image creation

## Implementation Recommendations

1. **Blur Caching**: Render pixelated region once, store as CGImage
2. **Layer Separation**:
   - Layer 1: Static annotations (cached bitmap)
   - Layer 2: Moving annotation (redrawn per frame)
   - Layer 3: Selection handles
3. **Dirty Rect**: Track changed regions, only redraw affected area
4. **Async Rendering**: Compute blur on background queue, update on main

## Sources
- Apple Core Graphics Documentation
- Apple Core Animation Programming Guide
- Apple Metal Documentation
- Instruments User Guide
