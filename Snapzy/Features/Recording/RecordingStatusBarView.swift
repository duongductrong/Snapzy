//
//  RecordingStatusBarView.swift
//  Snapzy
//
//  Status bar shown during active recording with timer and controls
//  Styled to match Apple's native macOS recording toolbar aesthetic
//

import SwiftUI

struct RecordingStatusBarView: View {
  @ObservedObject var recorder: ScreenRecordingManager
  let onDelete: () -> Void
  let onRestart: () -> Void
  let onStop: () -> Void

  @State private var indicatorOpacity: Double = 1.0

  var body: some View {
    HStack(spacing: ToolbarConstants.itemSpacing) {
      // Recording indicator (pulsing red dot)
      Circle()
        .fill(.red)
        .frame(width: 10, height: 10)
        .opacity(recorder.isPaused ? 0.4 : indicatorOpacity)
        .animation(
          .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
          value: indicatorOpacity
        )
        .onAppear { indicatorOpacity = 0.3 }
        .accessibilityLabel(recorder.isPaused ? "Recording paused" : "Recording in progress")

      // Timer display with integrated Stop action
      Button(action: onStop) {
        HStack(spacing: 6) {
          Text(recorder.formattedDuration)
            .font(.system(.body, design: .monospaced))
            .foregroundColor(recorder.isPaused ? .secondary : .primary)
          Image(systemName: "stop.fill")
        }
      }
      .buttonStyle(StopButtonStyle())
      .fixedSize()
      .accessibilityLabel("Stop recording - Duration: \(recorder.formattedDuration)")
      .accessibilityHint("Stops and saves the recording")

      RecordingToolbarDivider()

      // Pause/Resume button
      ToolbarIconButton(
        systemName: recorder.isPaused ? "play.fill" : "pause.fill",
        action: { recorder.togglePause() },
        accessibilityLabel: recorder.isPaused ? "Resume recording" : "Pause recording"
      )

      RecordingToolbarDivider()

      // Restart button
      ToolbarIconButton(
        systemName: "arrow.counterclockwise",
        action: onRestart,
        accessibilityLabel: "Restart recording"
      )

      RecordingToolbarDivider()

      // Delete button
      ToolbarIconButton(
        systemName: "trash",
        action: onDelete,
        accessibilityLabel: "Delete recording"
      )
    }
    .padding(.horizontal, ToolbarConstants.horizontalPadding)
    .padding(.vertical, ToolbarConstants.verticalPadding)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: ToolbarConstants.toolbarCornerRadius))
    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Recording status bar")
  }
}

#Preview {
  RecordingStatusBarView(
    recorder: ScreenRecordingManager.shared,
    onDelete: {},
    onRestart: {},
    onStop: {}
  )
  .padding()
}
