# Phase 2: 3D Rendering Engine

## Context

- **Parent Plan**: [plan.md](./plan.md)
- **Dependencies**: [Phase 1](./phase-01-core-state-and-models.md)
- **Research**: [SwiftUI 3D Transforms](./research/researcher-01-swiftui-3d-transforms.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-27 |
| Description | Implement 3D transformation rendering with rotation3DEffect |
| Priority | High |
| Status | `[ ]` Not Started |

## Key Insights

- Chain multiple `rotation3DEffect` for X, Y, Z axes
- Order matters: typically Y -> X -> Z for intuitive control
- Perspective parameter controls vanishing point depth
- Shadow should match rotation direction for realism
- Anchor at `.center` for natural rotation feel

## Requirements

1. Apply 3D rotations on all three axes
2. Configurable perspective depth
3. Dynamic shadow that follows rotation
4. Smooth real-time preview (<16ms frame time)

## Architecture

```swift
// Mockup3DRenderer.swift
struct Mockup3DRenderer: View {
    @ObservedObject var state: MockupState

    var body: some View {
        imageView
            .rotation3DEffect(.degrees(state.rotationY), axis: (x: 0, y: 1, z: 0), perspective: state.perspective)
            .rotation3DEffect(.degrees(state.rotationX), axis: (x: 1, y: 0, z: 0), perspective: state.perspective)
            .rotation3DEffect(.degrees(state.rotationZ), axis: (x: 0, y: 0, z: 1))
            .shadow(color: .black.opacity(state.shadowIntensity), radius: shadowRadius, x: shadowX, y: shadowY)
    }

    private var shadowX: CGFloat { state.rotationY * 0.5 }
    private var shadowY: CGFloat { state.rotationX * 0.5 }
}
```

## Related Files

| File | Purpose |
|------|---------|
| `Features/Annotate/Canvas/AnnotateCanvasView.swift` | Reference for canvas structure |
| `Features/Annotate/Canvas/BlurEffectRenderer.swift` | Performance optimization patterns |

## Implementation Steps

### Step 1: Create Mockup3DRenderer view
- [ ] Create `Features/Annotate/Mockup/Rendering/Mockup3DRenderer.swift`
- [ ] Add image display with resizable/aspectRatio
- [ ] Chain rotation3DEffect modifiers (Y -> X -> Z order)
- [ ] Add perspective parameter to Y and X rotations

### Step 2: Implement dynamic shadow
- [ ] Calculate shadow offset based on rotation angles
- [ ] shadowX = rotationY * factor, shadowY = rotationX * factor
- [ ] Scale shadow radius with perspective
- [ ] Apply shadow with configurable intensity

### Step 3: Add corner radius support
- [ ] Apply clipShape with RoundedRectangle
- [ ] Ensure clipping happens before rotation
- [ ] Match corner radius to state.cornerRadius

### Step 4: Optimize for real-time preview
- [ ] Use @StateObject to prevent re-initialization
- [ ] Minimize view hierarchy depth
- [ ] Cache transformed image for static preview
- [ ] Add animation(.interactiveSpring) for smooth updates

### Step 5: Handle edge cases
- [ ] Nil image placeholder view
- [ ] Extreme rotation values clamping
- [ ] Very low perspective handling (prevent divide issues)

## Todo

- [ ] Mockup3DRenderer.swift created
- [ ] Rotation chain implemented
- [ ] Dynamic shadow working
- [ ] Corner radius applied
- [ ] Performance validated (<16ms)

## Success Criteria

- Rotations apply correctly on all axes
- Perspective creates realistic depth effect
- Shadow follows rotation direction
- Preview updates at 60fps during slider drag
- No visual artifacts at extreme angles

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Poor performance on complex images | Limit preview resolution, use thumbnail |
| Rotation order confusion | Document Y->X->Z order, match UI slider order |
| Perspective artifacts at extremes | Clamp perspective to 0.1-1.0 range |

## Security Considerations

- None specific to this phase

## Next Steps

Proceed to [Phase 3: Preset System](./phase-03-preset-system.md)
