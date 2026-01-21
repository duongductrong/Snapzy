# Drag-Drop Debug Report: External App Drop Failure

**Date:** 2026-01-18
**Issue:** Cards cannot be dragged to external apps (Facebook, Notes, image dropzones)
**Status:** Root cause confirmed, solution designed

---

## Executive Summary

**Root Cause:** `.onDrag` modifier conditionally attached only when `!isHovering`, creating logical paradox - user must hover/click to initiate drag, but modifier detached during hover.

**Impact:** Complete failure of drag-drop to external apps. Swipe-to-dismiss works perfectly (unaffected).

**Solution:** Remove hover condition from `.onDrag`, use `.highPriorityGesture` for swipe to take precedence during hover.

---

## Technical Analysis

### Current Implementation (Lines 105-115)

```swift
.if(isHovering && !isDismissing) { view in
  view.gesture(swipeDismissGesture)  // ✅ Works - attached during hover
}
.if(manager.dragDropEnabled && !isHovering && !isDismissing) { view in
  view.onDrag {                      // ❌ Never triggers - detached during hover
    item.dragItemProvider()
  } preview: {
    dragPreview
  }
}
```

### Why It Fails

**SwiftUI Drag Behavior:**
1. User hovers over card → `isHovering = true`
2. User clicks/drags → SwiftUI checks for `.onDrag` modifier
3. **Problem:** `.onDrag` only attached when `!isHovering` → modifier not present
4. Drag fails, no drag session starts

**Logical Paradox:**
- To drag, user MUST hover first (physical requirement)
- `.onDrag` only attached when NOT hovering (code condition)
- These conditions mutually exclusive → drag never works

### Why Swipe Works

Swipe gesture correctly attached when `isHovering && !isDismissing` - condition matches user behavior (hover THEN swipe).

---

## Evidence

**File:** `QuickAccessCardView.swift`
**Lines:** 105-115
**Condition:** `!isHovering` on `.onDrag` attachment

**Drag Item Provider:** Working correctly (lines 15-26 in `QuickAccessItemDragSupport.swift`)
```swift
func dragItemProvider() -> NSItemProvider {
  let fileURL = self.url
  let provider = NSItemProvider(contentsOf: fileURL) ?? NSItemProvider()
  provider.suggestedName = fileURL.lastPathComponent
  return provider
}
```

**Gesture System:**
- `.gesture()` - normal priority
- Need `.highPriorityGesture()` or `.simultaneousGesture()` for precedence control

---

## Recommended Solution

### Strategy: Always Attach `.onDrag`, Prioritize Swipe During Hover

**Implementation:**

```swift
// ALWAYS attach .onDrag (no hover condition)
.if(manager.dragDropEnabled && !isDismissing) { view in
  view.onDrag {
    item.dragItemProvider()
  } preview: {
    dragPreview
  }
}
// Use HIGH PRIORITY gesture for swipe when hovering
.if(isHovering && !isDismissing) { view in
  view.highPriorityGesture(swipeDismissGesture)
}
```

**How It Works:**
1. `.onDrag` always attached → available when user drags
2. During hover: `.highPriorityGesture` takes precedence → swipe works
3. During non-hover drag: No competing gesture → `.onDrag` works
4. SwiftUI automatically handles gesture recognition

### Alternative Solutions (Not Recommended)

**Option 2: Simultaneous Gestures**
- Use `.simultaneousGesture()` - both gestures active
- Risk: Conflict between swipe and drag
- Complexity: Need custom conflict resolution

**Option 3: Delay-Based Detection**
- Attach `.onDrag` after hover delay
- Risk: Laggy UX, missed drag attempts
- Complexity: Timer management

**Option 4: Custom Drag Gesture**
- Implement drag manually with `DragGesture`
- Risk: Lose native drag preview, file type handling
- Complexity: High, reinventing wheel

---

## Implementation Code

**File:** `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/QuickAccess/QuickAccessCardView.swift`

**Replace lines 105-115 with:**

```swift
// Drag-drop support - ALWAYS attached (no hover condition)
.if(manager.dragDropEnabled && !isDismissing) { view in
  view.onDrag {
    item.dragItemProvider()
  } preview: {
    dragPreview
  }
}
// Swipe-to-dismiss - HIGH PRIORITY when hovering
.if(isHovering && !isDismissing) { view in
  view.highPriorityGesture(swipeDismissGesture)
}
```

**Changes:**
1. Line 109: Remove `!isHovering` condition from `.onDrag`
2. Line 107: Change `.gesture()` to `.highPriorityGesture()`
3. Swap order: `.onDrag` first, then `.highPriorityGesture`

---

## Validation Plan

**Test Cases:**
1. ✅ Swipe right to dismiss during hover → should work (high priority gesture)
2. ✅ Drag to Facebook post composer → should attach file
3. ✅ Drag to Notes app → should embed image
4. ✅ Drag to desktop/Finder → should create file copy
5. ✅ Drag to image dropzone (web) → should upload
6. ✅ Non-hover state → `.onDrag` available, no gesture conflict

**Expected Behavior:**
- Hover + swipe right: Dismiss animation, card removed
- Hover + drag to external app: Drag preview appears, file transfers
- No hover + drag: Drag preview appears, file transfers

---

## Risk Assessment

**Low Risk:**
- `.highPriorityGesture` well-documented SwiftUI API
- No changes to drag provider or swipe logic
- Minimal code change (2 lines)

**Rollback Plan:**
- Revert to original conditional attachment
- Card drag remains broken (current state)

---

## Unresolved Questions

None - solution straightforward, no ambiguities.
