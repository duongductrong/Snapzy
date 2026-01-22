# Plan: Video Editor Empty State with Drag & Drop Support

**Date:** 260122
**Status:** Completed
**Complexity:** Medium

## Problem Statement

Currently, users can only open the Video Editor through the QuickAccess card (double-click or edit button). Once the QuickAccess card is closed/removed, users have no way to re-open the video for editing. This limits usability for post-capture editing workflows.

## Solution Overview

Enable the Video Editor to be opened independently with an **empty state** that allows users to drag & drop video files for editing. This provides an "Open Annotate" mode equivalent for videos.

## Current Architecture Analysis

### VideoEditorManager
- Singleton pattern (`VideoEditorManager.shared`)
- `openEditor(for: QuickAccessItem)` - requires QuickAccessItem
- Tracks window controllers by UUID (item.id)
- No support for opening editor without pre-existing item

### VideoEditorWindowController
- Requires `QuickAccessItem` in initializer
- Creates `VideoEditorState` from item URL
- Manages window lifecycle

### VideoEditorState
- Initialized with URL directly (`init(url: URL)`)
- Already decoupled from QuickAccessItem

### Key Insight
`VideoEditorState` already accepts a URL directly, so adding URL-based opening is straightforward.

---

## Implementation Phases

### Phase 1: VideoEditorManager URL Support
**File:** `ClaudeShot/Features/VideoEditor/VideoEditorManager.swift`

**Changes:**
1. Add `openEditor(for url: URL)` method
2. Add `openEmptyEditor()` method for empty state window
3. Track URL-based windows separately (use URL hash as key)

```swift
// New tracking for URL-based windows
private var urlWindowControllers: [URL: VideoEditorWindowController] = [:]

/// Open video editor with empty state
func openEmptyEditor() {
  // Create empty state window controller
}

/// Open video editor for a video URL
func openEditor(for url: URL) {
  // Validate video file
  // Create/reuse window controller
}
```

### Phase 2: VideoEditorWindowController URL Initializer
**File:** `ClaudeShot/Features/VideoEditor/VideoEditorWindowController.swift`

**Changes:**
1. Add URL-based initializer `init(url: URL)`
2. Add empty state initializer `init()`
3. Store URL instead of QuickAccessItem for URL-based windows
4. Handle empty state setup

```swift
private var sourceURL: URL?

/// Initialize with URL directly (for drag & drop)
init(url: URL) {
  self.sourceURL = url
  self.state = VideoEditorState(url: url)
  // ... window setup
}

/// Initialize for empty state
init() {
  self.sourceURL = nil
  self.state = nil
  // ... empty state window setup
}
```

### Phase 3: Empty State View
**File:** `ClaudeShot/Features/VideoEditor/Views/VideoEditorEmptyStateView.swift` (NEW)

**Purpose:** Display when no video is loaded, prompt user to drag & drop

**UI Components:**
- Large drop zone with dashed border
- Video icon centered
- "Drop a video here to edit" text
- "Or browse files" button (optional)
- Visual feedback for drag hover state

```swift
struct VideoEditorEmptyStateView: View {
  var onVideoDropped: (URL) -> Void
  @State private var isTargeted = false

  var body: some View {
    // Drop zone UI
  }
}
```

### Phase 4: Update VideoEditorMainView
**File:** `ClaudeShot/Features/VideoEditor/Views/VideoEditorMainView.swift`

**Changes:**
1. Make `state` optional
2. Show empty state view when state is nil
3. Handle video drop to load new video

```swift
struct VideoEditorMainView: View {
  @ObservedObject var state: VideoEditorState?
  var onVideoLoaded: ((URL) -> Void)?
  // ...

  var body: some View {
    if let state = state {
      // Existing editor UI
    } else {
      VideoEditorEmptyStateView(onVideoDropped: onVideoLoaded)
    }
  }
}
```

### Phase 5: Menu Bar Integration (Optional)
**File:** `ClaudeShot/App/AppDelegate.swift` or menu handling

**Changes:**
- Add "Edit Video..." menu item under File menu
- Opens empty editor or file picker

---

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `VideoEditorManager.swift` | Modify | Add URL-based and empty editor methods |
| `VideoEditorWindowController.swift` | Modify | Add URL and empty initializers |
| `VideoEditorEmptyStateView.swift` | Create | New empty state with drop zone |
| `VideoEditorMainView.swift` | Modify | Support optional state, show empty view |

## Drag & Drop Implementation

Use SwiftUI's `.onDrop` modifier with `UTType.movie` and related video types:

```swift
.onDrop(of: [.movie, .video, .quickTimeMovie, .mpeg4Movie], isTargeted: $isTargeted) { providers in
  // Handle dropped video file
}
```

## Validation Requirements

1. Validate dropped file is a video (check UTType)
2. Verify file exists and is readable
3. Show error alert if invalid file dropped

## Testing Checklist

- [ ] Empty editor opens without crash
- [ ] Drag & drop video file loads editor
- [ ] Invalid file types show error
- [ ] Existing QuickAccessItem workflow unchanged
- [ ] Window closes properly in all scenarios
- [ ] Multiple editor windows work correctly

## Unresolved Questions

1. Should we add a "Browse Files" button in addition to drag & drop?
2. Should there be a keyboard shortcut to open empty video editor?
3. Should we limit to specific video formats or accept all video types?
