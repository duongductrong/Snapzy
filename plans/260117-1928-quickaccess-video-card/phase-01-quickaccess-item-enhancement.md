# Phase 01: QuickAccessItem Model Enhancement

**Date:** 2026-01-17
**Priority:** High
**Status:** Pending

## Context Links

- [Plan Overview](./plan.md)
- [Scout Report](./scout/scout-01-codebase-analysis.md)

## Overview

Extend `QuickAccessItem` model to support both screenshots and videos with backward compatibility.

## Requirements

### Functional
- Add item type discrimination (screenshot vs video)
- Add optional duration for videos
- Maintain backward compatibility with existing screenshot code

### Non-Functional
- No breaking changes to existing API
- Type-safe enum for item types

## Related Code Files

### Files to Modify
| File | Action | Description |
|------|--------|-------------|
| `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/QuickAccess/QuickAccessItem.swift` | MODIFY | Add itemType enum and duration |

## Implementation Steps

### Step 1: Add QuickAccessItemType enum

Add enum before the struct definition:

```swift
/// Type of quick access item
enum QuickAccessItemType: Equatable {
  case screenshot
  case video
}
```

### Step 2: Update QuickAccessItem struct

Add new properties:

```swift
struct QuickAccessItem: Identifiable, Equatable {
  let id: UUID
  let url: URL
  let thumbnail: NSImage
  let capturedAt: Date
  let itemType: QuickAccessItemType  // NEW
  let duration: TimeInterval?        // NEW: Optional, only for videos

  // Existing initializer for screenshots (backward compatible)
  init(url: URL, thumbnail: NSImage) {
    self.id = UUID()
    self.url = url
    self.thumbnail = thumbnail
    self.capturedAt = Date()
    self.itemType = .screenshot
    self.duration = nil
  }

  // New initializer for videos
  init(url: URL, thumbnail: NSImage, duration: TimeInterval) {
    self.id = UUID()
    self.url = url
    self.thumbnail = thumbnail
    self.capturedAt = Date()
    self.itemType = .video
    self.duration = duration
  }

  static func == (lhs: QuickAccessItem, rhs: QuickAccessItem) -> Bool {
    lhs.id == rhs.id
  }
}
```

### Step 3: Add computed helper properties

```swift
extension QuickAccessItem {
  /// Whether this item is a video
  var isVideo: Bool {
    itemType == .video
  }

  /// Formatted duration string for display (e.g., "01:30s")
  var formattedDuration: String? {
    guard let duration = duration, duration.isFinite, duration >= 0 else {
      return nil
    }
    let mins = Int(duration) / 60
    let secs = Int(duration) % 60
    return String(format: "%02d:%02ds", mins, secs)
  }
}
```

## Todo List

- [ ] Add `QuickAccessItemType` enum
- [ ] Add `itemType` property to struct
- [ ] Add `duration` optional property
- [ ] Add video initializer
- [ ] Add `isVideo` computed property
- [ ] Add `formattedDuration` computed property
- [ ] Verify existing screenshot code still compiles

## Success Criteria

- [ ] Existing `QuickAccessItem(url:thumbnail:)` initializer works unchanged
- [ ] New `QuickAccessItem(url:thumbnail:duration:)` initializer available
- [ ] `itemType` correctly set based on initializer used
- [ ] `formattedDuration` returns properly formatted string
- [ ] Project compiles without errors

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Breaking existing code | Low | Backward-compatible initializer preserved |

## Next Steps

After completing this phase, proceed to [Phase 02: Video Thumbnail Generator](./phase-02-video-thumbnail-generator.md).
