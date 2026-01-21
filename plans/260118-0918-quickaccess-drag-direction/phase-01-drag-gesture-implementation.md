# Phase 01: Drag Gesture Implementation with Micro-Animations

## Context Links

- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** None
- **Code Reference:** [implementation-code-snippets.md](./implementation-code-snippets.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-18 |
| Priority | Medium |
| Status | Completed |
| Estimated Effort | 2-3 hours |

Implement directional drag detection on QuickAccess cards. Swipe right dismisses with slide-out animation; other directions trigger external drag-drop.

## Key Insights

1. `QuickAccessCardView` uses `.onDrag` with `dragItemProvider()` for external drag
2. Uses `.if(manager.dragDropEnabled)` pattern for optional drag
3. `manager.removeScreenshot(id:)` handles removal with spring animation
4. Stack collapse already animated via `withAnimation(.spring())`
5. Card dimensions: 180x112.5pt, 10pt corner radius

## Requirements

### Functional
- Swipe right >50pt within ±45° → dismiss card
- Other directions → external drag-drop
- Visual feedback during swipe
- Smooth slide-out + stack collapse animations

### Micro-Animations
| Animation | Spec |
|-----------|------|
| Drag follow | 1:1 offset tracking (right only) |
| Opacity fade | `1 - min(offset.width / 150, 0.5)` |
| Dismiss tint | Red bg when >50pt |
| Slide-out | Spring right, then remove |
| Stack collapse | Existing spring fills gap |
| Cancel snap | Spring back if <50pt |

## Architecture

```
QuickAccessCardView
├── State: dragOffset, isDismissing
├── Computed: isSwipeRightGesture, dismissProgress
├── DragGesture (onChanged, onEnded)
└── Visual Modifiers (.offset, .opacity, .background)
```

## Related Files

| File | Action |
|------|--------|
| `ZapShot/Features/QuickAccess/QuickAccessCardView.swift` | Modify |
| `ZapShot/Features/QuickAccess/QuickAccessManager.swift` | Use existing |

## Implementation Steps

1. Add state: `dragOffset`, `isDismissing`
2. Add computed: `isSwipeRightGesture`, `dismissProgress`
3. Create `swipeDismissGesture` with direction detection
4. Implement `dismissWithSlideAnimation()`
5. Apply visual modifiers (offset, opacity, red tint)
6. Stack collapse handled by existing manager code
7. Handle gesture conflicts with `.onDrag`

See [implementation-code-snippets.md](./implementation-code-snippets.md) for full code.

## Todo List

- [x] Add state variables
- [x] Add computed properties
- [x] Create swipe dismiss gesture
- [x] Implement dismiss animation method
- [x] Apply visual modifiers
- [x] Add red tint background
- [x] Disable `.onDrag` when dismissing
- [x] Test gesture priority
- [x] Verify stack collapse
- [x] Test external drag-drop

## Success Criteria

| Criterion | Test |
|-----------|------|
| Swipe right >50pt dismisses | Manual gesture |
| Offset follows finger | Visual check |
| Opacity fades | Visual check |
| Red tint at threshold | Visual check |
| Slide-out animation | Visual check |
| Stack collapses | Dismiss middle card |
| Snap back on cancel | Release <50pt |
| External drag works | Drag to Finder |

## Risks

| Risk | Mitigation |
|------|------------|
| Gesture conflict with .onDrag | Use gesture priority |
| External drag broken | Keep .onDrag, intercept right only |
| Animation jank | Spring animations |

## Security

N/A - UI only.

## Next Steps

1. Implement Phase 01
2. Phase 02 if conflicts: Use `NSDraggingSession` via AppKit
3. Consider haptic/sound feedback
