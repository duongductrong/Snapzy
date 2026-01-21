# Plan: Close QuickAccess Card on Annotate Save

**Date:** 2026-01-18
**Status:** Ready for Implementation
**Complexity:** Low
**Estimated Effort:** 30 minutes

## Problem Statement

When user double-taps QuickAccess card, Annotate window opens. After saving (Done/Save/Save As), Annotate window closes but QuickAccess card remains visible with stale thumbnail. This causes UX confusion.

## Goal

Remove associated QuickAccess card when Annotate window closes after successful save.

## Analysis

### Current Flow
1. User double-taps QuickAccess card
2. `AnnotateManager.openAnnotation(for: item)` creates `AnnotateWindowController(item:)`
3. User edits and saves
4. `forceClose()` closes window
5. QuickAccess card remains (stale)

### Key Observations

**AnnotateWindowController.swift:**
- `init(item: QuickAccessItem)` - receives QuickAccessItem but does NOT store item.id
- `init()` - empty window for drag-drop (no associated card)
- `forceClose()` - called after save operations, sets `hasUnsavedChanges = false` and closes window

**QuickAccessManager.swift:**
- `removeItem(id: UUID)` - public method to remove card by ID
- `shared` singleton accessible

**AnnotateManager.swift:**
- Already tracks `windowControllers[item.id]` mapping
- Cleans up on `NSWindow.willCloseNotification`

### Decision: Store ID in AnnotateWindowController

Two approaches considered:

1. **Store ID in AnnotateWindowController** (chosen)
   - Add `quickAccessItemId: UUID?` property
   - Call `QuickAccessManager.shared.removeItem(id:)` in `forceClose()`
   - Simple, direct, minimal coupling

2. **Post notification from AnnotateWindowController**
   - More decoupled but adds complexity
   - Overkill for this use case

## Solution Design

### Changes to AnnotateWindowController.swift

```swift
// Add property
private let quickAccessItemId: UUID?

// Update init(item:)
init(item: QuickAccessItem) {
  self.quickAccessItemId = item.id
  // ... existing code
}

// Update init()
init() {
  self.quickAccessItemId = nil
  // ... existing code
}

// Update forceClose()
private func forceClose() {
  state.hasUnsavedChanges = false

  // Remove associated QuickAccess card after save
  if let itemId = quickAccessItemId {
    QuickAccessManager.shared.removeItem(id: itemId)
  }

  window?.close()
}
```

## Edge Cases

| Scenario | QuickAccessItemId | Behavior |
|----------|-------------------|----------|
| Open from QuickAccess, Save | UUID | Card removed |
| Open from QuickAccess, Don't Save | UUID | Card remains (user chose not to save) |
| Open from QuickAccess, Cancel | UUID | Card remains (window stays open) |
| Empty window (drag-drop), Save | nil | No card to remove |

### "Don't Save" Handling

Current code in `showUnsavedChangesAlert`:
- "Save" -> `performSaveAndClose()` -> `forceClose()` -> card removed
- "Don't Save" -> `forceClose()` -> card removed

**Issue:** "Don't Save" also removes card. Is this desired?

**Resolution:** YES, this is acceptable. User explicitly chose to close without saving. The screenshot file still exists at original location; only the QuickAccess preview is dismissed. Keeps UI clean.

## Files to Modify

| File | Change |
|------|--------|
| `ZapShot/Features/Annotate/Window/AnnotateWindowController.swift` | Add `quickAccessItemId`, update inits, update `forceClose()` |

## Testing Checklist

- [ ] Double-tap QuickAccess card, edit, Save -> card removed
- [ ] Double-tap QuickAccess card, edit, Save As -> card removed
- [ ] Double-tap QuickAccess card, edit, close with "Don't Save" -> card removed
- [ ] Double-tap QuickAccess card, edit, close with "Cancel" -> card remains, window stays
- [ ] Open empty Annotate (drag-drop), save -> no crash (nil check)
- [ ] Multiple QuickAccess cards, edit one, save -> only that card removed

## Risks

- **Low:** Direct coupling to `QuickAccessManager.shared` - acceptable for app-level singleton
- **None:** No changes to QuickAccessManager API

## Implementation Phase

See: `phase-01-implementation.md`
