# Phase 2: Timeline with Frame Previews

## Context

- [Plan](./plan.md)
- [Phase 1](./phase-01-video-editor-state-and-player.md)
- [SwiftUI Timeline Research](./research/researcher-02-swiftui-timeline-ui.md)

## Overview

Build the timeline UI with horizontal frame thumbnail strip. Extract frames at intervals using AVAssetImageGenerator and display them in a scrollable/fixed-width strip with playhead indicator.

## Requirements

1. Extract frame thumbnails at regular intervals
2. Display frames in horizontal strip below video player
3. Playhead indicator synchronized with currentTime
4. Efficient frame caching (no re-extraction on scrub)
5. Visual feedback for loading state

## Architecture Decisions

- **Frame Count**: Extract ~20-30 frames regardless of video length
- **Thumbnail Size**: 120x68 (16:9 aspect ratio, small footprint)
- **Caching**: Store extracted frames in state, generate once
- **Layout**: Fixed-width timeline, frames stretch to fill
- **Playhead**: Red vertical line, position = (currentTime / duration) * width

## Related Files

| File | Action |
|------|--------|
| `ZapShot/Features/VideoEditor/Views/VideoTimelineView.swift` | Create |
| `ZapShot/Features/VideoEditor/Views/VideoTimelineFrameStrip.swift` | Create |
| `ZapShot/Features/VideoEditor/State/VideoEditorState.swift` | Modify |

## Implementation Steps

### Step 1: Add Frame Extraction to State

Add to VideoEditorState:
```swift
@Published var frameThumbnails: [NSImage] = []
@Published var isExtractingFrames: Bool = false

func extractFrames() async {
    isExtractingFrames = true
    defer { isExtractingFrames = false }

    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 120, height: 68)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero

    let count = 25
    let interval = CMTimeGetSeconds(duration) / Double(count)

    var images: [NSImage] = []
    for i in 0..<count {
        let time = CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
        if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
            images.append(NSImage(cgImage: cgImage, size: NSSize(width: 120, height: 68)))
        }
    }
    frameThumbnails = images
}
```

### Step 2: Create VideoTimelineFrameStrip

Location: `ZapShot/Features/VideoEditor/Views/VideoTimelineFrameStrip.swift`

```swift
struct VideoTimelineFrameStrip: View {
    let thumbnails: [NSImage]
    let isLoading: Bool

    var body: some View {
        GeometryReader { geometry in
            if isLoading {
                // Loading indicator
            } else {
                HStack(spacing: 0) {
                    ForEach(0..<thumbnails.count, id: \.self) { index in
                        Image(nsImage: thumbnails[index])
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width / CGFloat(thumbnails.count))
                            .clipped()
                    }
                }
            }
        }
        .frame(height: 50)
    }
}
```

### Step 3: Create VideoTimelineView

Location: `ZapShot/Features/VideoEditor/Views/VideoTimelineView.swift`

Container view:
```swift
struct VideoTimelineView: View {
    @ObservedObject var state: VideoEditorState

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Frame strip background
                VideoTimelineFrameStrip(
                    thumbnails: state.frameThumbnails,
                    isLoading: state.isExtractingFrames
                )

                // Playhead indicator
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2, height: 60)
                    .offset(x: playheadOffset(in: geometry.size.width))
            }
        }
        .frame(height: 60)
        .background(Color.black.opacity(0.3))
        .cornerRadius(4)
    }

    private func playheadOffset(in width: CGFloat) -> CGFloat {
        guard CMTimeGetSeconds(state.duration) > 0 else { return 0 }
        let progress = CMTimeGetSeconds(state.currentTime) / CMTimeGetSeconds(state.duration)
        return CGFloat(progress) * width
    }
}
```

### Step 4: Integrate into VideoEditorMainView

Add VideoTimelineView below VideoPlayerSection:
```swift
VStack(spacing: 0) {
    VideoPlayerSection(player: state.player)

    VideoTimelineView(state: state)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)

    // Controls placeholder (Phase 4)
}
.onAppear {
    Task { await state.extractFrames() }
}
```

## Todo List

- [ ] Add frameThumbnails and isExtractingFrames to state
- [ ] Implement extractFrames() async method
- [ ] Create VideoTimelineFrameStrip view
- [ ] Create VideoTimelineView container
- [ ] Add playhead indicator with position calculation
- [ ] Integrate timeline into VideoEditorMainView
- [ ] Trigger frame extraction on view appear
- [ ] Test with various video lengths

## Success Criteria

- Frame thumbnails appear after brief loading
- Playhead moves smoothly during playback
- Timeline shows representative frames across video
- No frame re-extraction on window resize

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Slow frame extraction | Show loading indicator, extract in background |
| Memory pressure with many frames | Limit to 25 frames, use small thumbnail size |
| Frame extraction fails | Handle nil gracefully, show placeholder |
