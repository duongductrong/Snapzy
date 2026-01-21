# Phase 3: State Changes for Scrubbing and Trim

## Context

- [Phase 3 Main](./phase-03-timeline-scrubbing-and-trim.md)

## Add to VideoEditorState

```swift
// Trim boundaries
@Published var trimStart: CMTime = .zero
@Published var trimEnd: CMTime = .zero  // Initialized to duration after load
@Published var isScrubbing: Bool = false

// Check if trim range modified
var hasTrimChanges: Bool {
    trimStart != .zero || trimEnd != duration
}

func initializeTrimRange() {
    trimStart = .zero
    trimEnd = duration
}

func setTrimStart(progress: CGFloat) {
    let seconds = Double(progress) * CMTimeGetSeconds(duration)
    let newStart = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
    let minEnd = CMTime(seconds: CMTimeGetSeconds(newStart) + 1.0, preferredTimescale: 600)

    if newStart < trimEnd && trimEnd >= minEnd {
        trimStart = newStart
        hasUnsavedChanges = true
    }
}

func setTrimEnd(progress: CGFloat) {
    let seconds = Double(progress) * CMTimeGetSeconds(duration)
    let newEnd = CMTime(seconds: min(seconds, CMTimeGetSeconds(duration)), preferredTimescale: 600)
    let minStart = CMTime(seconds: CMTimeGetSeconds(newEnd) - 1.0, preferredTimescale: 600)

    if newEnd > trimStart && trimStart <= minStart {
        trimEnd = newEnd
        hasUnsavedChanges = true
    }
}

func scrub(to progress: CGFloat) {
    isScrubbing = true
    let seconds = Double(progress) * CMTimeGetSeconds(duration)
    let time = CMTime(seconds: seconds, preferredTimescale: 600)
    player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    currentTime = time
}

func endScrubbing() {
    isScrubbing = false
}
```

## Scrubbing Gesture for Timeline

Add to VideoTimelineView:
```swift
.gesture(
    DragGesture(minimumDistance: 0)
        .onChanged { value in
            let progress = max(0, min(value.location.x / geometry.size.width, 1))
            state.scrub(to: progress)
        }
        .onEnded { _ in
            state.endScrubbing()
        }
)
```
