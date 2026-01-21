# Phase 3: Recording Toolbar UI

## Context
- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** Phase 1 (ScreenRecorderManager)
- **Research:** [UX Patterns Report](./research/researcher-02-ux-patterns-report.md)

## Overview
| Field | Value |
|-------|-------|
| Date | 2026-01-17 |
| Priority | P1 - High |
| Status | pending |
| Effort | 2-3 hours |

Create floating toolbar that appears after area selection. Contains Record button, Mic toggle, Cancel button. Matches app aesthetic (rounded corners, blur material, dark mode).

## Key Insights
1. Use `NSPanel` with `.floating` level - same pattern as `FloatingPanel`
2. Position toolbar centered below selection rect
3. Toolbar hides when recording starts
4. Reuse existing `FloatingPanelController` pattern for window management

## Requirements

### Functional
- [x] Show toolbar after user completes area selection
- [x] Record button (red circle) starts recording
- [x] Mic toggle enables/disables microphone capture
- [x] Cancel button (X) dismisses toolbar and selection
- [x] Toolbar auto-positions below selection area

### Non-Functional
- Match app design: rounded corners, blur material
- Toolbar stays on top of all windows
- Works across multiple displays
- Escape key cancels

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│              RecordingToolbarController                  │
├─────────────────────────────────────────────────────────┤
│ + show(below: CGRect, onRecord:, onCancel:)             │
│ + hide()                                                 │
│ - panel: NSPanel?                                        │
│ - selectionRect: CGRect                                  │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                RecordingToolbarView                      │
│  ┌─────────┐  ┌─────────────┐  ┌─────────┐             │
│  │ Record  │  │ Mic Toggle  │  │ Cancel  │             │
│  │   ●     │  │  🎤 / 🔇    │  │    ✕    │             │
│  └─────────┘  └─────────────┘  └─────────┘             │
└─────────────────────────────────────────────────────────┘
```

## Related Code Files
| File | Purpose |
|------|---------|
| `ZapShot/Features/FloatingScreenshot/FloatingPanel.swift` | Reference for NSPanel setup |
| `ZapShot/Features/FloatingScreenshot/FloatingPanelController.swift` | Pattern for controller |

## Code Draft

### RecordingToolbarView.swift

```swift
//
//  RecordingToolbarView.swift
//  ZapShot
//
//  Floating toolbar for screen recording controls
//

import SwiftUI

struct RecordingToolbarView: View {
  @Binding var micEnabled: Bool
  let onRecord: () -> Void
  let onCancel: () -> Void

  var body: some View {
    HStack(spacing: 16) {
      // Record button
      Button(action: onRecord) {
        Circle()
          .fill(Color.red)
          .frame(width: 28, height: 28)
          .overlay(
            Circle()
              .stroke(Color.white.opacity(0.3), lineWidth: 2)
          )
      }
      .buttonStyle(.plain)
      .help("Start Recording")

      Divider()
        .frame(height: 24)

      // Mic toggle
      Button {
        micEnabled.toggle()
      } label: {
        Image(systemName: micEnabled ? "mic.fill" : "mic.slash")
          .font(.system(size: 16))
          .foregroundColor(micEnabled ? .white : .gray)
          .frame(width: 28, height: 28)
      }
      .buttonStyle(.plain)
      .help(micEnabled ? "Microphone On" : "Microphone Off")

      Divider()
        .frame(height: 24)

      // Cancel button
      Button(action: onCancel) {
        Image(systemName: "xmark")
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(.white.opacity(0.8))
          .frame(width: 28, height: 28)
      }
      .buttonStyle(.plain)
      .help("Cancel")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.white.opacity(0.1), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
  }
}

#Preview {
  RecordingToolbarView(
    micEnabled: .constant(true),
    onRecord: {},
    onCancel: {}
  )
  .padding()
  .background(Color.gray)
}
```

### RecordingToolbarController.swift

```swift
//
//  RecordingToolbarController.swift
//  ZapShot
//
//  Controller for managing recording toolbar window
//

import AppKit
import SwiftUI

@MainActor
final class RecordingToolbarController {

  private var panel: NSPanel?
  private var selectionRect: CGRect = .zero

  /// Show toolbar below the selection rect
  func show(
    below rect: CGRect,
    micEnabled: Binding<Bool>,
    onRecord: @escaping () -> Void,
    onCancel: @escaping () -> Void
  ) {
    selectionRect = rect

    let toolbarSize = CGSize(width: 160, height: 48)

    // Position centered below selection
    let origin = CGPoint(
      x: rect.midX - toolbarSize.width / 2,
      y: rect.minY - toolbarSize.height - 12
    )

    // Ensure toolbar stays on screen
    let adjustedOrigin = adjustOriginForScreen(origin, size: toolbarSize)

    let frame = NSRect(origin: adjustedOrigin, size: toolbarSize)

    let panel = NSPanel(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.level = .floating
    panel.hasShadow = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isMovableByWindowBackground = false

    let content = RecordingToolbarView(
      micEnabled: micEnabled,
      onRecord: { [weak self] in
        self?.hide()
        onRecord()
      },
      onCancel: { [weak self] in
        self?.hide()
        onCancel()
      }
    )

    let hostingView = NSHostingView(rootView: content)
    hostingView.frame = NSRect(origin: .zero, size: toolbarSize)
    panel.contentView = hostingView

    panel.orderFrontRegardless()
    self.panel = panel
  }

  func hide() {
    panel?.close()
    panel = nil
  }

  var isVisible: Bool {
    panel != nil
  }

  private func adjustOriginForScreen(_ origin: CGPoint, size: CGSize) -> CGPoint {
    guard let screen = NSScreen.main else { return origin }

    var adjusted = origin

    // Keep on screen horizontally
    if adjusted.x < screen.visibleFrame.minX {
      adjusted.x = screen.visibleFrame.minX + 8
    }
    if adjusted.x + size.width > screen.visibleFrame.maxX {
      adjusted.x = screen.visibleFrame.maxX - size.width - 8
    }

    // If below screen, show above selection instead
    if adjusted.y < screen.visibleFrame.minY {
      adjusted.y = selectionRect.maxY + 12
    }

    return adjusted
  }
}
```

## Implementation Steps

### Step 1: Create RecordingToolbarView.swift
- [ ] Create `ZapShot/Features/Recording/RecordingToolbarView.swift`
- [ ] Add Record button (red circle)
- [ ] Add Mic toggle button
- [ ] Add Cancel button
- [ ] Style with blur material, rounded corners

### Step 2: Create RecordingToolbarController.swift
- [ ] Create `ZapShot/Features/Recording/RecordingToolbarController.swift`
- [ ] Setup NSPanel with floating level
- [ ] Position below selection rect
- [ ] Handle screen edge cases

### Step 3: Integrate with selection flow
- [ ] After area selection completes, show toolbar
- [ ] Pass mic binding to toolbar
- [ ] Wire Record callback to start recording
- [ ] Wire Cancel to dismiss overlay

### Step 4: Handle escape key
- [ ] Add local key monitor for Escape
- [ ] Dismiss toolbar on Escape

## Todo
- [ ] Create RecordingToolbarView.swift
- [ ] Create RecordingToolbarController.swift
- [ ] Integrate with area selection flow
- [ ] Add escape key handling
- [ ] Test multi-display positioning

## Success Criteria
1. Toolbar appears after area selection
2. Toolbar positioned below selection, centered
3. Record button starts capture
4. Mic toggle updates ScreenRecorderManager.micEnabled
5. Cancel dismisses toolbar and overlay
6. Escape key cancels
7. Toolbar stays on screen (edge detection)

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Toolbar appears behind overlay | Medium | Medium | Use higher window level than overlay |
| Position off-screen on small displays | Low | Low | Edge detection logic |

## Security Considerations
- No sensitive data
- Mic permission handled by ScreenRecorderManager

## Next Steps
After completion, toolbar connects to ScreenRecorderManager (Phase 1). Phase 4 handles active recording state.

## Unresolved Questions
1. Should toolbar be draggable?
2. Add keyboard shortcut hint text to buttons?
