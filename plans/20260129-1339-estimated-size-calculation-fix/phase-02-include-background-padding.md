# Phase 02: Include Background Padding in Calculation

## Context Links

- **Parent Plan**: [plan.md](./plan.md)
- **Dependencies**: Phase 01
- **Research**: [researcher-02-export-pipeline.md](./research/researcher-02-export-pipeline.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-29 |
| Description | Verify background padding included in file size estimation |
| Priority | High |
| Implementation Status | Done |
| Review Status | Done |

## Key Insights

Background padding is ALREADY implemented correctly at L676-686:

```swift
// Include background padding in canvas size calculation
let canvasWidth: CGFloat
let canvasHeight: CGFloat
if backgroundStyle != .none && backgroundPadding > 0 {
  canvasWidth = exportSize.width + (backgroundPadding * 2)
  canvasHeight = exportSize.height + (backgroundPadding * 2)
} else {
  canvasWidth = exportSize.width
  canvasHeight = exportSize.height
}
let canvasPixels = canvasWidth * canvasHeight
let dimensionRatio = originalPixels > 0 ? canvasPixels / originalPixels : 1.0
```

## Requirements

- [x] Include background padding in pixel calculation
- [x] Match ZoomCompositor logic exactly
- [x] Backwards compatible when no background applied

## Architecture

```
calculateEstimatedFileSize()
    ├── Get exportSize from exportSettings
    ├── Calculate canvas size (IMPLEMENTED)
    │     └── If backgroundStyle != .none && padding > 0:
    │           canvasSize = exportSize + (padding * 2) each dimension
    │         Else:
    │           canvasSize = exportSize
    └── Use canvasPixels for dimensionRatio calculation
```

## Related Code Files

| File | Lines | Purpose |
|------|-------|---------|
| `VideoEditorState.swift` | 658-702 | `calculateEstimatedFileSize()` method |
| `VideoEditorState.swift` | 676-686 | Canvas size with padding calculation |
| `ZoomCompositor.swift` | 44-52 | Reference implementation for padding |

## Implementation Steps

No changes needed - already implemented correctly.

## Todo List

- [x] Verify dimension calculation includes background padding
- [x] Confirm logic matches ZoomCompositor condition

## Success Criteria

- [x] Estimated size increases when padding increases
- [x] No change when backgroundStyle == .none
- [x] Calculation matches ZoomCompositor.paddedRenderSize logic

## Risk Assessment

None - phase verified as complete.

## Security Considerations

None - internal calculation only.

## Next Steps

Proceed to [Phase 03: Add Change Triggers](./phase-03-add-change-triggers.md).
