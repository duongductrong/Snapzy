# Phase 4: Active Recording State

## Context
- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** Phase 1 (ScreenRecorderManager), Phase 3 (Toolbar)
- **Research:** [UX Patterns Report](./research/researcher-02-ux-patterns-report.md)

## Overview
| Field | Value |
|-------|-------|
| Date | 2026-01-17 |
| Priority | P1 - High |
| Status | pending |
| Effort | 2-3 hours |

Handle UI during active recording: menu bar icon changes to stop state, optional floating timer with stop button.

## Key Insights
1. Menu bar icon swap: `camera.aperture` -> `stop.circle.fill` (red tint)
2. Timer view is optional but recommended for UX - small, draggable
3. Click menu bar icon OR timer stop button ends recording
4. Timer shows elapsed time in `MM:SS` format

## Requirements

### Functional
- [x] Menu bar icon changes to "stop" state during recording
- [x] Click menu bar icon stops recording
- [x] Show floating timer with elapsed time (optional)
- [x] Timer has stop button
- [x] Timer is draggable

### Non-Functional
- Timer updates every second
- Minimal CPU usage for timer
- Timer remembers position (optional for MVP)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    ZapShotApp                            │
│  MenuBarExtra(systemImage: recordingIcon)               │
│    - idle: "camera.aperture"                            │
│    - recording: "stop.circle.fill"                      │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│              RecordingTimerController                    │
│  + show()                                                │
│  + hide()                                                │
│  - panel: NSPanel                                        │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│               RecordingTimerView                         │
│  ┌──────────────────────────────────────┐               │
│  │  ● 00:32          [Stop]            │               │
│  └──────────────────────────────────────┘               │
└─────────────────────────────────────────────────────────┘
```

## Related Code Files
| File | Purpose |
|------|---------|
| `ZapShot/App/ZapShotApp.swift` | MenuBarExtra icon binding |
| `ZapShot/Core/ScreenRecorderManager.swift` | isRecording, recordingDuration |

## Code Draft

### RecordingTimerView.swift

```swift
//
//  RecordingTimerView.swift
//  ZapShot
//
//  Floating timer shown during active recording
//

import SwiftUI

struct RecordingTimerView: View {
  let duration: TimeInterval
  let onStop: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      // Recording indicator dot
      Circle()
        .fill(Color.red)
        .frame(width: 8, height: 8)

      // Elapsed time
      Text(formatDuration(duration))
        .font(.system(size: 13, weight: .medium, design: .monospaced))
        .foregroundColor(.white)

      // Stop button
      Button(action: onStop) {
        Image(systemName: "stop.fill")
          .font(.system(size: 12))
          .foregroundColor(.white)
          .frame(width: 24, height: 24)
          .background(Color.red.opacity(0.8))
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      .buttonStyle(.plain)
      .help("Stop Recording")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.ultraThinMaterial)
    .clipShape(Capsule())
    .overlay(
      Capsule()
        .stroke(Color.white.opacity(0.1), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
  }

  private func formatDuration(_ seconds: TimeInterval) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%02d:%02d", mins, secs)
  }
}

#Preview {
  RecordingTimerView(duration: 92, onStop: {})
    .padding()
    .background(Color.gray)
}
```

### RecordingTimerController.swift

```swift
//
//  RecordingTimerController.swift
//  ZapShot
//
//  Controller for floating recording timer window
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingTimerController {

  private var panel: NSPanel?
  private var cancellables = Set<AnyCancellable>()

  func show(onStop: @escaping () -> Void) {
    let timerSize = CGSize(width: 140, height: 40)

    // Position top-center of main screen
    guard let screen = NSScreen.main else { return }
    let origin = CGPoint(
      x: screen.visibleFrame.midX - timerSize.width / 2,
      y: screen.visibleFrame.maxY - timerSize.height - 20
    )

    let panel = NSPanel(
      contentRect: NSRect(origin: origin, size: timerSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.level = .floating
    panel.hasShadow = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isMovableByWindowBackground = true  // Draggable

    // Bind to ScreenRecorderManager duration
    let manager = ScreenRecorderManager.shared

    let content = TimerHostView(
      manager: manager,
      onStop: { [weak self] in
        self?.hide()
        onStop()
      }
    )

    let hostingView = NSHostingView(rootView: content)
    hostingView.frame = NSRect(origin: .zero, size: timerSize)
    panel.contentView = hostingView

    panel.orderFrontRegardless()
    self.panel = panel
  }

  func hide() {
    panel?.close()
    panel = nil
    cancellables.removeAll()
  }

  var isVisible: Bool { panel != nil }
}

// Helper view to observe manager
private struct TimerHostView: View {
  @ObservedObject var manager: ScreenRecorderManager
  let onStop: () -> Void

  var body: some View {
    RecordingTimerView(
      duration: manager.recordingDuration,
      onStop: onStop
    )
  }
}
```

### MenuBarContentView Updates

```swift
// In ZapShotApp.swift - update MenuBarExtra

@main
struct ZapShotApp: App {
  @StateObject private var viewModel = ScreenCaptureViewModel()
  @StateObject private var recorder = ScreenRecorderManager.shared

  var body: some Scene {
    MenuBarExtra("ZapShot", systemImage: menuBarIcon) {
      MenuBarContentView(viewModel: viewModel, recorder: recorder)
    }
    // ...
  }

  private var menuBarIcon: String {
    recorder.isRecording ? "stop.circle.fill" : "camera.aperture"
  }
}

// In MenuBarContentView - add recording controls
struct MenuBarContentView: View {
  @ObservedObject var viewModel: ScreenCaptureViewModel
  @ObservedObject var recorder: ScreenRecorderManager

  var body: some View {
    Group {
      if recorder.isRecording {
        // Show stop option when recording
        Button {
          Task { try? await recorder.stopRecording() }
        } label: {
          Label("Stop Recording", systemImage: "stop.circle")
        }
        .keyboardShortcut("5", modifiers: [.command, .shift])

        Text("Recording: \(formatDuration(recorder.recordingDuration))")
          .foregroundColor(.secondary)

        Divider()
      } else {
        // Normal capture options
        Button { viewModel.captureArea() } label: {
          Label("Capture Area", systemImage: "crop")
        }
        // ... rest of menu
      }
    }
  }

  private func formatDuration(_ seconds: TimeInterval) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%02d:%02d", mins, secs)
  }
}
```

## Implementation Steps

### Step 1: Create RecordingTimerView.swift
- [ ] Create `ZapShot/Features/Recording/RecordingTimerView.swift`
- [ ] Add recording dot, time display, stop button
- [ ] Style with capsule shape, blur material

### Step 2: Create RecordingTimerController.swift
- [ ] Create `ZapShot/Features/Recording/RecordingTimerController.swift`
- [ ] Setup draggable NSPanel
- [ ] Bind to ScreenRecorderManager.recordingDuration

### Step 3: Update ZapShotApp.swift
- [ ] Add @StateObject for ScreenRecorderManager
- [ ] Compute menuBarIcon based on isRecording
- [ ] Update MenuBarContentView for recording state

### Step 4: Integrate timer with recording flow
- [ ] Show timer when recording starts
- [ ] Hide timer when recording stops
- [ ] Wire stop button to stopRecording()

## Todo
- [ ] Create RecordingTimerView.swift
- [ ] Create RecordingTimerController.swift
- [ ] Update ZapShotApp for menu bar icon swap
- [ ] Update MenuBarContentView for recording state
- [ ] Integrate timer show/hide with recording lifecycle

## Success Criteria
1. Menu bar icon changes to stop.circle.fill during recording
2. Clicking menu bar shows "Stop Recording" option
3. Timer appears at top of screen during recording
4. Timer shows accurate elapsed time (MM:SS)
5. Timer is draggable
6. Stop button on timer ends recording
7. Timer disappears when recording stops

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Timer obscures content | Low | Low | Draggable, positioned at top |
| Menu bar icon not updating | Low | Medium | Use @ObservedObject properly |

## Security Considerations
- No sensitive data involved

## Next Steps
After completion, recording stops and flows to Phase 5 (Post-Recording) for thumbnail and save actions.

## Unresolved Questions
1. Should timer position persist across sessions?
2. Add preference to disable floating timer?
