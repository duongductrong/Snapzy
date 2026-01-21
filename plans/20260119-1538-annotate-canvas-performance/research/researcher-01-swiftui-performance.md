# Research Report: SwiftUI Canvas Performance Optimization

## Executive Summary
SwiftUI Canvas and NSView drawing require careful optimization for real-time interaction. Key strategies include minimizing state changes, caching expensive operations, and leveraging Metal-backed rendering.

## Key Findings

### 1. SwiftUI Canvas Performance Best Practices
- Use `drawingGroup()` modifier to flatten view hierarchies into Metal-backed bitmap
- Minimize `@Published` property updates during gestures
- Avoid recreating views in `body` during drag operations
- Use `equatable()` modifier to prevent unnecessary recomputations

### 2. Handling Drag Gestures with Minimal Lag
- Store gesture state locally, commit to model on `.ended`
- Use `@GestureState` for transient values (auto-resets)
- Debounce rapid state updates during continuous gestures
- Prefer `onChanged` with local state vs immediate model updates

### 3. Optimizing Blur Effects
- **CIFilter Issues**: CPU-bound, not optimized for real-time
- **Metal Solutions**: Use GPU-accelerated blur via Metal shaders
- **Caching Strategy**: Render blur once, cache as CGImage/texture
- Pre-compute blur at annotation creation, not per frame

### 4. Efficient Shape Rendering During Movement
- Separate static content from dynamic (moving) content
- Draw static annotations to cached bitmap layer
- Only redraw moving annotation during drag
- Composite layers on final render

### 5. Common Causes of Frame Drops
- Excessive view recomposition from state changes
- Heavy computations on main thread
- Full canvas redraw instead of dirty rect
- Creating new objects (CGImage, NSImage) per frame
- Synchronous I/O or image decoding

## Implementation Recommendations

```swift
// Example: Separate drag state from model
@State private var dragOffset: CGSize = .zero // Local, fast
@Published var position: CGPoint // Model, update on end

// Example: Cache expensive renders
var cachedBlurImage: CGImage? // Computed once, reused

// Example: Dirty rect optimization
override func draw(_ dirtyRect: NSRect) {
    // Only redraw intersection with dirtyRect
}
```

## Sources
- Apple Developer Documentation - Canvas
- Apple Developer Documentation - DragGesture
- WWDC Sessions on SwiftUI Performance
- SwiftUI Performance guides (Kodeco, SwiftBySundell)
