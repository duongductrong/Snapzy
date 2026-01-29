# Plan: Improve Crop Feature (CleanShot X Style)

**Date:** 2025-01-29
**Status:** In Progress
**Priority:** High

---

## Overview

Enhance crop feature to match CleanShot X's professional UX with aspect ratio presets, live dimensions, grid overlay, and improved visuals.

## Phases

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | [State Management](phase-01-state.md) | In Progress |
| 2 | [Visual Improvements](phase-02-visuals.md) | Pending |
| 3 | [Interaction Enhancements](phase-03-interactions.md) | Pending |
| 4 | [Crop Toolbar](phase-04-toolbar.md) | Pending |

## Key Features

1. **Aspect Ratio Presets**: Free, 1:1, 4:3, 16:9, custom
2. **Shift+Drag Lock**: Hold Shift to maintain current aspect ratio
3. **Live Dimensions**: Tooltip showing WxH during resize
4. **Rule of Thirds Grid**: Toggleable grid overlay
5. **Modern Handle Design**: Improved visual handles
6. **Crop Toolbar**: Floating toolbar with controls

## Files to Modify

- `State/AnnotateState.swift` - Add crop aspect ratio state
- `Views/CropOverlayView.swift` - Improve visuals, add grid/dimensions
- `Canvas/CanvasDrawingView.swift` - Add Shift+drag support
- `Views/CropToolbarView.swift` - New file for crop controls

## Success Criteria

- [ ] Aspect ratio presets work correctly
- [ ] Shift+drag maintains ratio
- [ ] Dimensions display during resize
- [ ] Grid overlay toggleable
- [ ] Handles match CleanShot X style
- [ ] Toolbar appears during crop mode
