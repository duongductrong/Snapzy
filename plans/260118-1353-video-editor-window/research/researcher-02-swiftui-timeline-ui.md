# SwiftUI Timeline UI Patterns for Video Editors

## Summary
Research on SwiftUI timeline UI patterns for building video editor interfaces with scrubber, frame preview, trim handles, and playhead.

## Key Findings

### 1. Timeline Scrubber with DragGesture
```swift
struct TimelineView: View {
    @State private var playheadPosition: CGFloat = 0
    let totalWidth: CGFloat = 300

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 50)

            Rectangle()
                .fill(Color.red)
                .frame(width: 2, height: 60)
                .offset(x: playheadPosition)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            playheadPosition = min(max(value.location.x, 0), totalWidth)
                        }
                )
        }
        .frame(width: totalWidth)
    }
}
```

### 2. Frame Preview Strip
- Use `LazyHStack` inside `ScrollView(.horizontal)` for efficient thumbnail loading
- Extract frames at intervals using AVAssetImageGenerator
- Cache thumbnails to avoid regeneration

### 3. Trim Handles Implementation
```swift
struct TrimHandleView: View {
    @Binding var trimStart: CGFloat
    @Binding var trimEnd: CGFloat
    let totalWidth: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            // Trimmed region highlight
            Rectangle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: trimEnd - trimStart)
                .offset(x: trimStart)

            // Start handle
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.yellow)
                .frame(width: 12, height: 60)
                .offset(x: trimStart - 6)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            trimStart = min(max(value.location.x, 0), trimEnd - 20)
                        }
                )

            // End handle
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.yellow)
                .frame(width: 12, height: 60)
                .offset(x: trimEnd - 6)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            trimEnd = min(max(value.location.x, trimStart + 20), totalWidth)
                        }
                )
        }
    }
}
```

### 4. Playhead Synchronization
- Use `AVPlayer.addPeriodicTimeObserver` to update playhead position
- Convert CMTime to CGFloat position based on timeline width
- Update at 30-60fps for smooth movement

### 5. Time Display
- Format: `MM:SS` or `HH:MM:SS` for longer videos
- Round down seconds until playhead crosses next second
- Show current time / total duration

## Best Practices

1. **Large Hit Areas**: Make handles ≥44pt for touch targets
2. **Horizontal Layout**: Time flows left-to-right
3. **Snapping**: Consider frame-accurate snapping
4. **Independent Preview**: Show trim preview separate from main playback
5. **Gesture Priority**: Use `.highPriorityGesture` to avoid conflicts

## Performance Tips
- Use `LazyHStack` for frame thumbnails
- Cache extracted frames
- Debounce seek operations during scrubbing
- Use `.drawingGroup()` for complex timeline rendering

## Sources
- [SwiftUI Gestures Documentation](https://developer.apple.com/documentation/swiftui/gestures)
- [Best practices for mobile video editing timeline](https://img.ly/blog/best-practices-for-designing-a-timeline-for-mobile-video-editing)
