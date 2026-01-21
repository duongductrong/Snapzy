# Annotate Canvas Performance Fix Plan

## Problem Statement
Users experience lag and frame drops when moving annotations (arrows, rectangles, blur effects) in select-tool mode.

## Root Causes (Priority Order)
1. **Blur recalculation** - Pixelation computed from scratch each frame (O(rows*cols) per blur region)
2. **Full canvas redraw** - `needsDisplay = true` on every mouse drag event redraws ALL annotations
3. **No dirty rect** - Entire canvas redrawn instead of affected regions only
4. **State cascade** - `@Published` annotations array triggers SwiftUI updates during drag
5. **Single layer** - No separation between static and moving content

## Implementation Phases

| Phase | File | Focus | Impact | Risk | Status |
|-------|------|-------|--------|------|--------|
| 1 | phase-01-blur-caching.md | Cache blur as CGImage | HIGH | LOW | ✅ DONE |
| 2 | phase-02-dirty-rect-optimization.md | Redraw only changed regions | MEDIUM | LOW | Pending |
| 3 | phase-03-layer-separation.md | Separate static/moving layers | MEDIUM | MEDIUM | Pending |
| 4 | phase-04-state-batching.md | Batch state updates during drag | MEDIUM | LOW | Pending |

## Success Criteria
- Drag operations maintain 60fps (16.6ms frame time)
- No visible stutter when moving blur annotations
- CPU usage during drag reduced by 50%+
- Memory stable (no per-frame allocations)

## Key Files to Modify
- `/ZapShot/Features/Annotate/Canvas/BlurEffectRenderer.swift` - Add caching
- `/ZapShot/Features/Annotate/Canvas/CanvasDrawingView.swift` - Dirty rect + layers
- `/ZapShot/Features/Annotate/Canvas/AnnotationRenderer.swift` - Partial redraw support
- `/ZapShot/Features/Annotate/State/AnnotateState.swift` - Drag state separation

## Testing Strategy
- Profile with Instruments (Time Profiler, Core Animation)
- Measure frame times before/after each phase
- Test with 10+ annotations including multiple blur regions
- Verify on both Retina and non-Retina displays

## Dependencies
- Phase 2 benefits from Phase 1 (cached blurs reduce dirty rect overhead)
- Phase 3 can proceed independently
- Phase 4 can proceed independently

## Rollback Strategy
Each phase is self-contained. If issues arise, revert phase-specific changes without affecting others.

## Estimated Effort
- Phase 1: 2-3 hours
- Phase 2: 3-4 hours
- Phase 3: 4-5 hours
- Phase 4: 2-3 hours
- Total: ~12-15 hours
