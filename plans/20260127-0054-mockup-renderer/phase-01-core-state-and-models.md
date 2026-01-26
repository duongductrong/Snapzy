# Phase 1: Core State and Models

## Context

- **Parent Plan**: [plan.md](./plan.md)
- **Dependencies**: None (foundational phase)
- **Research**: [SwiftUI 3D Transforms](./research/researcher-01-swiftui-3d-transforms.md)
- **Scout**: [Annotate Module](./scout/scout-01-annotate-module.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-27 |
| Description | Create foundational state management and data models |
| Priority | High |
| Status | `[ ]` Not Started |

## Key Insights

- Follow `AnnotateState` pattern: single ObservableObject as source of truth
- Perspective range 0.1-1.0 (lower = stronger depth effect)
- Rotation angles typically -45 to +45 degrees for realistic mockups
- Reuse `BackgroundStyle` enum from Annotate module

## Requirements

1. Central state object with all mockup parameters
2. Preset data model with serializable properties
3. Undo/redo support for parameter changes
4. Integration point with existing Annotate workflow

## Architecture

```swift
// MockupState.swift
@MainActor
class MockupState: ObservableObject {
    @Published var sourceImage: NSImage?
    @Published var rotationX: Double = 0      // -45 to +45
    @Published var rotationY: Double = 0      // -45 to +45
    @Published var rotationZ: Double = 0      // -180 to +180
    @Published var perspective: Double = 0.5  // 0.1 to 1.0
    @Published var padding: CGFloat = 40
    @Published var backgroundStyle: BackgroundStyle = .none
    @Published var shadowIntensity: Double = 0.3
    @Published var selectedPresetId: UUID?
}

// MockupPreset.swift
struct MockupPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var rotationX: Double
    var rotationY: Double
    var rotationZ: Double
    var perspective: Double
    var padding: CGFloat
}
```

## Related Files

| File | Purpose |
|------|---------|
| `Features/Annotate/State/AnnotateState.swift` | Reference pattern |
| `Features/Annotate/Background/BackgroundStyle.swift` | Reuse for backgrounds |

## Implementation Steps

### Step 1: Create MockupPreset model
- [ ] Create `Features/Annotate/Mockup/State/MockupPreset.swift`
- [ ] Define struct with id, name, rotation parameters
- [ ] Add Codable conformance for persistence
- [ ] Add Equatable for comparison

### Step 2: Create MockupState ObservableObject
- [ ] Create `Features/Annotate/Mockup/State/MockupState.swift`
- [ ] Add @Published properties for all parameters
- [ ] Import BackgroundStyle from Annotate module
- [ ] Add computed properties for transform values

### Step 3: Add state methods
- [ ] `applyPreset(_ preset: MockupPreset)` - apply preset values
- [ ] `resetToDefaults()` - reset all parameters
- [ ] `loadImage(from url: URL)` - load source image
- [ ] Parameter validation methods

### Step 4: Add undo/redo support
- [ ] Create state snapshot struct
- [ ] Add undoStack and redoStack
- [ ] Implement saveState(), undo(), redo()
- [ ] Add canUndo, canRedo computed properties

## Todo

- [ ] MockupPreset.swift created
- [ ] MockupState.swift created
- [ ] BackgroundStyle imported/reused
- [ ] Undo/redo implemented
- [ ] Unit tests for state changes

## Success Criteria

- State changes trigger UI updates correctly
- Preset application updates all parameters atomically
- Undo/redo works for parameter changes
- No memory leaks in state management

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| State synchronization issues | Use @MainActor for thread safety |
| Memory bloat from undo stack | Limit stack size to 20 entries |

## Security Considerations

- Validate image URLs before loading
- Sanitize preset names for file system operations

## Next Steps

Proceed to [Phase 2: 3D Rendering Engine](./phase-02-3d-rendering-engine.md)
