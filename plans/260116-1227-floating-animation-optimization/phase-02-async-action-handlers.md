# Phase 02: Async Action Handlers

## Context Links
- Parent: [plan.md](./plan.md)
- Dependencies: Phase 01 (Animation Consolidation)
- Related: FloatingScreenshotManager.swift, FloatingStackView.swift

## Overview
| Field | Value |
|-------|-------|
| Date | 2026-01-16 |
| Description | Move blocking operations off main thread, add immediate visual feedback |
| Priority | High |
| Implementation Status | Not Started |
| Review Status | Pending |

## Key Insights

### Current Blocking Operations
1. **copyToClipboard()** - `NSImage(contentsOf:)` loads full image synchronously on main thread
2. **openInFinder()** - `NSWorkspace.shared.selectFile()` can block briefly
3. **Action sequence** - Currently: block → animate → remove. User perceives delay before visual response.

### Perceived Delay Pattern
```
User clicks "Copy" →
  NSImage loads (blocks 50-200ms) →
  NSPasteboard writes →
  NSSound plays →
  Animation starts →
  Card removed
```
User waits with no feedback during image load.

### Ideal Pattern
```
User clicks "Copy" →
  Immediate visual feedback (scale/opacity) →
  Animation starts (card exits) →
  Background: load image, write pasteboard, play sound
```

## Requirements
1. Immediate visual feedback on action click (< 16ms)
2. Image loading off main thread
3. Card removal animation starts immediately
4. Clipboard/Finder operations complete async

## Architecture

### Async Flow
```swift
User clicks action →
  1. Start exit animation immediately
  2. Remove from items array (triggers animation)
  3. Task.detached: load image, write pasteboard
  4. MainActor: play sound after operation
```

### Visual Feedback Strategy
Option A: Start removal animation immediately, async complete operation
Option B: Brief "pressed" state before removal (adds 100ms perceived responsiveness)

Recommend Option A - simplest, fastest perceived response.

## Related Code Files
| File | Changes |
|------|---------|
| FloatingScreenshotManager.swift | Refactor copyToClipboard/openInFinder to async |
| FloatingStackView.swift | Update callback signatures if needed |

## Implementation Steps

### Step 1: Create async clipboard operation
```swift
// FloatingScreenshotManager.swift - new method
private func copyToClipboardAsync(url: URL) {
  Task.detached(priority: .userInitiated) {
    guard let image = NSImage(contentsOf: url) else { return }
    await MainActor.run {
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.writeObjects([image])
      NSSound(named: "Pop")?.play()
    }
  }
}
```

### Step 2: Refactor copyToClipboard for immediate response
```swift
// FloatingScreenshotManager.swift:154-165
func copyToClipboard(id: UUID) {
  guard let item = items.first(where: { $0.id == id }) else { return }

  // Capture URL before removal
  let url = item.url

  // Start async copy (runs in background)
  copyToClipboardAsync(url: url)

  // Remove immediately - animation starts now
  removeScreenshot(id: id)
}
```

### Step 3: Refactor openInFinder for immediate response
```swift
// FloatingScreenshotManager.swift:168-171
func openInFinder(id: UUID) {
  guard let item = items.first(where: { $0.id == id }) else { return }

  let url = item.url

  // Async Finder reveal
  Task.detached(priority: .userInitiated) {
    await MainActor.run {
      NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
    }
  }

  // Remove immediately
  removeScreenshot(id: id)
}
```

### Step 4: Update FloatingStackView callbacks (simplify)
```swift
// FloatingStackView.swift:22-38 - simplified, no withAnimation, no manual remove
FloatingCardView(
  item: item,
  onCopy: { manager.copyToClipboard(id: item.id) },
  onOpenFinder: { manager.openInFinder(id: item.id) },
  onDismiss: { manager.removeScreenshot(id: item.id) }
)
```

### Step 5: Optional - Add haptic feedback substitute
macOS doesn't have haptic feedback, but can add subtle audio or visual cue:
```swift
// In copyToClipboard, before async operation
// Option: Brief scale pulse on card before removal
// Decided: Not needed if animation is fast enough
```

## Todo List
- [ ] Create copyToClipboardAsync private method
- [ ] Refactor copyToClipboard to remove immediately, async copy
- [ ] Refactor openInFinder to remove immediately, async reveal
- [ ] Simplify FloatingStackView callbacks
- [ ] Test rapid clicks don't cause issues

## Success Criteria
1. Card begins exit animation within 16ms of click
2. Clipboard contains image after animation completes
3. Finder reveals file after animation completes
4. No UI freeze on action clicks
5. Rapid clicking multiple cards works smoothly

## Risk Assessment
| Risk | Mitigation |
|------|------------|
| Card removed before copy completes | Capture URL before removal |
| User deletes file before copy | Edge case, acceptable |
| Pasteboard write fails silently | Could add error handling, low priority |

## Security Considerations
None - existing operations, just reordered.

## Next Steps
Proceed to Phase 03: Panel Resize Optimization (optional, may not be needed after Phase 01-02)
