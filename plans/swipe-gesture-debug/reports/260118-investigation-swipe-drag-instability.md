# Swipe Animation & Drag-Drop Instability Investigation

**Date:** 2026-01-18
**File:** `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/QuickAccess/QuickAccessCardView.swift`
**Status:** Root cause identified

---

## Executive Summary

Swipe-to-dismiss and drag-drop behaviors unstable due to **gesture conflict**. `.gesture()` modifier blocks `.onDrag` recognition in SwiftUI, preventing external drag-drop from working when custom DragGesture present.

**Impact:** Users cannot reliably drag items to external apps. Swipe right works but prevents all other drag operations.

**Root Cause:** SwiftUI gesture priority - `.gesture()` consumes all drag events before `.onDrag` receives them.

---

## Technical Analysis

### 1. Gesture Conflict Pattern (Lines 91-98)

```swift
.gesture(swipeDismissGesture)  // ← Consumes ALL drag events
.if(manager.dragDropEnabled && !isSwipingRight) { view in
  view.onDrag {  // ← Never receives events
    item.dragItemProvider()
  }
}
```

**Problem:** `.gesture()` has higher priority than `.onDrag`. Custom DragGesture intercepts all drag events, preventing `.onDrag` from activating.

**Evidence:**
- Line 194: `DragGesture(minimumDistance: 20)` captures all drags ≥20pt
- Line 200: Only right-direction drags set `isSwipingRight = true`
- Line 204-206: Non-right drags do nothing but still consumed by gesture
- Line 92: Conditional `.onDrag` never activates because gesture already consumed input

### 2. State Management Issues

**Incomplete State Reset:**
```swift
// Line 209-218: onEnded handler
.onEnded { _ in
  if isSwipeRightGesture {
    dismissWithSlideAnimation()
  } else {
    // Snap back - but only resets if right swipe occurred
    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
      dragOffset = .zero
      isSwipingRight = false  // ← Only reset here
    }
  }
}
```

**Problem:** `isSwipingRight` only reset in else branch. If dismiss animation starts, flag remains true.

**Evidence:**
- Line 225: `isSwipingRight = true` set at dismiss start
- Line 234: Item removed from manager after 0.2s delay
- No reset of `isSwipingRight` if dismiss completes
- Line 92 condition may remain blocked after dismiss

### 3. Gesture Logic Gaps

**Non-right drags ignored:**
```swift
// Line 200-207
if isRightDirection && !isDismissing {
  isSwipingRight = true
  dragOffset = value.translation
} else if !isSwipingRight {
  // Non-right direction - let .onDrag handle it (don't interfere)
  // ← Comment claims .onDrag handles it, but gesture already consumed event
}
```

**Problem:** Gesture consumes event but does nothing with it. `.onDrag` never sees the event because gesture priority consumed it first.

**Result:** User drags up/down/left but nothing happens. No visual feedback, no drag-drop activation.

### 4. Animation Timing Issues

**Dismiss animation dependencies:**
- Line 228-230: Slide animation runs 0.25s
- Line 233-235: Item removal after 0.2s delay
- **Timing mismatch:** Item removed BEFORE animation completes (0.2s < 0.25s)
- May cause visual glitch where card disappears mid-animation

### 5. SwiftUI Gesture Priority

**Gesture hierarchy (highest to lowest):**
1. `.gesture(_, including: .all)` - exclusive, blocks lower
2. `.gesture()` - default priority, blocks `.onDrag`
3. `.simultaneousGesture()` - runs alongside others
4. `.highPriorityGesture()` - blocks all below
5. `.onDrag` - lowest priority, blocked by custom gestures

**Current implementation:** Uses `.gesture()` which blocks `.onDrag` entirely.

---

## Root Cause Summary

**Primary:** `.gesture()` modifier blocks `.onDrag` recognition due to SwiftUI gesture priority system.

**Secondary:**
1. State flag `isSwipingRight` not reset after dismiss completes
2. Non-right drags consumed but ignored, no fallback behavior
3. Animation timing mismatch (removal at 0.2s vs animation 0.25s)
4. No simultaneous gesture support

---

## Recommended Fixes

### Option 1: Simultaneous Gestures (Recommended)

Replace `.gesture()` with `.simultaneousGesture()`:

```swift
.simultaneousGesture(swipeDismissGesture)
.if(manager.dragDropEnabled) { view in
  view.onDrag {
    item.dragItemProvider()
  }
}
```

**Pros:**
- Both gestures can activate
- Simpler implementation
- Standard SwiftUI pattern

**Cons:**
- May need logic to prevent both activating simultaneously
- Requires refined direction detection

### Option 2: Manual Gesture Coordination (More Control)

Remove `.gesture()`, implement all drag logic in single handler:

```swift
.gesture(
  DragGesture(minimumDistance: 20)
    .onChanged { value in
      let angle = atan2(value.translation.height, value.translation.width)
      let isRight = abs(angle) < .pi / 4 && value.translation.width > 0

      if isRight && value.translation.width > 50 {
        // Swipe right - show dismiss visual feedback
        isSwipingRight = true
        dragOffset = value.translation
      } else {
        // Other directions - trigger .onDrag manually
        // Not possible in SwiftUI - must use simultaneous approach
      }
    }
)
```

**Not viable:** Cannot manually trigger `.onDrag` from custom gesture. Must use Option 1 or 3.

### Option 3: Conditional Gesture Attachment (Cleanest)

Only attach swipe gesture when hovering, else allow `.onDrag`:

```swift
.if(isHovering) { view in
  view.gesture(swipeDismissGesture)
}
.if(manager.dragDropEnabled && !isHovering) { view in
  view.onDrag {
    item.dragItemProvider()
  }
}
```

**Pros:**
- Clear separation of concerns
- No gesture conflicts
- Swipe only when user can see card (hovering)

**Cons:**
- Swipe requires hover first (may be acceptable)
- Cannot swipe and drag simultaneously

### Option 4: NSView Drag Implementation (Advanced)

Replace `.onDrag` with `NSViewRepresentable` using `NSDraggingSource`:

**Pros:**
- Full control over drag behavior
- Can coordinate with SwiftUI gesture
- macOS native drag-drop APIs

**Cons:**
- Significant refactoring required
- More complex code
- Breaks SwiftUI declarative pattern

---

## Specific Code Issues

### Issue 1: Gesture Priority Conflict (Lines 91-98)
**Severity:** Critical
**Impact:** Drag-drop non-functional
**Fix:** Use Option 1 or 3 above

### Issue 2: State Not Reset (Line 225)
**Severity:** Medium
**Impact:** UI may stay in dismiss state after removal
**Fix:** Add cleanup in dismiss completion:

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {  // Match animation duration
  manager.removeScreenshot(id: item.id)
  // Reset state even though view will be removed
  isSwipingRight = false
  isDismissing = false
  dragOffset = .zero
}
```

### Issue 3: Animation Timing Mismatch (Lines 228-235)
**Severity:** Low
**Impact:** Visual glitch on dismiss
**Fix:** Change delay to 0.25s to match animation:

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {  // Was 0.2
  manager.removeScreenshot(id: item.id)
}
```

### Issue 4: Ignored Non-Right Drags (Lines 204-207)
**Severity:** Medium
**Impact:** No feedback when dragging wrong direction
**Fix:** With Option 1/3, `.onDrag` will handle automatically. With current approach, need visual feedback:

```swift
} else if !isSwipingRight {
  // Show subtle visual feedback that drag not recognized for dismiss
  // But don't block - let .onDrag handle (except it can't because gesture consumed)
  dragOffset = .zero  // Reset any accumulated offset
}
```

---

## SwiftUI Best Practices

### Gesture + Drag-Drop Patterns

**Don't:**
```swift
.gesture(DragGesture())  // Blocks .onDrag
.onDrag { ... }
```

**Do:**
```swift
.simultaneousGesture(DragGesture())  // Allows .onDrag
.onDrag { ... }
```

**Or:**
```swift
.if(condition) { view in
  view.gesture(DragGesture())  // Exclusive mode
}
.if(!condition) { view in
  view.onDrag { ... }  // Alternative mode
}
```

### Gesture Simultaneity

Use `simultaneousGesture` when:
- Need multiple gestures active
- Combining with `.onDrag`/`.onTapGesture`
- Gestures target different behaviors

Use `.gesture` when:
- Exclusive control needed
- One gesture should block others
- Clear priority required

### State Management

Always reset gesture state in `onEnded`:
```swift
.onEnded { _ in
  // Reset ALL state, even if action taken
  dragOffset = .zero
  isSwipingRight = false
  isDismissing = false
}
```

---

## Implementation Priority

1. **High:** Fix gesture conflict (Option 3 recommended - cleanest UX)
2. **High:** Reset state properly in all paths
3. **Medium:** Fix animation timing (0.2s → 0.25s)
4. **Low:** Add visual feedback for non-right drags (if not using Option 1/3)

---

## Verification Steps

After fix implementation:

1. **Test swipe right:** Should dismiss with smooth animation
2. **Test drag up/down/left:** Should initiate drag-drop to external apps
3. **Test drag to Finder:** File should copy to destination
4. **Test rapid gestures:** No stuck states or animation glitches
5. **Test hover + swipe:** Both should work together (if using Option 3)
6. **Test animation timing:** Card should fully animate before disappearing

---

## Unresolved Questions

1. **User preference:** Should swipe require hover first (Option 3) or always available (Option 1)?
2. **Gesture threshold:** Is 50pt right-swipe threshold optimal for user comfort?
3. **Animation feel:** Is 0.25s spring dismiss too slow/fast?
4. **Feedback:** Should non-right drags show visual indication before .onDrag activates?

---

## References

- SwiftUI gesture priority: `.highPriorityGesture` > `.gesture` > `.simultaneousGesture` > `.onDrag`
- `.gesture()` blocks all lower-priority gestures including `.onDrag`
- `.simultaneousGesture()` allows coordination but requires logic to prevent conflicts
- Conditional gesture attachment cleanest for mutually exclusive behaviors
