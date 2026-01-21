# Video Editor Window Implementation Plan

## Overview

Implement a video editor window for ZapShot that enables users to view, trim, and export screen recordings. The editor follows the existing NSWindow + NSHostingView + SwiftUI architecture pattern established by AnnotateWindowController.

## Architecture Summary

```
VideoEditorWindowController (NSWindowController)
    |-- VideoEditorState (ObservableObject) - Central state management
    |-- VideoEditorMainView (SwiftUI)
            |-- VideoPlayerSection (AVPlayerView wrapper)
            |-- VideoTimelineView
            |   |-- VideoTimelineFrameStrip (thumbnails)
            |   |-- TimelineScrubber (playhead)
            |   |-- TrimHandlesView (start/end handles)
            |-- VideoControlsView (play/pause, time display)
            |-- VideoInfoPanel (metadata display)
    |-- VideoEditorExporter - Trim and export logic
```

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `VideoEditorState.swift` | Create | Observable state with AVPlayer, trim range, unsaved tracking |
| `VideoEditorMainView.swift` | Create | Main SwiftUI container view |
| `VideoPlayerSection.swift` | Create | NSViewRepresentable for AVPlayerView |
| `VideoTimelineView.swift` | Create | Timeline container with frame strip and scrubber |
| `VideoTimelineFrameStrip.swift` | Create | Horizontal frame thumbnail strip |
| `VideoTrimHandlesView.swift` | Create | Draggable trim start/end handles |
| `VideoControlsView.swift` | Create | Playback controls and time display |
| `VideoInfoPanel.swift` | Create | Video metadata display |
| `VideoEditorExporter.swift` | Create | Trim and export functionality |
| `VideoEditorWindowController.swift` | Modify | Add state, delegates, unsaved changes |
| `VideoEditorPlaceholderView.swift` | Delete | No longer needed |

## Implementation Phases

| Phase | Status | Description |
|-------|--------|-------------|
| [Phase 1](./phase-01-video-editor-state-and-player.md) | ✅ completed | State management and video player |
| [Phase 2](./phase-02-timeline-with-frame-previews.md) | ✅ completed | Timeline with frame extraction |
| [Phase 3](./phase-03-timeline-scrubbing-and-trim.md) | ✅ completed | Interactive scrubber and trim handles |
| [Phase 4](./phase-04-controls-and-info-panel.md) | ✅ completed | Playback controls and info panel |
| [Phase 5](./phase-05-export-and-save.md) | ✅ completed | Export, save dialogs, unsaved changes |

## Dependencies

- AVFoundation / AVKit for video playback and export
- Existing: QuickAccessItem, VideoEditorWindow, VideoEditorManager

## Success Criteria

- Video loads and plays with custom controls
- Timeline shows frame previews synchronized with playhead
- Trim handles adjust video start/end points
- Export preserves quality with Replace/Copy options
- Unsaved changes prompt on close (matches Annotate pattern)
