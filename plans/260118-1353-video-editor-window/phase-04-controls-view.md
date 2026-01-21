# Phase 4: Controls View Implementation

## Context

- [Phase 4 Main](./phase-04-controls-and-info-panel.md)

## State Methods for Playback

Add to VideoEditorState:
```swift
func play() {
    player.play()
    isPlaying = true
}

func pause() {
    player.pause()
    isPlaying = false
}

func togglePlayback() {
    if isPlaying {
        pause()
    } else {
        play()
    }
}

func setupEndObserver() {
    NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: player.currentItem,
        queue: .main
    ) { [weak self] _ in
        self?.handlePlaybackEnd()
    }
}

private func handlePlaybackEnd() {
    isPlaying = false
}
```

## VideoControlsView

Location: `ZapShot/Features/VideoEditor/Views/VideoControlsView.swift`

```swift
struct VideoControlsView: View {
    @ObservedObject var state: VideoEditorState

    var body: some View {
        HStack(spacing: 16) {
            Button(action: { state.togglePlayback() }) {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            Text(timeDisplay)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.vertical, 8)
    }

    private var timeDisplay: String {
        let current = formatTime(state.currentTime)
        let total = formatTime(state.trimEnd - state.trimStart)
        return "\(current) / \(total)"
    }

    private func formatTime(_ time: CMTime) -> String {
        let seconds = Int(CMTimeGetSeconds(time))
        let mins = seconds / 60
        let secs = seconds % 60

        if mins >= 60 {
            let hours = mins / 60
            let remainingMins = mins % 60
            return String(format: "%d:%02d:%02d", hours, remainingMins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }
}
```
