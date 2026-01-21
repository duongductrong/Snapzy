# Research Report: Screen Recording UX Patterns (CleanShot X Reference)

## 1. Recording Toolbar Design

**Pattern:** Floating toolbar appears below selection area after defining capture region.

**Implementation:**
```swift
struct RecordingToolbarView: View {
    var body: some View {
        HStack(spacing: 12) {
            // Record button (primary)
            Button(action: startRecording) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 32, height: 32)
            }

            // Microphone toggle
            Toggle(isOn: $micEnabled) {
                Image(systemName: micEnabled ? "mic.fill" : "mic.slash")
            }

            // Cancel
            Button(action: cancel) {
                Image(systemName: "xmark")
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
```

**Window Setup:**
- `NSPanel` with `.floating` level
- Position: centered below selection rect
- `canJoinAllSpaces = true` for multi-desktop

## 2. Area Selection Overlay

**Existing Pattern (ZapShot):**
- Full-screen borderless NSWindow
- Semi-transparent overlay with clear selection area
- Mouse tracking for drag selection
- Escape to cancel

**Enhancement for Recording:**
- Add mode indicator (Recording vs Screenshot)
- Keep selection visible until recording starts
- Show toolbar after selection complete

## 3. Menu Bar Icon States

**States:**
1. **Idle:** Normal app icon (`camera.aperture`)
2. **Recording:** Red dot or stop icon (`stop.circle.fill`)
3. **Optional:** Blinking animation during recording

```swift
// In AppDelegate or MenuBarExtra
@Published var isRecording = false

var menuBarIcon: String {
    isRecording ? "stop.circle.fill" : "camera.aperture"
}

// With timer for blinking
Timer.publish(every: 0.5, on: .main, in: .common)
    .autoconnect()
    .sink { _ in self.toggleBlink() }
```

## 4. Floating Timer During Recording

**Design:**
- Small draggable window (80x40 pt)
- Shows elapsed time: "00:32"
- Stop button
- Semi-transparent background

```swift
struct RecordingTimerView: View {
    @State var elapsed: TimeInterval = 0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 8) {
            Text(formatTime(elapsed))
                .monospacedDigit()

            Button(action: stopRecording) {
                Image(systemName: "stop.fill")
                    .foregroundColor(.red)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .onReceive(timer) { _ in elapsed += 1 }
    }
}
```

**Window:** NSPanel, `.floating` level, draggable

## 5. Post-Recording Thumbnail

**Pattern:** Floating thumbnail in corner after capture stops.

**Actions:**
- Copy (file URL to clipboard)
- Save to Desktop
- Click → Open editor (VideoEditorStub)
- Auto-dismiss after ~5 seconds

**Implementation:**
- Reuse `FloatingPanelController` pattern
- Generate video thumbnail from first frame
- Route click to `VideoEditorStubView` instead of Annotate

```swift
struct VideoThumbnailView: View {
    let videoURL: URL
    let thumbnail: NSImage

    var body: some View {
        ZStack {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)

            // Play icon overlay
            Image(systemName: "play.circle.fill")
                .font(.largeTitle)
                .foregroundColor(.white.opacity(0.8))
        }
        .onTapGesture { openVideoEditor() }
    }
}
```

## Key UX Principles

1. **Minimal friction** - One shortcut to start, one click to stop
2. **Visual feedback** - Clear recording indicator in menu bar
3. **Non-intrusive** - Small timer, auto-dismissing thumbnail
4. **Consistent** - Match existing screenshot flow aesthetics

## Sources
- CleanShot X UI/UX
- macOS Screenshot App (Cmd+Shift+5)
- Apple Human Interface Guidelines
