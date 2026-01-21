# Plan: QuickAccess Edit & Delete Action Buttons

**Date:** 2026-01-19
**Complexity:** Simple (single file modification)
**Status:** Completed

## Objective

Add two action buttons to QuickAccessCardView:
1. **Edit button** (bottom-left) - opens Annotate for images, VideoEditor for videos
2. **Delete button** (top-left) - quick deletion of capture item

## Current State

`QuickAccessCardView.swift` has:
- `handleDoubleClick()` - routes to Annotate/VideoEditor based on item type
- `dismissButton` - xmark icon, top-right, visible on hover
- `hoverOverlay` - Copy/Save buttons centered
- `QuickAccessActionButton` - reusable circular icon button component

## Implementation

### Single Phase: Update QuickAccessCardView.swift

**Add `editButton` computed property:**
```swift
private var editButton: some View {
  VStack {
    Spacer()
    HStack {
      QuickAccessActionButton(
        icon: "pencil",
        tooltip: item.isVideo ? "Edit Video" : "Annotate",
        action: handleDoubleClick
      )
      .padding(6)
      Spacer()
    }
  }
}
```

**Add `deleteButton` computed property:**
```swift
private var deleteButton: some View {
  VStack {
    HStack {
      QuickAccessActionButton(
        icon: "trash",
        tooltip: "Delete",
        action: { manager.removeScreenshot(id: item.id) }
      )
      .padding(6)
      Spacer()
    }
    Spacer()
  }
}
```

**Update body ZStack (after dismissButton block):**
```swift
// Edit button (bottom-left, only visible on hover)
if isHovering {
  editButton
    .transition(.opacity)
}

// Delete button (top-left, only visible on hover)
if isHovering {
  deleteButton
    .transition(.opacity)
}
```

## File Changes

| File | Action |
|------|--------|
| `ZapShot/Features/QuickAccess/QuickAccessCardView.swift` | Add 2 computed properties + update body |

## Verification

- [ ] Build succeeds
- [ ] Edit button appears bottom-left on hover
- [ ] Edit button opens Annotate for screenshots
- [ ] Edit button opens VideoEditor for videos
- [ ] Delete button appears top-left on hover
- [ ] Delete button removes item from QuickAccess
- [ ] All buttons have proper hover effects
- [ ] Transitions match existing dismissButton behavior

## Notes

- Reuses existing `QuickAccessActionButton` for consistency
- Follows same hover/transition pattern as `dismissButton`
- No new dependencies required
