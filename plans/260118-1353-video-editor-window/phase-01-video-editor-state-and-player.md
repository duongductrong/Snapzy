# Phase 1: Video Editor State and Player

## Context

- [Plan](./plan.md)
- [AVFoundation Research](./research/researcher-01-avfoundation-video-editing.md)
- [Codebase Scout](./scout/scout-01-codebase-structure.md)

## Overview

Establish core state management and video player foundation. VideoEditorState serves as the single source of truth, managing AVPlayer, video metadata, trim range, and unsaved changes tracking.

## Requirements

1. VideoEditorState as ObservableObject with @Published properties
2. Load video from QuickAccessItem URL
3. AVPlayer setup with time observation
4. Basic video player view using AVPlayerView (NSViewRepresentable)
5. Track video metadata (duration, resolution, format)

## Architecture Decisions

- **State Pattern**: Follow AnnotateState pattern - single ObservableObject passed through view hierarchy
- **Player Ownership**: State owns AVPlayer instance; views observe state
- **Time Observer**: 30fps periodic observer for smooth playhead updates
- **Async Loading**: Use async/await for AVAsset property loading

## Related Files

| File | Action |
|------|--------|
| `ZapShot/Features/VideoEditor/State/VideoEditorState.swift` | Create |
| `ZapShot/Features/VideoEditor/Views/VideoEditorMainView.swift` | Create |
| `ZapShot/Features/VideoEditor/Views/VideoPlayerSection.swift` | Create |
| `ZapShot/Features/VideoEditor/VideoEditorWindowController.swift` | Modify |

## Implementation Steps

### Step 1: Create VideoEditorState

Location: `ZapShot/Features/VideoEditor/State/VideoEditorState.swift`

```swift
@MainActor
final class VideoEditorState: ObservableObject {
    // Video source
    let sourceURL: URL
    let asset: AVAsset
    let player: AVPlayer

    // Metadata
    @Published var duration: CMTime = .zero
    @Published var naturalSize: CGSize = .zero
    @Published var currentTime: CMTime = .zero
    @Published var isPlaying: Bool = false

    // Trim range (Phase 3)
    @Published var trimStart: CMTime = .zero
    @Published var trimEnd: CMTime = .zero

    // Unsaved tracking
    @Published var hasUnsavedChanges: Bool = false

    private var timeObserver: Any?
}
```

Key methods:
- `init(url: URL)` - Load asset, create player
- `loadMetadata() async` - Load duration, naturalSize
- `setupTimeObserver()` - 30fps periodic observer
- `seek(to time: CMTime)` - Seek with zero tolerance
- `play()` / `pause()` / `togglePlayback()`

### Step 2: Create VideoPlayerSection

Location: `ZapShot/Features/VideoEditor/Views/VideoPlayerSection.swift`

NSViewRepresentable wrapping AVPlayerView:
- `controlsStyle = .none` (custom controls)
- `showsFullScreenToggleButton = false`
- Observe state.player

### Step 3: Create VideoEditorMainView

Location: `ZapShot/Features/VideoEditor/Views/VideoEditorMainView.swift`

Container view with:
- VideoPlayerSection (fills available space)
- Placeholder for timeline (Phase 2)
- Placeholder for controls (Phase 4)

### Step 4: Modify VideoEditorWindowController

Changes:
- Add `private let state: VideoEditorState`
- Initialize state with `item.url`
- Replace placeholder view with VideoEditorMainView
- Add window delegate conformance (for Phase 5)

## Todo List

- [ ] Create State/ directory structure
- [ ] Create Views/ directory structure
- [ ] Implement VideoEditorState with AVPlayer setup
- [ ] Implement async metadata loading
- [ ] Implement time observer (30fps)
- [ ] Create VideoPlayerSection (NSViewRepresentable)
- [ ] Create VideoEditorMainView container
- [ ] Modify VideoEditorWindowController to use state
- [ ] Test video loads and displays correctly

## Success Criteria

- Video editor window opens with video visible
- Video metadata (duration, size) loads correctly
- currentTime updates during playback (observable in debugger)
- No memory leaks (player properly released on window close)

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| AVPlayer not releasing | Remove time observer in deinit, nil player on close |
| Async loading race conditions | Use Task with proper cancellation |
| Retina scaling issues | Apply preferredTrackTransform in asset loading |
