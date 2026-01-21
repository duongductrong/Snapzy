# Research Report: SwiftUI Recording UI Patterns

## Executive Summary
Recording UI requires floating control bar, timer display, and state-aware menu bar icon. SwiftUI with NSWindow integration provides best approach for macOS 12+.

## UI Components Needed

### 1. Recording Control Toolbar (Bottom Bar)
Floating window shown after area selection, before recording starts.

**SwiftUI Implementation:**
```swift
struct RecordingToolbarView: View {
    @ObservedObject var recorder: ScreenRecordingManager
    @Binding var selectedFormat: VideoFormat

    var body: some View {
        HStack(spacing: 16) {
            // Format picker
            Picker("Format", selection: $selectedFormat) {
                Text("MOV").tag(VideoFormat.mov)
                Text("MP4").tag(VideoFormat.mp4)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)

            Divider().frame(height: 20)

            // Record button
            Button(action: { recorder.startRecording() }) {
                Label("Record", systemImage: "record.circle")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            // Cancel button
            Button("Cancel") { recorder.cancel() }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

### 2. Recording In-Progress Bar
Shows timer, pause/stop controls during active recording.

```swift
struct RecordingStatusBar: View {
    @ObservedObject var recorder: ScreenRecordingManager

    var body: some View {
        HStack(spacing: 16) {
            // Recording indicator
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .opacity(recorder.isPaused ? 0.5 : 1.0)

            // Timer
            Text(recorder.formattedDuration)
                .font(.system(.body, design: .monospaced))
                .frame(width: 80)

            Divider().frame(height: 20)

            // Pause/Resume
            Button(action: { recorder.togglePause() }) {
                Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
            }

            // Stop
            Button(action: { recorder.stopRecording() }) {
                Image(systemName: "stop.fill")
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
```

### 3. Floating Window Controller
NSWindow wrapper for toolbar positioning.

```swift
@MainActor
final class RecordingToolbarWindow: NSWindow {
    init(contentView: NSView, anchorRect: CGRect) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.contentView = contentView

        // Position below selection rect
        positionBelow(rect: anchorRect)
    }

    func positionBelow(rect: CGRect) {
        guard let size = contentView?.fittingSize else { return }
        let x = rect.midX - size.width / 2
        let y = rect.minY - size.height - 20
        setFrameOrigin(CGPoint(x: x, y: max(y, 40)))
    }
}
```

### 4. Timer Management
```swift
@MainActor
class RecordingTimer: ObservableObject {
    @Published var elapsedSeconds: Int = 0
    @Published var formattedDuration: String = "00:00"

    private var timer: Timer?
    private var startTime: Date?

    func start() {
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsed()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func updateElapsed() {
        guard let start = startTime else { return }
        elapsedSeconds = Int(Date().timeIntervalSince(start))
        let mins = elapsedSeconds / 60
        let secs = elapsedSeconds % 60
        formattedDuration = String(format: "%02d:%02d", mins, secs)
    }
}
```

### 5. Menu Bar Icon States
```swift
enum MenuBarIconState {
    case idle           // "camera.aperture"
    case recording      // "record.circle.fill" (red tint)
    case paused         // "pause.circle.fill"
}

// In MenuBarExtra
MenuBarExtra("ZapShot", systemImage: iconForState(recorder.state)) {
    // ...
}

func iconForState(_ state: RecordingState) -> String {
    switch state {
    case .idle: return "camera.aperture"
    case .recording: return "record.circle.fill"
    case .paused: return "pause.circle.fill"
    }
}
```

## Recording Flow

1. **User triggers ⌘⇧5** → Show area selection overlay
2. **User selects area** → Show bottom toolbar with Record/Format/Cancel
3. **User clicks Record** → Hide toolbar, show recording bar, start capture
4. **During recording** → Show timer, pause/stop buttons
5. **User clicks Stop** → Finalize video, save to export location
6. **Complete** → Show notification or Quick Access overlay

## Area Selection Reuse
Existing `AreaSelectionController` can be extended:
```swift
func startSelection(mode: SelectionMode, completion: @escaping (CGRect?) -> Void) {
    self.selectionMode = mode  // .screenshot or .recording
    // ... existing logic
    // On complete, show different UI based on mode
}
```

## Preferences UI (Recording Tab)
```swift
struct RecordingSettingsView: View {
    @AppStorage("recordingFormat") var format = "mov"
    @AppStorage("recordingFPS") var fps = 30
    @AppStorage("recordingQuality") var quality = "high"
    @AppStorage("captureAudio") var captureAudio = true
    @AppStorage("captureMicrophone") var captureMicrophone = false

    var body: some View {
        Form {
            Section("Format") {
                Picker("Video Format", selection: $format) {
                    Text("MOV (Recommended)").tag("mov")
                    Text("MP4").tag("mp4")
                }
            }

            Section("Quality") {
                Picker("Frame Rate", selection: $fps) {
                    Text("30 FPS").tag(30)
                    Text("60 FPS").tag(60)
                }
                Picker("Quality", selection: $quality) {
                    Text("High").tag("high")
                    Text("Medium").tag("medium")
                    Text("Low").tag("low")
                }
            }

            Section("Audio") {
                Toggle("Capture System Audio", isOn: $captureAudio)
                Toggle("Capture Microphone", isOn: $captureMicrophone)
            }
        }
        .formStyle(.grouped)
    }
}
```

## Sources
- [Apple Human Interface Guidelines - macOS](https://developer.apple.com/design/human-interface-guidelines/macos)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- Native macOS screenshot tool (⌘⇧5) UI patterns
