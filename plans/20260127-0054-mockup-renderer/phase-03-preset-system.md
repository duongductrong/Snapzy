# Phase 3: Preset System

## Context

- **Parent Plan**: [plan.md](./plan.md)
- **Dependencies**: [Phase 1](./phase-01-core-state-and-models.md), [Phase 2](./phase-02-3d-rendering-engine.md)
- **Research**: [SwiftUI 3D Transforms](./research/researcher-01-swiftui-3d-transforms.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-27 |
| Description | Build preset system with thumbnails like CleanShot |
| Priority | Medium |
| Status | `[ ]` Not Started |

## Key Insights

- Presets should be instantly previewable via thumbnails
- CleanShot pattern: horizontal row of small preview buttons
- Thumbnails generated once, cached for performance
- Allow custom presets saved by user

## Requirements

1. Built-in default presets (8-12 variations)
2. Thumbnail preview for each preset
3. One-click preset application
4. Custom preset save/delete support

## Architecture

```swift
// DefaultPresets.swift
struct DefaultPresets {
    static let all: [MockupPreset] = [
        MockupPreset(id: UUID(), name: "Flat", rotationX: 0, rotationY: 0, rotationZ: 0, perspective: 0.5, padding: 40),
        MockupPreset(id: UUID(), name: "Left Tilt", rotationX: 0, rotationY: -25, rotationZ: 0, perspective: 0.5, padding: 40),
        MockupPreset(id: UUID(), name: "Right Tilt", rotationX: 0, rotationY: 25, rotationZ: 0, perspective: 0.5, padding: 40),
        MockupPreset(id: UUID(), name: "Top View", rotationX: 20, rotationY: 0, rotationZ: 0, perspective: 0.4, padding: 40),
        MockupPreset(id: UUID(), name: "Isometric Left", rotationX: 15, rotationY: -30, rotationZ: 0, perspective: 0.3, padding: 50),
        MockupPreset(id: UUID(), name: "Isometric Right", rotationX: 15, rotationY: 30, rotationZ: 0, perspective: 0.3, padding: 50),
        MockupPreset(id: UUID(), name: "Hero Shot", rotationX: 10, rotationY: -20, rotationZ: -5, perspective: 0.4, padding: 60),
        MockupPreset(id: UUID(), name: "Dramatic", rotationX: 25, rotationY: 35, rotationZ: 0, perspective: 0.2, padding: 80),
    ]
}

// PresetThumbnailGenerator.swift
class PresetThumbnailGenerator {
    static func generateThumbnail(for preset: MockupPreset, sampleImage: NSImage) -> NSImage
}
```

## Related Files

| File | Purpose |
|------|---------|
| `Features/Annotate/Background/BackgroundStyle.swift` | Reference for enum pattern with presets |

## Implementation Steps

### Step 1: Create DefaultPresets
- [ ] Create `Features/Annotate/Mockup/Presets/DefaultPresets.swift`
- [ ] Define 8 built-in presets with descriptive names
- [ ] Balance variety: flat, tilts, isometric, dramatic angles
- [ ] Test each preset looks good with sample screenshots

### Step 2: Create PresetThumbnailGenerator
- [ ] Create thumbnail generation using ImageRenderer
- [ ] Use small sample image (placeholder screenshot)
- [ ] Render at 80x60px for compact preview
- [ ] Cache thumbnails in memory

### Step 3: Add preset management to MockupState
- [ ] Add `@Published var presets: [MockupPreset]` (defaults + custom)
- [ ] Add `applyPreset(_ preset: MockupPreset)` method
- [ ] Add `saveCustomPreset(name: String)` method
- [ ] Add `deletePreset(_ preset: MockupPreset)` method

### Step 4: Implement preset persistence
- [ ] Save custom presets to UserDefaults or JSON file
- [ ] Load custom presets on init
- [ ] Merge with default presets (defaults first)

### Step 5: Create PresetButton view
- [ ] Thumbnail image with border
- [ ] Selected state indicator
- [ ] Hover effect
- [ ] Tap to apply preset

## Todo

- [ ] DefaultPresets.swift with 8 presets
- [ ] PresetThumbnailGenerator working
- [ ] Preset apply/save/delete methods
- [ ] Persistence implemented
- [ ] PresetButton view created

## Success Criteria

- All default presets render correctly
- Thumbnails accurately represent preset appearance
- Preset application is instant (<50ms)
- Custom presets persist across app launches
- UI clearly shows selected preset

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Thumbnail generation slow | Generate async, show placeholder |
| Too many presets clutter UI | Limit to 12 visible, scrollable |
| Preset values look bad | User test each preset, iterate |

## Security Considerations

- Sanitize custom preset names
- Validate preset JSON on load

## Next Steps

Proceed to [Phase 4: UI Components](./phase-04-ui-components.md)
