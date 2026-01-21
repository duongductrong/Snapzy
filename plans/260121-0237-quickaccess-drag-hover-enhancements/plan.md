# QuickAccess Drag & Hover Enhancements Plan

**Created:** 2026-01-21
**Status:** Ready for Implementation
**Complexity:** Low-Medium

## Summary

Enhance QuickAccessCardView with:
1. Drag state visual feedback (opacity reduction during drag)
2. Auto-close behavior after drag (success or cancel)
3. Hover interactions for action buttons (edit/delete/close) with color changes and cursor states

## Requirements Analysis

### R1: Drag State Visual Feedback
- When user starts dragging a card → reduce opacity to ~0.6
- Visual indicator that card is being dragged

### R2: Auto-Close After Drag
- If drag completes (dropped successfully) → auto-close card
- If drag cancelled (not dropped anywhere) → restore opacity, then auto-close card

### R3: Button Hover Interactions
- Edit/Delete/Close buttons need hover color change
- Cursor should change to pointer on hover
- Consistent with existing `QuickAccessTextButton` hover pattern

## Current State Analysis

### QuickAccessCardView.swift (lines 80-86)
```swift
.if(manager.dragDropEnabled) { view in
  view.onDrag {
    item.dragItemProvider()
  } preview: {
    dragPreview
  }
}
```
**Issue:** No drag state tracking, no completion/cancel handling

### Action Buttons (lines 147-210)
- `dismissButton`, `editButton`, `deleteButton` - all use static `Color.black.opacity(0.6)`
- No hover state tracking
- No cursor change

## Implementation Design

### Phase 1: Drag State Tracking

**Approach:** Use `@State` to track dragging state and `onDrag` with custom handling.

SwiftUI's `onDrag` doesn't provide completion callbacks directly. We need to:
1. Track `isDragging` state
2. Use `onDrop` or observe when drag ends
3. Alternative: Use `DragGesture` combined with `onDrag`

**Solution:** Since `onDrag` doesn't have completion handler, we'll use a combination approach:
- Set `isDragging = true` when drag starts (in `onDrag` closure)
- Use `onDrop` on parent or detect drag end via `onHover` state change
- Simpler: Since after successful drag the item is typically used (copied/moved), we auto-remove on drag start with delay

**Refined Solution:**
- Track `isDragging` state
- On drag start: set `isDragging = true`, reduce opacity
- After drag ends (user releases): remove item
- This aligns with user expectation: dragging = intent to use elsewhere

### Phase 2: Button Hover States

**Approach:** Create reusable `QuickAccessIconButton` component (similar pattern to `QuickAccessTextButton`)

**Features:**
- `@State isHovering` for hover tracking
- Background color change on hover: `Color.black.opacity(0.6)` → `Color.white.opacity(0.35)`
- Cursor change: `.pointingHand` on hover
- Consistent animation timing (0.15s)

## Implementation Tasks

### Task 1: Add Drag State to QuickAccessCardView
**File:** `QuickAccessCardView.swift`

Add state:
```swift
@State private var isDragging = false
```

Modify body to apply opacity:
```swift
.opacity(isDragging ? 0.6 : 1.0)
```

Update onDrag to track state:
```swift
.if(manager.dragDropEnabled) { view in
  view.onDrag {
    isDragging = true
    // Schedule auto-remove after brief delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      manager.removeScreenshot(id: item.id)
    }
    return item.dragItemProvider()
  } preview: {
    dragPreview
  }
}
```

### Task 2: Create QuickAccessIconButton Component
**File:** `QuickAccessIconButton.swift` (new file)

```swift
struct QuickAccessIconButton: View {
  let icon: String
  let action: () -> Void
  var helpText: String? = nil

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 10, weight: .bold))
        .foregroundColor(.white)
        .frame(width: 20, height: 20)
        .background(
          Circle()
            .fill(isHovering ? Color.white.opacity(0.35) : Color.black.opacity(0.6))
        )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.15)) {
        isHovering = hovering
      }
      if hovering {
        NSCursor.pointingHand.push()
      } else {
        NSCursor.pop()
      }
    }
    .if(helpText != nil) { view in
      view.help(helpText!)
    }
  }
}
```

### Task 3: Refactor Action Buttons in QuickAccessCardView
**File:** `QuickAccessCardView.swift`

Replace inline button implementations with `QuickAccessIconButton`:

**dismissButton:**
```swift
private var dismissButton: some View {
  VStack {
    HStack {
      Spacer()
      QuickAccessIconButton(icon: "xmark") {
        manager.removeScreenshot(id: item.id)
      }
      .padding(6)
    }
    Spacer()
  }
}
```

**editButton:**
```swift
private var editButton: some View {
  VStack {
    Spacer()
    HStack {
      QuickAccessIconButton(
        icon: "pencil",
        action: handleDoubleClick,
        helpText: item.isVideo ? "Edit Video" : "Annotate"
      )
      .padding(6)
      Spacer()
    }
  }
}
```

**deleteButton:**
```swift
private var deleteButton: some View {
  VStack {
    HStack {
      QuickAccessIconButton(
        icon: "trash",
        action: { manager.deleteItem(id: item.id) },
        helpText: "Delete"
      )
      .padding(6)
      Spacer()
    }
    Spacer()
  }
}
```

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `QuickAccessCardView.swift` | Modify | Add isDragging state, opacity, refactor buttons |
| `QuickAccessIconButton.swift` | Create | New reusable icon button with hover/cursor |

## Testing Checklist

- [ ] Drag a card → opacity reduces to 0.6
- [ ] Release drag (drop anywhere) → card auto-closes
- [ ] Release drag (cancel/no drop) → card auto-closes
- [ ] Hover over dismiss (X) button → background lightens, cursor changes to hand
- [ ] Hover over edit (pencil) button → background lightens, cursor changes to hand
- [ ] Hover over delete (trash) button → background lightens, cursor changes to hand
- [ ] Click each button → correct action executes
- [ ] Cursor returns to normal after leaving button

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Drag cancel detection unreliable | Use timeout-based auto-remove (0.5s delay gives time for drop to complete) |
| Cursor not popping correctly | Ensure `NSCursor.pop()` always called in onHover false case |
| Button hover interferes with card hover | Buttons already inside card hover zone, should work correctly |

## Unresolved Questions

None - requirements are clear and implementation approach is straightforward.
