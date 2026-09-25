//
//  RecordingStatusBarView.swift
//  Snapzy
//
//  Status bar shown during active recording with timer and controls
//  Styled to match Apple's native macOS recording toolbar aesthetic
//
//  Layout: [≡] | [● 00:00:00] | [⏸] [✏️] | [↺] | [🗑] | [Stop]
//

import AppKit
import SwiftUI

// MARK: - AppKit anchor reporter

/// A transparent AppKit node is used instead of a SwiftUI PreferenceKey because native Liquid
/// Glass can isolate preferences emitted from descendants of a glass control/container.
private final class RecordingToolbarAnchorReportingView: NSView {
  var onLayout: ((CGFloat) -> Void)?
  private var lastReportedCenterX: CGFloat?

  override func hitTest(_: NSPoint) -> NSView? {
    nil
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    reportAnchorPosition()
  }

  override func layout() {
    super.layout()
    reportAnchorPosition()
  }

  func reportAnchorPosition() {
    guard let contentView = window?.contentView else { return }
    guard bounds.width > 0, bounds.height > 0 else { return }
    let frameInContentView = convert(bounds, to: contentView)
    let centerX = frameInContentView.midX
    guard centerX.isFinite else { return }
    guard lastReportedCenterX.map({ abs($0 - centerX) > 0.01 }) ?? true else { return }

    lastReportedCenterX = centerX
    onLayout?(centerX)
  }
}

private struct RecordingToolbarAnchorReporter: NSViewRepresentable {
  let onLayout: (CGFloat) -> Void

  func makeNSView(context _: Context) -> RecordingToolbarAnchorReportingView {
    let view = RecordingToolbarAnchorReportingView()
    view.onLayout = onLayout
    return view
  }

  func updateNSView(_ nsView: RecordingToolbarAnchorReportingView, context _: Context) {
    nsView.onLayout = onLayout
    nsView.reportAnchorPosition()
  }
}

struct RecordingStatusBarView: View {
  @ObservedObject var recorder: ScreenRecordingManager
  @ObservedObject var audioLevelMeter: RecordingAudioLevelMeter
  @ObservedObject var annotationState: RecordingAnnotationState
  @ObservedObject var state: RecordingToolbarState
  let onDelete: () -> Void
  let onRestart: () -> Void
  let onStop: () -> Void

  /// Reports the center-X of the annotate button relative to the hosting window's content view.
  var onAnnotateButtonLayout: ((CGFloat) -> Void)?

  @State private var indicatorOpacity: Double = 1.0

  /// Show the audio waveform only when it accurately describes the recording:
  /// microphone is being captured and the output supports audio (GIF has none).
  private var shouldShowWaveform: Bool {
    state.captureMicrophone && state.outputMode != .gif
  }

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
          .accessibilityLabel(
            recorder.isPaused
              ? L10n.RecordingToolbar.recordingPaused
              : L10n.RecordingToolbar.recordingInProgress
          )

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
        accessibilityLabel: recorder.isPaused
          ? L10n.RecordingToolbar.resumeRecording
          : L10n.RecordingToolbar.pauseRecording
      )

      // Annotate toggle button
      // Keep the reporter as a sibling of the button so its AppKit frame is the actual trigger
      // frame, independent of the button's native Liquid Glass subtree.
      ZStack {
        ToolbarIconButton(
          systemName: annotationState.isAnnotationEnabled
            ? "pencil.tip.crop.circle.fill"
            : "pencil.tip.crop.circle",
          action: { annotationState.isAnnotationEnabled.toggle() },
          accessibilityLabel: annotationState.isAnnotationEnabled
            ? L10n.RecordingToolbar.disableAnnotations
            : L10n.RecordingToolbar.enableAnnotations
        )

        RecordingToolbarAnchorReporter { centerX in
          onAnnotateButtonLayout?(centerX)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
      .frame(
        width: ToolbarConstants.iconButtonSize,
        height: ToolbarConstants.iconButtonSize
      )

      RecordingToolbarDivider()

      // Restart button
      ToolbarIconButton(
        systemName: "arrow.counterclockwise",
        action: onRestart,
        accessibilityLabel: L10n.RecordingToolbar.restartRecording
      )

      // Delete button
      ToolbarIconButton(
        systemName: "trash",
        action: onDelete,
        accessibilityLabel: L10n.RecordingToolbar.deleteRecording
      )

      RecordingToolbarDivider()

      // Stop button (native text style)
      Button(action: onStop) {
        Text(L10n.RecordingToolbar.stop)
      }
      .buttonStyle(StopButtonStyle())
      .fixedSize()
      .accessibilityLabel(L10n.RecordingToolbar.stopRecordingAccessibility(recorder.formattedDuration))
      .accessibilityHint(L10n.RecordingToolbar.stopRecordingHint)
    }
    .padding(.horizontal, ToolbarConstants.horizontalPadding)
    .padding(.vertical, ToolbarConstants.verticalPadding)
    .liquidGlassGroup(spacing: ToolbarConstants.itemSpacing)
    .background {
      // Hidden entirely (not just faded) when no mic audio is captured so the
      // TimelineView animation stops too.
      if shouldShowWaveform {
        RecordingWaveformView(
          level: audioLevelMeter.level,
          isActive: recorder.isRecording && !recorder.isPaused
        )
        .opacity(recorder.isPaused ? 0.35 : 1.0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(L10n.RecordingToolbar.statusBarAccessibility)
  }
}

#Preview {
  RecordingStatusBarView(
    recorder: ScreenRecordingManager.shared,
    audioLevelMeter: ScreenRecordingManager.shared.audioLevelMeter,
    annotationState: RecordingAnnotationState(),
    state: RecordingToolbarState(),
    onDelete: {},
    onRestart: {},
    onStop: {}
  )
  .padding()
}
