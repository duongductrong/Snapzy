# Cursor Mode (Select Tool) Implementation Plan

**Date**: 260116
**Feature**: Cursor Mode / Selection Tool for ZapShot Annotation Editor
**Priority**: High
**Status**: ✅ Completed

## Overview

Implement complete selection tool functionality enabling users to select, move, resize, and edit annotation properties. The `.selection` tool type already exists but toolbar integration and property binding are incomplete.

## Current State Analysis

### Already Implemented
- `.selection` case in `AnnotationToolType` (icon: "arrow.up.left", shortcut: "v")
- `selectedAnnotationId` tracking in `AnnotateState`
- Basic bounds-based hit testing (`hitTestAnnotation`)
- Move/drag functionality with coordinate transforms
- Resize handles (corner only) with minimum size constraints
- Delete key support (keyCode 51, 117)
- Undo/redo state management

### Gaps Identified
1. ~~Selection tool NOT in toolbar `drawingTools` array~~ ✅ Fixed
2. ~~Hit testing only uses bounding box (inaccurate for arrows, paths)~~ ✅ Fixed
3. ~~Sidebar shows no properties for non-text annotations when selected~~ ✅ Fixed
4. ~~Missing keyboard shortcuts (arrow nudge, Escape deselect)~~ ✅ Fixed
5. ~~No cursor feedback on hover~~ ✅ Fixed
6. No z-index management (bring front/send back) - Future enhancement

## Implementation Phases

| Phase | Title | Status | Effort |
|-------|-------|--------|--------|
| 01 | Toolbar Integration | ✅ Completed | 0.5 day |
| 02 | Hit Testing Enhancement | ✅ Completed | 1 day |
| 03 | Property Binding | ✅ Completed | 1 day |
| 04 | UX Enhancements | ✅ Completed | 1 day |

## Key Files Modified

| File | Changes |
|------|---------|
| `State/AnnotationToolType.swift` | Tool enum with icon/shortcut (existing) |
| `State/AnnotateState.swift` | Added `selectedAnnotation`, `nudgeSelectedAnnotation`, `deselectAnnotation`, enhanced `updateAnnotationProperties` |
| `State/AnnotationItem.swift` | Added `containsPoint(_:)` extension with geometry helpers |
| `Canvas/CanvasDrawingView.swift` | Enhanced keyboard, cursor tracking, prevent accidental creation |
| `Views/AnnotateToolbarView.swift` | Added `.selection` to toolbar |
| `Views/AnnotateSidebarView.swift` | Integrated properties section |
| `Views/AnnotationPropertiesSection.swift` | **New file** - property editing UI |

## Success Criteria

1. ✅ Selection tool visible and functional in toolbar
2. ✅ Accurate hit detection for all annotation types
3. ✅ Selected annotation properties editable in sidebar
4. ✅ Keyboard shortcuts working (V, Delete, Arrows, Escape)
5. ✅ Visual cursor feedback on interactive elements

## Phase Files

- [Phase 01: Toolbar Integration](./phase-01-toolbar-integration.md)
- [Phase 02: Hit Testing Enhancement](./phase-02-hit-testing-enhancement.md)
- [Phase 03: Property Binding](./phase-03-property-binding.md)
- [Phase 04: UX Enhancements](./phase-04-ux-enhancements.md)
