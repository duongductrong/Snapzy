# Phase 01: State Tracking for Unsaved Changes

**Status:** Completed
**File:** `ZapShot/Features/Annotate/State/AnnotateState.swift`

## Objective

Track when canvas has unsaved modifications to enable close confirmation dialog.

## Current State Analysis

`AnnotateState` already has `saveState()` method (line 233-238) called before modifications:
- Pushes current annotations to undo stack
- Called by annotation creation, deletion, nudging operations

Modifications that should mark dirty:
1. `saveState()` - annotation changes (already centralized)
2. `applyCrop()` - crop applied (line 277-279)
3. `loadImage()` methods - loading new image resets state (should NOT mark dirty)

## Implementation

### Step 1: Add Published Property

```swift
// Add after line 137 (crop state section)

// MARK: - Unsaved Changes Tracking

/// Whether canvas has modifications not yet saved to disk
@Published var hasUnsavedChanges: Bool = false
```

### Step 2: Modify saveState() to Set Flag

```swift
// Modify lines 233-238
func saveState() {
  undoStack.append(annotations)
  redoStack.removeAll()
  canUndo = true
  canRedo = false
  hasUnsavedChanges = true  // ADD THIS LINE
}
```

### Step 3: Mark Dirty on Crop Apply

```swift
// Modify lines 277-279
func applyCrop() {
  isCropActive = false
  hasUnsavedChanges = true  // ADD THIS LINE
}
```

### Step 4: Add markAsSaved() Method

```swift
// Add after applyCrop() method, around line 280

/// Reset unsaved changes flag after successful save
func markAsSaved() {
  hasUnsavedChanges = false
}
```

### Step 5: Reset Flag on Image Load

Ensure `loadImage(from:)` and `loadImage(_:url:)` reset the flag (they already reset annotations, counter, crop - add hasUnsavedChanges reset):

```swift
// In loadImage(from:) around line 162-176, add:
hasUnsavedChanges = false

// In loadImage(_:url:) around line 179-192, add:
hasUnsavedChanges = false
```

## Code Diff Summary

```diff
 // MARK: - Crop State
 @Published var cropRect: CGRect?
 @Published var isCropActive: Bool = false

+// MARK: - Unsaved Changes Tracking
+@Published var hasUnsavedChanges: Bool = false

 // MARK: - Undo/Redo
 @Published var canUndo: Bool = false

   func loadImage(from url: URL) {
     guard let image = Self.loadImageWithCorrectScale(from: url) else { return }
     self.sourceImage = image
     self.sourceURL = url
     annotations.removeAll()
     undoStack.removeAll()
     redoStack.removeAll()
     canUndo = false
     canRedo = false
     counterValue = 1
     cropRect = nil
     isCropActive = false
+    hasUnsavedChanges = false
   }

   func loadImage(_ image: NSImage, url: URL? = nil) {
     self.sourceImage = image
     self.sourceURL = url
     annotations.removeAll()
     undoStack.removeAll()
     redoStack.removeAll()
     canUndo = false
     canRedo = false
     counterValue = 1
     cropRect = nil
     isCropActive = false
+    hasUnsavedChanges = false
   }

   func saveState() {
     undoStack.append(annotations)
     redoStack.removeAll()
     canUndo = true
     canRedo = false
+    hasUnsavedChanges = true
   }

   func applyCrop() {
     isCropActive = false
+    hasUnsavedChanges = true
   }

+  /// Reset unsaved changes flag after successful save
+  func markAsSaved() {
+    hasUnsavedChanges = false
+  }
```

## Verification

After implementation:
1. Open annotation window with image
2. Add any annotation -> `hasUnsavedChanges` should be `true`
3. Undo all changes -> `hasUnsavedChanges` stays `true` (undo doesn't mean saved)
4. Load new image -> `hasUnsavedChanges` resets to `false`

## Notes

- Undo/redo operations do NOT reset `hasUnsavedChanges` - user still has unsaved state even if they undo
- Only explicit save action (via `markAsSaved()`) or loading new image clears the flag
