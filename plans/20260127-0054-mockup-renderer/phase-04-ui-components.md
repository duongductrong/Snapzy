# Phase 4: UI Components

## Context

- **Parent Plan**: [plan.md](./plan.md)
- **Dependencies**: [Phase 1](./phase-01-core-state-and-models.md), [Phase 2](./phase-02-3d-rendering-engine.md), [Phase 3](./phase-03-preset-system.md)
- **Scout**: [Annotate Module](./scout/scout-01-annotate-module.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-27 |
| Description | Build UI with sidebar sliders and bottom preset bar |
| Priority | Medium |
| Status | `[ ]` Not Started |

## Key Insights

- Follow AnnotateMainView layout: toolbar + sidebar + canvas + bottombar
- Sliders for continuous parameter adjustment
- Bottom bar with horizontal preset thumbnails (CleanShot style)
- Sidebar collapsible for focused preview

## Requirements

1. Main container with toolbar, sidebar, canvas, bottom bar
2. Sidebar with grouped parameter sliders
3. Bottom bar with scrollable preset thumbnails
4. Real-time preview updates during slider drag

## Architecture

```
MockupMainView
├── MockupToolbarView (top)
│   └── Export button, Close button
├── HSplitView
│   ├── MockupSidebarView (left, 250px)
│   │   ├── Rotation Section (X, Y, Z sliders)
│   │   ├── Perspective Section (perspective slider)
│   │   ├── Appearance Section (padding, shadow, corner radius)
│   │   └── Background Section (reuse BackgroundStyle picker)
│   └── MockupCanvasView (center)
│       └── Mockup3DRenderer
└── MockupPresetBar (bottom, 80px)
    └── HStack of PresetButton
```

## Related Files

| File | Purpose |
|------|---------|
| `Features/Annotate/Views/AnnotateMainView.swift` | Layout reference |
| `Features/Annotate/Views/AnnotateSidebarView.swift` | Slider patterns |
| `Features/Annotate/Views/AnnotateBottomBarView.swift` | Bottom bar pattern |

## Implementation Steps

### Step 1: Create MockupMainView
- [ ] Create `Features/Annotate/Mockup/Views/MockupMainView.swift`
- [ ] VStack with toolbar, HSplitView, bottom bar
- [ ] Pass MockupState as @StateObject
- [ ] Handle window sizing (min 800x600)

### Step 2: Create MockupCanvasView
- [ ] Create `Features/Annotate/Mockup/Views/MockupCanvasView.swift`
- [ ] GeometryReader for responsive sizing
- [ ] Center Mockup3DRenderer in available space
- [ ] Apply background from state.backgroundStyle
- [ ] Handle drag-drop for image loading

### Step 3: Create MockupSidebarView
- [ ] Create `Features/Annotate/Mockup/Views/MockupSidebarView.swift`
- [ ] Section: Rotation (X, Y, Z sliders, -45 to +45)
- [ ] Section: Perspective (0.1 to 1.0 slider)
- [ ] Section: Appearance (padding, shadow, corner radius)
- [ ] Section: Background (reuse BackgroundStyle picker)
- [ ] Reset button for each section

### Step 4: Create MockupPresetBar
- [ ] Create `Features/Annotate/Mockup/Views/MockupPresetBar.swift`
- [ ] ScrollView horizontal with HStack
- [ ] Map presets to PresetButton views
- [ ] Highlight selected preset
- [ ] Add "Save Custom" button at end

### Step 5: Create slider components
- [ ] Reuse or create CompactSliderRow component
- [ ] Label + Slider + Value display
- [ ] Consistent styling with Annotate sidebar

### Step 6: Create MockupToolbarView
- [ ] Export button (dropdown: Save As, Copy, Share)
- [ ] Undo/Redo buttons
- [ ] Toggle sidebar button
- [ ] Close button

## Todo

- [ ] MockupMainView.swift created
- [ ] MockupCanvasView.swift with 3D preview
- [ ] MockupSidebarView.swift with all sliders
- [ ] MockupPresetBar.swift with thumbnails
- [ ] MockupToolbarView.swift
- [ ] All components connected to MockupState

## Success Criteria

- Layout matches Annotate module style
- Sliders update preview in real-time
- Preset bar scrolls horizontally
- Sidebar toggles smoothly
- Responsive to window resize

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Slider lag on complex images | Debounce updates, use thumbnail for preview |
| UI inconsistency with Annotate | Extract shared components |
| Preset bar overflow | Use ScrollView, limit visible count |

## Security Considerations

- None specific to this phase

## Next Steps

Proceed to [Phase 5: Export Functionality](./phase-05-export-functionality.md)
