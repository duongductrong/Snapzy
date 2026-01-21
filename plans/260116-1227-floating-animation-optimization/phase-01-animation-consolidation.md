# Phase 01: Animation Consolidation

## Context Links
- Parent: [plan.md](./plan.md)
- Dependencies: None
- Related: FloatingStackView.swift, FloatingCardView.swift, FloatingScreenshotManager.swift

## Overview
| Field | Value |
|-------|-------|
| Date | 2026-01-16 |
| Description | Consolidate duplicate animation triggers and unify animation approach |
| Priority | High |
| Implementation Status | Not Started |
| Review Status | Pending |

## Key Insights

### Current Animation Problems
1. **Double withAnimation calls**: `removeScreenshot()` in manager wraps mutation in `withAnimation`, callers in `FloatingStackView` also wrap → conflicting/fighting animations
2. **Individual appeared state**: Each `FloatingCardView` manages own `appeared` bool with spring animation → staggered lag when multiple cards change
3. **Competing animation values**: Stack uses `.animation(.spring(), value: items.count)` while cards use transitions → animation conflicts
4. **Panel resize animation**: `FloatingPanelController.updateSize()` uses `animate: true` in `setFrame()` → fights SwiftUI layout animation

### Root Cause
Multiple animation systems operating independently without coordination:
- SwiftUI implicit animation (`.animation` modifier)
- SwiftUI explicit animation (`withAnimation` blocks)
- AppKit window animation (`setFrame(animate:)`)
- Per-card appearance state

## Requirements
1. Single source of truth for animations - remove all duplicate `withAnimation` calls
2. Use transition-based animations instead of per-card state
3. Disable AppKit window animation, let SwiftUI handle all transitions
4. Use interruptible spring animations for smooth add/remove sequences

## Architecture

### Animation Flow (After)
```
User Action → Manager mutates items array →
SwiftUI ForEach detects change →
Transition animates card in/out →
Panel resizes without AppKit animation
```

### Single Animation Point
All animations triggered via `.animation` modifier on container, not individual `withAnimation` calls.

## Related Code Files
| File | Changes |
|------|---------|
| FloatingStackView.swift | Remove withAnimation wrappers from callbacks, keep single `.animation` modifier |
| FloatingCardView.swift | Remove `appeared` state, rely on transition |
| FloatingScreenshotManager.swift | Remove withAnimation from `removeScreenshot()` |
| FloatingPanelController.swift | Set `animate: false` in `updateSize()` |

## Implementation Steps

### Step 1: Remove duplicate withAnimation in FloatingStackView
```swift
// BEFORE (FloatingStackView.swift:22-38)
onCopy: {
  manager.copyToClipboard(id: item.id)
  withAnimation(.easeOut(duration: 0.2)) {  // REMOVE
    manager.removeScreenshot(id: item.id)
  }
}

// AFTER
onCopy: {
  manager.copyToClipboard(id: item.id)
  manager.removeScreenshot(id: item.id)  // No wrapper
}
```
Apply same pattern to `onOpenFinder` and `onDismiss`.

### Step 2: Centralize animation in manager
```swift
// FloatingScreenshotManager.swift:133-137
func removeScreenshot(id: UUID) {
  cancelDismissTimer(for: id)
  // Single withAnimation here - or remove entirely if using .animation modifier
  withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
    items.removeAll { $0.id == id }
  }
  if items.isEmpty {
    panelController.hide()
  }
}
```

### Step 3: Remove individual appeared state from FloatingCardView
```swift
// REMOVE these lines (FloatingCardView.swift:18, 65-72):
@State private var appeared = false
// ...
.opacity(appeared ? 1 : 0)
.scaleEffect(appeared ? 1 : 0.8)
.offset(y: appeared ? 0 : 20)
.onAppear {
  withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
    appeared = true
  }
}
```
Card appearance now handled entirely by transition.

### Step 4: Update transition for smoother animation
```swift
// FloatingStackView.swift:40-45 - use spring transition
.transition(
  .asymmetric(
    insertion: .opacity.combined(with: .scale(scale: 0.9)).combined(with: .offset(y: 15)),
    removal: .opacity.combined(with: .scale(scale: 0.85))
  )
)
```

### Step 5: Disable AppKit panel animation
```swift
// FloatingPanelController.swift:54
panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
```

### Step 6: Use single animation modifier on container
```swift
// FloatingStackView.swift:49 - use interruptible spring
.animation(.spring(response: 0.35, dampingFraction: 0.75, blendDuration: 0), value: manager.items)
```
Note: Animate on full `items` array, not just `count`, for proper identity tracking.

## Todo List
- [ ] Remove withAnimation wrappers from FloatingStackView callbacks
- [ ] Update FloatingScreenshotManager.removeScreenshot with single animation
- [ ] Remove appeared state and onAppear animation from FloatingCardView
- [ ] Update transition in FloatingStackView
- [ ] Disable animate:true in FloatingPanelController.updateSize
- [ ] Update .animation modifier to use items instead of items.count

## Success Criteria
1. No duplicate withAnimation calls in codebase
2. Cards animate smoothly without stagger on add/remove
3. Panel resizes instantly (no AppKit animation delay)
4. Rapid add/remove operations don't cause animation fighting

## Risk Assessment
| Risk | Mitigation |
|------|------------|
| Transition not triggering | Ensure ForEach uses stable identifiers (UUID) |
| Animation too fast/slow | Tune spring parameters after testing |

## Security Considerations
None - UI-only changes.

## Next Steps
Proceed to Phase 02: Async Action Handlers
