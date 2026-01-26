# SwiftUI 3D Transformations Research

Research on rotation3DEffect, perspective transformations, and 3D mockup rendering for macOS.

---

## 1. rotation3DEffect API

### Core Parameters

```swift
.rotation3DEffect(
    angle: Angle,
    axis: (x: CGFloat, y: CGFloat, z: CGFloat),
    anchor: UnitPoint = .center,
    anchorZ: CGFloat = 0,
    perspective: CGFloat = 1
)
```

**Parameters:**
- `angle`: Rotation amount in degrees/radians
- `axis`: 3D rotation axis. Examples:
  - `(x: 0, y: 1, z: 0)` - Y-axis rotation (horizontal spin)
  - `(x: 1, y: 0, z: 0)` - X-axis rotation (vertical tilt)
  - `(x: 0, y: 0, z: 1)` - Z-axis rotation (flat spin)
- `anchor`: Unit point for rotation origin (default: `.center`)
- `anchorZ`: Z-axis location for rotation center (default: 0)
- `perspective`: Relative vanishing point control for depth effect

### Basic Example

```swift
Image("screenshot")
    .rotation3DEffect(
        .degrees(30),
        axis: (x: 0, y: 1, z: 0)
    )
```

---

## 2. Perspective & ProjectionTransform

### ProjectionEffect Modifier

For advanced perspective distortion, use `ProjectionEffect` with `ProjectionTransform`:

```swift
var transform = CATransform3DIdentity
transform.m34 = -1.0 / 500.0  // Perspective depth (camera distance)
transform = CATransform3DRotate(transform, .pi / 6, 1, 0, 0)

view.projectionEffect(ProjectionTransform(transform))
```

### Perspective Skew Technique

Using `CGAffineTransform` for 2D perspective illusion:

```swift
var transform = CGAffineTransform.identity
transform.c = tan(0.7)  // Skew factor for perspective

view.transformEffect(transform)
```

**Enhancement tip:** Combine with gradients and shadows to amplify depth illusion.

### CATransform3D (Lower-Level Approach)

For UIKit/AppKit layer manipulation:

```swift
var transform = CATransform3DIdentity
transform.m34 = -1.0 / 1000.0  // Key property for z-axis perspective
transform = CATransform3DRotate(transform, angle, x, y, z)
layer.transform = transform
```

The `m34` matrix cell controls perspective strength. Smaller denominators = stronger perspective.

---

## 3. Best Practices for Combining Transformations

### Layering Multiple Effects

```swift
Image("mockup")
    .rotation3DEffect(.degrees(45), axis: (x: 0, y: 1, z: 0))
    .scaleEffect(1.2)
    .shadow(radius: 10, x: 5, y: 5)  // Depth enhancement
```

### Optimization Strategies

**View Body Efficiency:**
- Keep `body` computations lightweight
- Move heavy calculations to `@StateObject` or computed properties
- Use `@EquatableView` to prevent unnecessary redraws

**Layout Optimization:**
- Flatten view hierarchies (avoid deep nesting)
- Use lazy containers (`LazyVStack`, `LazyHGrid`) for large collections
- Combine similar modifiers into single applications

**GPU-Heavy Modifiers:**
- Minimize `.blur()`, `.shadow()`, `.mask()` in animated contexts
- These trigger expensive offscreen rendering
- Consolidate effects into single `.overlay()` when possible

**Animation Control:**
- Avoid simultaneous layout + opacity animations
- Limit animations on large view hierarchies
- Disable non-critical animations for performance

### State Management

```swift
@StateObject private var viewModel = MockupViewModel()

var body: some View {
    mockupView
        .rotation3DEffect(
            .degrees(viewModel.rotationAngle),
            axis: viewModel.rotationAxis
        )
}
```

Use `@StateObject` to prevent re-initialization on view updates.

---

## 4. Performance Considerations

### Real-Time Preview Optimization

**Critical practices:**
- Use `Instruments` (SwiftUI template) to profile render frequency
- Monitor layout costs and memory usage
- Apply `Self._printChanges()` during development to debug re-renders

**Concurrency:**
- Offload calculations to background threads using `Task` API
- Cache expensive resources (formatted strings, processed images)

**Architecture:**
- MVVM pattern separates logic from views
- Centralize state to reduce duplication
- Isolate complex components to limit impact

### macOS-Specific Improvements

Recent SwiftUI updates (2025-2026) brought significant macOS performance enhancements:
- Faster list loading
- Improved overall update cycles
- Better GPU acceleration for 3D effects

### VisionOS Context (Future-Proofing)

SwiftUI on visionOS 26 includes:
- Volumetric features with depth alignments
- Layout-aware rotations
- Enhanced 3D modifier support
- `.materialEffect()` for "Liquid Glass" depth-aware effects

---

## 5. Known Limitations: macOS vs iOS

### Behavioral Differences

**Animation Discrepancies:**
- `rotation3DEffect` can behave/align differently between platforms
- Same code may require platform-specific adjustments
- Test thoroughly on both platforms

**Interaction Models:**
- iOS: Touch-based (direct manipulation)
- macOS: Mouse/keyboard (indirect interaction)
- May affect how 3D rotations feel to users

**Platform Conditionals:**

```swift
#if os(macOS)
    .rotation3DEffect(.degrees(30), axis: (x: 0, y: 1, z: 0))
#else
    .rotation3DEffect(.degrees(45), axis: (x: 0, y: 1, z: 0))
#endif
```

### Maturity Differences

- SwiftUI on macOS historically more limited than iOS
- Many Mac apps still rely on AppKit for complex features
- Gap narrowing with recent updates but platform-specific quirks remain

### Rendering Framework Differences

- iOS: UIKit-based rendering
- macOS: AppKit-based rendering
- Subtle variations in how modifiers are rendered/animated
- GPU acceleration availability may differ

### Design Adaptability

"One look for all devices" challenging with SwiftUI:
- Large macOS displays vs small iOS screens require different approaches
- Rotation effects may need tweaking per platform
- Consider screen size and interaction paradigm in design

---

## Implementation Recommendations for Mockup Renderer

### Suggested Approach

```swift
struct MockupRenderer: View {
    @State private var rotationX: Double = 0
    @State private var rotationY: Double = 0

    var body: some View {
        Image("screenshot")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .rotation3DEffect(
                .degrees(rotationX),
                axis: (x: 1, y: 0, z: 0),
                anchor: .center,
                anchorZ: 0,
                perspective: 0.5  // Adjust for desired depth
            )
            .rotation3DEffect(
                .degrees(rotationY),
                axis: (x: 0, y: 1, z: 0)
            )
            .shadow(radius: 20, x: 10, y: 10)
    }
}
```

### Key Considerations

1. **Perspective value:** Lower = stronger depth (0.1-1.0 range typical)
2. **Shadow placement:** Match rotation direction for realism
3. **Anchor points:** Use `.center` for natural rotation feel
4. **Performance:** Cache transformed images if static, avoid real-time for high-res

---

## Sources

- [Apple Developer - rotation3DEffect](https://apple.com)
- [Medium - SwiftUI ProjectionEffect for 3D Perspective](https://medium.com)
- [Medium - SwiftUI Performance Best Practices 2026](https://medium.com)
- [Kodeco - 3D Transforms Tutorial](https://kodeco.com)
- [Stack Overflow - SwiftUI 3D Transformations](https://stackoverflow.com)
- [Agent Hicks - SwiftUI Performance Optimization](https://agenthicks.com)
- [Sachith UK - SwiftUI 3D Best Practices](https://sachith.co.uk)
- [Reddit - SwiftUI Platform Differences](https://reddit.com)
- [Flying Harley Dev - Cross-Platform SwiftUI](https://flyingharley.dev)
