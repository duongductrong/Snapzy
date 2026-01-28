# Phase 2: State Management

**Parent:** [plan.md](./plan.md)
**Dependencies:** [phase-01-rendering-optimization.md](./phase-01-rendering-optimization.md)

---

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-28 |
| Description | Implement preview value pattern for smooth slider interactions |
| Priority | P1 |
| Status | Pending |

---

## Key Insights

Annotate uses "preview values" pattern where slider drag updates temporary state, committing only on release. This prevents expensive state propagation during drag.

---

## Requirements

1. Add preview value properties for padding, shadow, corner radius
2. Compute effective values (preview ?? actual)
3. Update sliders to use preview values during drag

---

## Related Code Files

| File | Purpose |
|------|---------|
| `/Users/duongductrong/Developer/ZapShot/ClaudeShot/Features/VideoEditor/State/VideoEditorState.swift` | Add preview properties |
| `/Users/duongductrong/Developer/ZapShot/ClaudeShot/Features/VideoEditor/Views/VideoBackgroundSidebarView.swift` | Update slider bindings |
| `/Users/duongductrong/Developer/ZapShot/ClaudeShot/Features/Annotate/State/AnnotateState.swift` | Reference implementation |

---

## Implementation Steps

### Step 1: Add Preview Properties to VideoEditorState

```swift
// Add after background settings section

// MARK: - Preview Values (for smooth slider dragging)

@Published var previewBackgroundPadding: CGFloat?
@Published var previewBackgroundShadowIntensity: CGFloat?
@Published var previewBackgroundCornerRadius: CGFloat?

var effectiveBackgroundPadding: CGFloat {
  previewBackgroundPadding ?? backgroundPadding
}
var effectiveBackgroundShadowIntensity: CGFloat {
  previewBackgroundShadowIntensity ?? backgroundShadowIntensity
}
var effectiveBackgroundCornerRadius: CGFloat {
  previewBackgroundCornerRadius ?? backgroundCornerRadius
}
```

### Step 2: Update ZoomPreviewOverlay to Use Effective Values

Replace direct `state.backgroundPadding` references with `state.effectiveBackgroundPadding` etc.

### Step 3: Update Slider Bindings in VideoBackgroundSidebarView

Create custom bindings that set preview on drag, commit on release.

---

## Todo List

- [ ] Add preview properties to VideoEditorState
- [ ] Add effective computed properties
- [ ] Update ZoomPreviewOverlay to use effective values
- [ ] Create slider binding helpers with onEditingChanged
- [ ] Test slider responsiveness

---

## Success Criteria

1. Slider drag updates preview values only
2. Slider release commits to actual values
3. No frame drops during slider interaction

---

## Next Steps

Proceed to Phase 3 for performance validation.
