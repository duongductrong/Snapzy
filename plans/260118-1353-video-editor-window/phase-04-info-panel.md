# Phase 4: Info Panel Implementation

## Context

- [Phase 4 Main](./phase-04-controls-and-info-panel.md)

## VideoInfoPanel

Location: `ZapShot/Features/VideoEditor/Views/VideoInfoPanel.swift`

```swift
struct VideoInfoPanel: View {
    @ObservedObject var state: VideoEditorState

    var body: some View {
        HStack(spacing: 24) {
            InfoItem(label: "File", value: state.sourceURL.lastPathComponent)
            InfoItem(label: "Duration", value: formattedDuration)
            InfoItem(label: "Resolution", value: formattedResolution)
            InfoItem(label: "Format", value: state.sourceURL.pathExtension.uppercased())
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var formattedDuration: String {
        let seconds = CMTimeGetSeconds(state.trimEnd) - CMTimeGetSeconds(state.trimStart)
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private var formattedResolution: String {
        let size = state.naturalSize
        return "\(Int(size.width))x\(Int(size.height))"
    }
}
```

## InfoItem Helper View

```swift
struct InfoItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .foregroundColor(.secondary.opacity(0.7))
            Text(value)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
```

## Integration in VideoEditorMainView

```swift
VStack(spacing: 0) {
    VideoPlayerSection(player: state.player)

    VideoTimelineView(state: state)
        .padding(.horizontal, 16)
        .padding(.top, 8)

    VideoControlsView(state: state)

    Divider()
        .background(Color.white.opacity(0.1))

    VideoInfoPanel(state: state)
}
```
