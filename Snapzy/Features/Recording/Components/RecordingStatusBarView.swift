//
//  RecordingStatusBarView.swift
//  Snapzy
//
//  Status bar shown during active recording with timer and controls
//  Styled to match Apple's native macOS recording toolbar aesthetic
//
//  Layout: [≡] | [● 00:00:00] | [⏸] [✏️] | [↺] | [🗑] | [Stop]
//

import SwiftUI

// MARK: - Preference Key for annotate button position

private struct AnnotateButtonCenterXKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

struct RecordingStatusBarView: View {
  @ObservedObject var recorder: ScreenRecordingManager
  @ObservedObject var annotationState: RecordingAnnotationState
  let onDelete: () -> Void
  let onRestart: () -> Void
  let onStop: () -> Void

  /// Reports the center-X of the annotate button in local coordinate space
  var onAnnotateButtonLayout: ((CGFloat) -> Void)?

  @State private var indicatorOpacity: Double = 1.0

  var body: some View {
    HStack(spacing: ToolbarConstants.itemSpacing) {
      // Drag handle (visual only — drag handled by NSWindow)
      Image(systemName: "line.3.horizontal")
        .font(.system(size: 10, weight: .bold))
        .foregroundColor(.primary.opacity(0.3))
        .frame(width: 20, height: 20)

      RecordingToolbarDivider()

      // Recording indicator (pulsing red dot) + Timer
      HStack(spacing: 8) {
        Circle()
          .fill(.red)
          .frame(width: 8, height: 8)
          .opacity(recorder.isPaused ? 0.4 : indicatorOpacity)
          .animation(
            .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
            value: indicatorOpacity
          )
          .onAppear { indicatorOpacity = 0.3 }
          .accessibilityLabel(recorder.isPaused ? "Recording paused" : "Recording in progress")

        Text(recorder.formattedDuration)
          .font(.system(size: 13, weight: .medium, design: .monospaced))
          .foregroundColor(recorder.isPaused ? .primary.opacity(0.5) : .primary)
      }
      .padding(.horizontal, 8)

      RecordingToolbarDivider()

      // Pause/Resume button
      ToolbarIconButton(
        systemName: recorder.isPaused ? "play.fill" : "pause.fill",
        action: { recorder.togglePause() },
        accessibilityLabel: recorder.isPaused ? "Resume recording" : "Pause recording"
      )

      // Annotate toggle button
      ToolbarIconButton(
        systemName: annotationState.isAnnotationEnabled
          ? "pencil.tip.crop.circle.fill"
          : "pencil.tip.crop.circle",
        action: { annotationState.isAnnotationEnabled.toggle() },
        accessibilityLabel: annotationState.isAnnotationEnabled
          ? "Disable annotations" : "Enable annotations"
      )
      .background(
        GeometryReader { geo in
          Color.clear.preference(
            key: AnnotateButtonCenterXKey.self,
            value: geo.frame(in: .named("statusBar")).midX
          )
        }
      )

      RecordingToolbarDivider()

      // Restart button
      ToolbarIconButton(
        systemName: "arrow.counterclockwise",
        action: onRestart,
        accessibilityLabel: "Restart recording"
      )

      // Delete button
      ToolbarIconButton(
        systemName: "trash",
        action: onDelete,
        accessibilityLabel: "Delete recording"
      )

      RecordingToolbarDivider()

      // Stop button (native text style)
      Button(action: onStop) {
        Text("Stop")
      }
      .buttonStyle(StopButtonStyle())
      .fixedSize()
      .accessibilityLabel("Stop recording - Duration: \(recorder.formattedDuration)")
      .accessibilityHint("Stops and saves the recording")
    }
    .coordinateSpace(name: "statusBar")
    .padding(.horizontal, ToolbarConstants.horizontalPadding)
    .padding(.vertical, ToolbarConstants.verticalPadding)
    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    .onPreferenceChange(AnnotateButtonCenterXKey.self) { centerX in
      onAnnotateButtonLayout?(centerX)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Recording status bar")
  }
}

#Preview {
  RecordingStatusBarView(
    recorder: ScreenRecordingManager.shared,
    annotationState: RecordingAnnotationState(),
    onDelete: {},
    onRestart: {},
    onStop: {}
  )
  .padding()
}
