# Phase 3: Trim Handles View Implementation

## Context

- [Phase 3 Main](./phase-03-timeline-scrubbing-and-trim.md)

## VideoTrimHandlesView

Location: `ZapShot/Features/VideoEditor/Views/VideoTrimHandlesView.swift`

```swift
struct VideoTrimHandlesView: View {
    @ObservedObject var state: VideoEditorState
    let timelineWidth: CGFloat

    private let handleWidth: CGFloat = 12
    private let handleHeight: CGFloat = 60

    var body: some View {
        ZStack(alignment: .leading) {
            // Dimmed region before trim start
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .frame(width: trimStartOffset)

            // Dimmed region after trim end
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .frame(width: timelineWidth - trimEndOffset)
                .offset(x: trimEndOffset)

            // Start handle
            TrimHandle(position: trimStartOffset)
                .highPriorityGesture(startHandleGesture)

            // End handle
            TrimHandle(position: trimEndOffset - handleWidth)
                .highPriorityGesture(endHandleGesture)
        }
    }

    private var trimStartOffset: CGFloat {
        guard CMTimeGetSeconds(state.duration) > 0 else { return 0 }
        let progress = CMTimeGetSeconds(state.trimStart) / CMTimeGetSeconds(state.duration)
        return CGFloat(progress) * timelineWidth
    }

    private var trimEndOffset: CGFloat {
        guard CMTimeGetSeconds(state.duration) > 0 else { return timelineWidth }
        let progress = CMTimeGetSeconds(state.trimEnd) / CMTimeGetSeconds(state.duration)
        return CGFloat(progress) * timelineWidth
    }

    private var startHandleGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let progress = max(0, min(value.location.x / timelineWidth, 1))
                state.setTrimStart(progress: progress)
            }
    }

    private var endHandleGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let progress = max(0, min(value.location.x / timelineWidth, 1))
                state.setTrimEnd(progress: progress)
            }
    }
}
```

## TrimHandle Subview

```swift
struct TrimHandle: View {
    let position: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.yellow)
            .frame(width: 12, height: 60)
            .offset(x: position)
    }
}
```

## Integration in VideoTimelineView

```swift
ZStack(alignment: .leading) {
    VideoTimelineFrameStrip(...)

    VideoTrimHandlesView(state: state, timelineWidth: geometry.size.width)

    // Playhead (on top)
    Rectangle()
        .fill(Color.red)
        .frame(width: 2, height: 60)
        .offset(x: playheadOffset(in: geometry.size.width))
}
```
