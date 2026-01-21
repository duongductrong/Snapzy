# Phase 03: Video Card UI with Duration Badge

**Date:** 2026-01-17
**Priority:** High
**Status:** Pending

## Context Links

- [Plan Overview](./plan.md)
- [Phase 01: Model Enhancement](./phase-01-quickaccess-item-enhancement.md)

## Overview

Update `QuickAccessCardView` to display duration badge for videos and handle video-specific double-click behavior.

## Requirements

### Functional
- Display duration badge (bottom-right) for video items only
- Double-click opens video editor (not annotation editor) for videos
- Same hover overlay behavior for copy/save actions

### Non-Functional
- Visual consistency with screenshot cards
- Badge readable on any thumbnail background

## Related Code Files

### Files to Modify
| File | Action | Description |
|------|--------|-------------|
| `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/QuickAccess/QuickAccessCardView.swift` | MODIFY | Add duration badge, conditional double-click |
| `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/QuickAccess/QuickAccessManager.swift` | MODIFY | Add addVideo(), update copyToClipboard for videos |

## Implementation Steps

### Step 1: Update QuickAccessCardView - Add duration badge

Add duration badge view after thumbnail, before hover overlay:

```swift
// Duration badge (videos only)
if let duration = item.formattedDuration {
  durationBadge(duration)
}
```

### Step 2: Create durationBadge view

```swift
private func durationBadge(_ duration: String) -> some View {
  VStack {
    Spacer()
    HStack {
      Spacer()
      Text(duration)
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
          RoundedRectangle(cornerRadius: 4)
            .fill(Color.black.opacity(0.7))
        )
        .padding(6)
    }
  }
}
```

### Step 3: Update double-click handler

Replace current `onTapGesture(count: 2)` handler:

```swift
.onTapGesture(count: 2) {
  if item.isVideo {
    openVideoEditor()
  } else {
    openAnnotation()
  }
}
```

### Step 4: Add openVideoEditor method

```swift
private func openVideoEditor() {
  Task { @MainActor in
    VideoEditorManager.shared.openEditor(for: item)
  }
}
```

### Step 5: Update QuickAccessManager - Add addVideo method

```swift
/// Add a new video recording to the quick access stack
func addVideo(url: URL) async {
  guard isEnabled else { return }

  let result = await ThumbnailGenerator.generate(from: url)
  guard let thumbnail = result.thumbnail else { return }

  let item: QuickAccessItem
  if let duration = result.duration {
    item = QuickAccessItem(url: url, thumbnail: thumbnail, duration: duration)
  } else {
    // Fallback: create as video without duration
    item = QuickAccessItem(url: url, thumbnail: thumbnail, duration: 0)
  }

  if items.count >= maxVisibleItems {
    if let oldestId = items.last?.id {
      removeScreenshot(id: oldestId)
    }
  }

  let wasEmpty = items.isEmpty
  items.insert(item, at: 0)

  if wasEmpty {
    showPanel()
  }

  if autoDismissEnabled {
    startDismissTimer(for: item.id)
  }
}
```

### Step 6: Update copyToClipboard for videos

```swift
func copyToClipboard(id: UUID) {
  guard let item = items.first(where: { $0.id == id }) else { return }

  let url = item.url
  let isVideo = item.isVideo

  removeScreenshot(id: id)

  Task.detached(priority: .userInitiated) {
    await MainActor.run {
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()

      if isVideo {
        // Copy video file URL
        pasteboard.writeObjects([url as NSURL])
      } else {
        // Copy image data
        if let image = NSImage(contentsOf: url) {
          pasteboard.writeObjects([image])
        }
      }
      NSSound(named: "Pop")?.play()
    }
  }
}
```

## Todo List

- [ ] Add `durationBadge` view to QuickAccessCardView
- [ ] Show badge only when `item.formattedDuration` exists
- [ ] Update double-click to check `item.isVideo`
- [ ] Add `openVideoEditor()` method
- [ ] Add `addVideo(url:)` to QuickAccessManager
- [ ] Update `copyToClipboard` to handle video files
- [ ] Test badge positioning and styling
- [ ] Verify project compiles

## Success Criteria

- [ ] Duration badge visible on video cards only
- [ ] Badge readable with semi-transparent background
- [ ] Double-click video opens video editor
- [ ] Double-click screenshot opens annotation editor
- [ ] Copy action works for both types
- [ ] Save action unchanged (works for both)

## Next Steps

Proceed to [Phase 04: Video Editor Placeholder](./phase-04-video-editor-placeholder.md).
