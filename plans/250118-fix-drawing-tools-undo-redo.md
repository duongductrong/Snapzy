# Plan: Fix Drawing Tools & Add Keyboard Undo/Redo

**Date:** 250118
**Status:** Draft
**Complexity:** Low-Medium

## Summary

Fix two issues in the Annotate feature:
1. Highlighter/Pencil drawings disappear after mouse up (race condition)
2. Add keyboard shortcuts for undo/redo (⌘Z / ⇧⌘Z)

---

## Issue 1: Drawing Tools State Not Persisted

### Root Cause Analysis

In `CanvasDrawingView.swift:mouseUp()` (lines 426-437):

```swift
Task { @MainActor in
  state.saveState()
  createAnnotation(from: start, to: imagePoint)  // Uses currentPath
}

isDrawing = false
dragStart = nil
currentPath = []  // CLEARED BEFORE async task executes
needsDisplay = true
```

The `currentPath` array is cleared synchronously while `createAnnotation()` runs asynchronously. By the time annotation factory reads `currentPath`, it's already empty.

### Solution

Capture `currentPath` in local variable before clearing, pass to `createAnnotation()`.

### Changes Required

**File:** `CanvasDrawingView.swift`

1. Modify `mouseUp()` method (lines 426-437):
   - Capture `currentPath` before clearing
   - Pass captured path to `createAnnotation()`

2. Modify `createAnnotation()` signature (line 472):
   - Add `path` parameter instead of using instance variable

---

## Issue 2: Keyboard Shortcuts for Undo/Redo

### Current State

`keyDown(with:)` handles: Delete, Escape, Enter, Arrow keys, V key
Missing: ⌘Z (undo), ⇧⌘Z (redo)

### Solution

Add Z key (keyCode 6) handling with modifier checks.

### Changes Required

**File:** `CanvasDrawingView.swift`

Add case in `keyDown(with:)` method (after line 159):

```swift
case 6: // Z key
  if event.modifierFlags.contains(.command) {
    if event.modifierFlags.contains(.shift) {
      state.redo()
    } else {
      state.undo()
    }
    needsDisplay = true
  }
```

---

## Implementation Steps

### Step 1: Fix currentPath race condition
- [ ] In `mouseUp()`, capture `currentPath` to local `let pathToSave = currentPath`
- [ ] Pass `pathToSave` to `createAnnotation()`
- [ ] Update `createAnnotation()` to accept path parameter

### Step 2: Add keyboard undo/redo
- [ ] Add case 6 (Z key) in `keyDown(with:)`
- [ ] Check Command modifier for undo
- [ ] Check Command+Shift for redo
- [ ] Call appropriate state method and refresh display

### Step 3: Testing
- [ ] Draw with pencil tool - verify persists
- [ ] Draw with highlighter tool - verify persists
- [ ] Press ⌘Z - verify undo works
- [ ] Press ⇧⌘Z - verify redo works
- [ ] Verify toolbar buttons still work

---

## Files Modified

| File | Changes |
|------|---------|
| `CanvasDrawingView.swift` | Fix race condition + add keyboard shortcuts |

---

## Risk Assessment

- **Low risk** - isolated changes to single file
- **No architectural changes** - just bug fix and feature addition
- **Backwards compatible** - toolbar undo/redo unaffected

---

## Unresolved Questions

None.
