# Phase 3: Recording UI Components

## Context Links
- [Main Plan](./plan.md)
- [Phase 1: Core Recording Engine](./phase-01-core-recording-engine.md)
- [Phase 2: Keyboard Shortcut Integration](./phase-02-keyboard-shortcut-integration.md)
- [Recording UI Patterns Research](./research/researcher-02-recording-ui-patterns.md)

## Overview
Create floating toolbar UI for recording workflow: pre-record toolbar (format picker, Record, Cancel) and during-record status bar (timer, Pause/Resume, Stop). Uses NSWindow with SwiftUI content.

## Requirements
- R1: Bottom floating toolbar appears after area selection
- R2: Pre-record toolbar: format picker, Record button, Cancel button
- R3: Status bar during recording: timer, Pause/Resume, Stop
- R4: Toolbar positions below selected area
- R5: Material background with rounded corners
- R6: Recording indicator (pulsing red dot)

## Architecture

### Component Hierarchy
```
RecordingToolbarWindow (NSWindow, borderless, floating)
├── RecordingToolbarView (pre-record)
│   ├── Format Picker (.mov/.mp4)
│   ├── Record Button (red)
│   └── Cancel Button
└── RecordingStatusBarView (during-record)
    ├── Recording Indicator (red dot)
    ├── Timer Display (00:00)
    ├── Pause/Resume Button
    └── Stop Button
```

### State Machine
```
idle -> (area selected) -> showingToolbar
showingToolbar -> (Record) -> recording
showingToolbar -> (Cancel) -> idle
recording -> (Pause) -> paused
paused -> (Resume) -> recording
recording/paused -> (Stop) -> idle (save video)
```

## Related Code Files

### Reference
| File | Purpose |
|------|---------|
| `ZapShot/Core/AreaSelectionWindow.swift` | NSWindow borderless pattern |
| `ZapShot/Features/FloatingScreenshot/FloatingScreenshotOverlayWindow.swift` | Floating window example |

### Create
| File | Purpose |
|------|---------|
| `ZapShot/Features/Recording/RecordingToolbarWindow.swift` | Floating window controller |
| `ZapShot/Features/Recording/RecordingToolbarView.swift` | Pre-record toolbar UI |
| `ZapShot/Features/Recording/RecordingStatusBarView.swift` | During-record status UI |

### Modify
| File | Changes |
|------|---------|
| `ZapShot/Core/ScreenCaptureViewModel.swift` | Integrate recording UI flow |

## Implementation Steps

### Step 1: Create RecordingToolbarView
File: `ZapShot/Features/Recording/RecordingToolbarView.swift`

```swift
import SwiftUI

struct RecordingToolbarView: View {
    @Binding var selectedFormat: VideoFormat
    let onRecord: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Format picker
            Picker("Format", selection: $selectedFormat) {
                Text("MOV").tag(VideoFormat.mov)
                Text("MP4").tag(VideoFormat.mp4)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)

            Divider()
                .frame(height: 20)

            // Record button
            Button(action: onRecord) {
                Label("Record", systemImage: "record.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)

            // Cancel button
            Button("Cancel", action: onCancel)
                .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

#Preview {
    RecordingToolbarView(
        selectedFormat: .constant(.mov),
        onRecord: {},
        onCancel: {}
    )
    .padding()
}
```

### Step 2: Create RecordingStatusBarView
File: `ZapShot/Features/Recording/RecordingStatusBarView.swift`

```swift
import SwiftUI

struct RecordingStatusBarView: View {
    @ObservedObject var recorder: ScreenRecordingManager
    let onStop: () -> Void

    @State private var indicatorOpacity: Double = 1.0

    var body: some View {
        HStack(spacing: 16) {
            // Recording indicator (pulsing red dot)
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .opacity(recorder.isPaused ? 0.4 : indicatorOpacity)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                          value: indicatorOpacity)
                .onAppear { indicatorOpacity = 0.3 }

            // Timer display
            Text(recorder.formattedDuration)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(recorder.isPaused ? .secondary : .primary)
                .frame(width: 60, alignment: .leading)

            Divider()
                .frame(height: 20)

            // Pause/Resume button
            Button(action: { recorder.togglePause() }) {
                Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                    .frame(width: 20)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            // Stop button
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .foregroundColor(.red)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
    }
}

#Preview {
    RecordingStatusBarView(
        recorder: ScreenRecordingManager.shared,
        onStop: {}
    )
    .padding()
}
```

### Step 3: Create RecordingToolbarWindow
File: `ZapShot/Features/Recording/RecordingToolbarWindow.swift`

```swift
import AppKit
import SwiftUI

enum RecordingToolbarMode {
    case preRecord
    case recording
}

@MainActor
final class RecordingToolbarWindow: NSWindow {

    private var anchorRect: CGRect
    private var mode: RecordingToolbarMode = .preRecord
    private var hostingView: NSHostingView<AnyView>?

    // Callbacks
    var onRecord: (() -> Void)?
    var onCancel: (() -> Void)?
    var onStop: (() -> Void)?

    // State
    @Published var selectedFormat: VideoFormat = .mov

    init(anchorRect: CGRect) {
        self.anchorRect = anchorRect

        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        configureWindow()
        showPreRecordToolbar()
    }

    private func configureWindow() {
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hasShadow = false
        isReleasedWhenClosed = false
    }

    func showPreRecordToolbar() {
        mode = .preRecord

        let binding = Binding<VideoFormat>(
            get: { [weak self] in self?.selectedFormat ?? .mov },
            set: { [weak self] in self?.selectedFormat = $0 }
        )

        let view = RecordingToolbarView(
            selectedFormat: binding,
            onRecord: { [weak self] in self?.onRecord?() },
            onCancel: { [weak self] in self?.onCancel?() }
        )

        setContent(AnyView(view))
        positionBelowRect(anchorRect)
    }

    func showRecordingStatusBar(recorder: ScreenRecordingManager) {
        mode = .recording

        let view = RecordingStatusBarView(
            recorder: recorder,
            onStop: { [weak self] in self?.onStop?() }
        )

        setContent(AnyView(view))
        positionBelowRect(anchorRect)
    }

    private func setContent(_ view: AnyView) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        contentView = hosting
        hostingView = hosting

        setContentSize(hosting.fittingSize)
    }

    private func positionBelowRect(_ rect: CGRect) {
        guard let size = contentView?.fittingSize else { return }

        // Position centered below the selection rect
        let x = rect.midX - size.width / 2
        let y = rect.minY - size.height - 20

        // Ensure minimum distance from screen edge
        let safeY = max(y, 40)

        setFrameOrigin(CGPoint(x: x, y: safeY))
        orderFrontRegardless()
    }

    func updateAnchorRect(_ rect: CGRect) {
        anchorRect = rect
        positionBelowRect(rect)
    }
}
```

### Step 4: Create RecordingCoordinator
File: `ZapShot/Features/Recording/RecordingCoordinator.swift`

```swift
import AppKit
import SwiftUI

@MainActor
final class RecordingCoordinator: ObservableObject {

    static let shared = RecordingCoordinator()

    @Published private(set) var isActive = false

    private var toolbarWindow: RecordingToolbarWindow?
    private var selectedRect: CGRect?
    private let recorder = ScreenRecordingManager.shared

    private init() {}

    // MARK: - Public API

    /// Start recording flow after area selection
    func showToolbar(for rect: CGRect) {
        guard !isActive else { return }
        isActive = true
        selectedRect = rect

        toolbarWindow = RecordingToolbarWindow(anchorRect: rect)
        toolbarWindow?.onRecord = { [weak self] in
            self?.startRecording()
        }
        toolbarWindow?.onCancel = { [weak self] in
            self?.cancel()
        }
        toolbarWindow?.onStop = { [weak self] in
            self?.stopRecording()
        }

        // Load format from preferences
        if let formatString = UserDefaults.standard.string(forKey: PreferencesKeys.recordingFormat),
           let format = VideoFormat(rawValue: formatString) {
            toolbarWindow?.selectedFormat = format
        }
    }

    func cancel() {
        Task {
            await recorder.cancelRecording()
        }
        cleanup()
    }

    // MARK: - Private

    private func startRecording() {
        guard let rect = selectedRect, let window = toolbarWindow else { return }

        let format = window.selectedFormat
        let fps = UserDefaults.standard.integer(forKey: PreferencesKeys.recordingFPS)
        let captureAudio = UserDefaults.standard.bool(forKey: PreferencesKeys.recordingCaptureAudio)

        // Get save directory
        let saveDirectory: URL
        if let path = UserDefaults.standard.string(forKey: PreferencesKeys.exportLocation),
           !path.isEmpty {
            saveDirectory = URL(fileURLWithPath: path)
        } else {
            saveDirectory = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
                .appendingPathComponent("ZapShot")
        }

        Task {
            do {
                try await recorder.prepareRecording(
                    rect: rect,
                    format: format,
                    fps: fps > 0 ? fps : 30,
                    captureAudio: captureAudio,
                    saveDirectory: saveDirectory
                )

                try await recorder.startRecording()

                // Switch to status bar
                window.showRecordingStatusBar(recorder: recorder)

            } catch {
                print("Recording failed: \(error)")
                cancel()
            }
        }
    }

    private func stopRecording() {
        Task {
            let url = await recorder.stopRecording()

            if let url = url {
                // Show in Finder or trigger Quick Access (future)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }

            cleanup()
        }
    }

    private func cleanup() {
        toolbarWindow?.close()
        toolbarWindow = nil
        selectedRect = nil
        isActive = false
    }
}
```

### Step 5: Add Recording PreferencesKeys
File: `ZapShot/Features/Preferences/PreferencesKeys.swift`

```swift
// Add to PreferencesKeys enum
// Recording
static let recordingFormat = "recording.format"
static let recordingFPS = "recording.fps"
static let recordingQuality = "recording.quality"
static let recordingCaptureAudio = "recording.captureAudio"
static let recordingCaptureMicrophone = "recording.captureMicrophone"
```

### Step 6: Update ScreenCaptureViewModel
File: `ZapShot/Core/ScreenCaptureViewModel.swift`

```swift
/// Start recording area selection flow
func startRecordingFlow() {
    guard hasPermission else {
        requestPermission()
        return
    }

    // Check if already recording
    guard !RecordingCoordinator.shared.isActive else { return }

    let controller = AreaSelectionController()
    controller.startSelection(mode: .recording) { rect, mode in
        guard let rect = rect else { return }

        Task { @MainActor in
            RecordingCoordinator.shared.showToolbar(for: rect)
        }
    }
}
```

### Step 7: Create folder structure
```
ZapShot/Features/Recording/
├── RecordingToolbarWindow.swift
├── RecordingToolbarView.swift
├── RecordingStatusBarView.swift
└── RecordingCoordinator.swift
```

## Todo List
- [ ] Create Recording folder under Features
- [ ] Create RecordingToolbarView.swift with format picker and buttons
- [ ] Create RecordingStatusBarView.swift with timer and controls
- [ ] Create RecordingToolbarWindow.swift as NSWindow container
- [ ] Create RecordingCoordinator.swift to manage flow
- [ ] Add recording keys to PreferencesKeys.swift
- [ ] Update ScreenCaptureViewModel.startRecordingFlow()
- [ ] Test toolbar positioning below selection
- [ ] Test format picker saves selection
- [ ] Test recording indicator animation
- [ ] Test pause/resume UI updates

## Success Criteria
1. Toolbar appears below selected area after selection
2. Format picker toggles between MOV/MP4
3. Record button starts recording and switches to status bar
4. Timer counts up accurately
5. Pause button toggles to Resume and dims indicator
6. Stop button saves video and opens in Finder
7. Cancel closes toolbar without saving

## Risk Assessment
| Risk | Impact | Mitigation |
|------|--------|------------|
| Toolbar outside screen bounds | Medium | Clamp position to safe area |
| Window focus issues | Low | Use floating level and orderFrontRegardless |
| Animation performance | Low | Use simple opacity animation |
| State sync between views | Medium | Use ObservableObject pattern |
