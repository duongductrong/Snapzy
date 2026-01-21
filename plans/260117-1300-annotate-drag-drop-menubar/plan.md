# Annotate Feature Enhancement: Drag-Drop & Menubar Integration

## Overview

Extend annotation feature to support opening via menubar without initial image and accepting drag-and-drop images onto the canvas. Enables users to annotate external images, not just captured screenshots.

## Implementation Phases

| Phase | Description | Status | Link |
|-------|-------------|--------|------|
| 01 | State Architecture - Make AnnotateState support optional/mutable image | ✅ Complete | [phase-01](./phase-01-state-architecture.md) |
| 02 | Window Management - Empty window init and manager extensions | ✅ Complete | [phase-02](./phase-02-window-management.md) |
| 03 | Drag-Drop Implementation - Canvas drop zone and image loading | ✅ Complete | [phase-03](./phase-03-drag-drop-implementation.md) |
| 04 | Menubar Integration - Add "Open Annotate" menu item | ✅ Complete | [phase-04](./phase-04-menubar-integration.md) |

## Code Review

| Date | Status | Report |
|------|--------|--------|
| 2026-01-17 | ✅ Approved (Minor Fixes Needed) | [Review Report](./reports/260117-code-review-annotate-drag-drop.md) |

## Key Files

**Modify:**
- `ZapShot/Features/Annotate/State/AnnotateState.swift`
- `ZapShot/Features/Annotate/AnnotateManager.swift`
- `ZapShot/Features/Annotate/Window/AnnotateWindowController.swift`
- `ZapShot/Features/Annotate/Views/AnnotateCanvasView.swift`
- `ZapShot/App/ZapShotApp.swift`

**Create:**
- `ZapShot/Features/Annotate/Views/AnnotateDropZoneView.swift`

## Supported Image Formats

PNG, JPG, JPEG, GIF, TIFF, BMP, HEIC

## Success Criteria

1. ✅ "Open Annotate" visible in menubar, opens empty annotation window
2. ✅ Drop zone visible when no image loaded with clear instructions
3. ✅ Dropping supported image file loads it into canvas
4. ✅ All existing annotation tools work on dropped images
5. ✅ Export functionality works for dropped images
6. ⚠️ Unsupported file types show error feedback - **Needs implementation**
7. ✅ Window sizing adapts to dropped image dimensions

## Known Issues

1. **Missing user feedback for invalid drops** - No visual error shown when unsupported files dropped
2. **Annotate shortcut persistence** - Cmd+Shift+A not saved/loaded from UserDefaults
3. **Code duplication** - loadImageWithCorrectScale duplicated in 2 files
4. **Missing cleanup** - Combine cancellables not cleared in AnnotateWindowController deinit

See [Code Review Report](./reports/260117-code-review-annotate-drag-drop.md) for details.

## Dependencies

- macOS 14.0+ drag-drop APIs
- Existing AnnotateExporter for final output
- UTType for file type validation

## Estimated Effort

~4-6 hours total implementation
