# Canvas Inset Padding Refactor

## Problem Statement

Current behavior: When padding increases, background grows outward (content-box).
Desired behavior: Background fills viewport; image shrinks inward (border-box).

## Current vs Desired

| Aspect | Current | Desired |
|--------|---------|---------|
| Container | Grows with padding | Fixed to viewport |
| Background | Grows with padding | Always 100% of container |
| Image | Fixed size | Shrinks as padding increases |
| Annotations | Relative to image | Unchanged (still relative to image) |

## Architecture Decision

**Export Strategy**: Keep current export logic (original image size + padding).
- Rationale: Preserves full image resolution regardless of display size
- Annotations stored in image-relative coords; exporter offsets by padding

## Files to Modify

1. `AnnotateCanvasView.swift` - Core layout logic refactor
2. `CanvasDrawingView.swift` - Coordinate transformation for annotations
3. `AnnotateState.swift` - Add computed properties for display metrics

## Implementation Phases

| Phase | Description | Effort |
|-------|-------------|--------|
| 01 | State metrics & scale computation | Low |
| 02 | Canvas layout refactor (inset behavior) | Medium |
| 03 | Annotation coordinate sync | Medium |
| 04 | Testing & edge cases | Low |

## Success Criteria

- [ ] Background always fills available viewport
- [ ] Image shrinks when padding increases (aspect ratio preserved)
- [ ] Annotations remain correctly positioned on image
- [ ] Export produces same output as before (original size + padding)
- [ ] Zoom still works correctly
- [ ] ImageAlignment positions image within padding area

## Risk Mitigation

- Annotation coordinates must transform correctly between display/image space
- Export unchanged; only display logic modified

## Phase Files

- [Phase 01: State Metrics](./phase-01-state-metrics.md)
- [Phase 02: Canvas Layout](./phase-02-canvas-layout.md)
- [Phase 03: Annotation Sync](./phase-03-annotation-sync.md)
- [Phase 04: Testing](./phase-04-testing.md)
