# Mockup Renderer Implementation Plan

## Overview

Build a 3D mockup renderer module for ClaudeShot that applies perspective transformations to screenshots with preset system, parameter controls, and high-quality export.

## File Structure

```
Features/Annotate/Mockup/
├── MockupManager.swift           # Optional singleton for standalone window
├── State/
│   ├── MockupState.swift         # Central ObservableObject
│   └── MockupPreset.swift        # Preset data model
├── Rendering/
│   ├── Mockup3DRenderer.swift    # 3D transform view component
│   └── MockupExporter.swift      # High-quality export (2x/3x)
├── Views/
│   ├── MockupMainView.swift      # Root container
│   ├── MockupCanvasView.swift    # 3D preview canvas
│   ├── MockupSidebarView.swift   # Parameter sliders
│   └── MockupPresetBar.swift     # Bottom preset thumbnails
└── Presets/
    └── DefaultPresets.swift      # Built-in presets
```

## Implementation Phases

| Phase | Description | Status | File |
|-------|-------------|--------|------|
| 1 | Core State and Models | `[ ]` | [phase-01-core-state-and-models.md](./phase-01-core-state-and-models.md) |
| 2 | 3D Rendering Engine | `[ ]` | [phase-02-3d-rendering-engine.md](./phase-02-3d-rendering-engine.md) |
| 3 | Preset System | `[ ]` | [phase-03-preset-system.md](./phase-03-preset-system.md) |
| 4 | UI Components | `[ ]` | [phase-04-ui-components.md](./phase-04-ui-components.md) |
| 5 | Export Functionality | `[ ]` | [phase-05-export-functionality.md](./phase-05-export-functionality.md) |
| 6 | Integration and Testing | `[ ]` | [phase-06-integration-and-testing.md](./phase-06-integration-and-testing.md) |

## Key Architectural Decisions

1. **State Pattern**: Central `MockupState` ObservableObject following `AnnotateState` pattern
2. **3D Transforms**: Chained `rotation3DEffect` modifiers for X/Y/Z axes with configurable perspective
3. **Preset Model**: `MockupPreset` struct with rotation, perspective, padding parameters
4. **Export Strategy**: `ImageRenderer` with 2x/3x scale + `NSBitmapImageRep` for PNG
5. **Integration**: Standalone feature in Annotate module, reuses `BackgroundStyle`

## Dependencies

- Research: [SwiftUI 3D Transforms](./research/researcher-01-swiftui-3d-transforms.md)
- Research: [Image Export](./research/researcher-02-image-export.md)
- Scout: [Annotate Module](./scout/scout-01-annotate-module.md)

## Success Criteria

- Real-time 3D preview with smooth parameter adjustment
- Preset thumbnails render correctly and apply instantly
- Export produces high-quality images at 2x/3x resolution
- Performance: <16ms render time for 60fps preview
