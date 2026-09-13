//
//  VideoEditorVideoControlsView.swift
//  Snapzy
//
//  Playback controls with play/pause button and time display
//

import AVFoundation
import SwiftUI

private enum VideoControlsSection: Hashable {
  case left
  case right
}

private enum VideoControlsLayoutStyle {
  case compact
  case regular
  case expanded

  static func forWidth(_ width: CGFloat) -> Self {
    switch width {
    case ..<640:
      .compact
    case ..<920:
      .regular
    default:
      .expanded
    }
  }

  var outerSpacing: CGFloat {
    switch self {
    case .compact: 12
    case .regular: 14
    case .expanded: 16
    }
  }

  var centerSpacing: CGFloat {
    switch self {
    case .compact: 10
    case .regular: 12
    case .expanded: 14
    }
  }

  var verticalPadding: CGFloat {
    switch self {
    case .compact: 6
    case .regular: 7
    case .expanded: 8
    }
  }

  var metadataSpacing: CGFloat {
    switch self {
    case .compact: 6
    case .regular: 7
    case .expanded: 8
    }
  }

  var timeLabelWidth: CGFloat {
    switch self {
    case .compact: 42
    case .regular: 46
    case .expanded: 50
    }
  }

  var timeFontSize: CGFloat {
    switch self {
    case .compact: 12
    case .regular, .expanded: 13
    }
  }

  var transportButtonSize: CGFloat {
    switch self {
    case .compact: 24
    case .regular: 26
    case .expanded: 28
    }
  }

  var transportIconSize: CGFloat {
    switch self {
    case .compact: 15
    case .regular: 16
    case .expanded: 18
    }
  }

  var playButtonSize: CGFloat {
    switch self {
    case .compact: 40
    case .regular: 42
    case .expanded: 44
    }
  }

  var playIconSize: CGFloat {
    switch self {
    case .compact: 16
    case .regular: 18
    case .expanded: 20
    }
  }

  var badgeIconSize: CGFloat {
    switch self {
    case .compact: 10
    case .regular, .expanded: 11
    }
  }

  var badgeFontSize: CGFloat {
    switch self {
    case .compact: 10
    case .regular, .expanded: 11
    }
  }
}

private struct VideoControlsSectionWidthKey: PreferenceKey {
  static var defaultValue: [VideoControlsSection: CGFloat] = [:]

  static func reduce(
    value: inout [VideoControlsSection: CGFloat],
    nextValue: () -> [VideoControlsSection: CGFloat]
  ) {
    value.merge(nextValue(), uniquingKeysWith: { _, next in next })
  }
}

private struct VideoControlsContainerWidthKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

private extension View {
  func measureVideoControlsWidth(for section: VideoControlsSection) -> some View {
    background(
      GeometryReader { proxy in
        Color.clear.preference(
          key: VideoControlsSectionWidthKey.self,
          value: [section: proxy.size.width]
        )
      }
    )
  }
}

/// Playback controls view with play/pause and time display
struct VideoControlsView: View {
  @ObservedObject var state: VideoEditorState
  @ObservedObject private var playbackState: VideoEditorPlaybackState
  private let stepIntervalSeconds: Double = 1.0
  @State private var leftSectionWidth: CGFloat = 0
  @State private var rightSectionWidth: CGFloat = 0
  @State private var containerWidth: CGFloat = 0

  init(state: VideoEditorState) {
    _state = ObservedObject(wrappedValue: state)
    _playbackState = ObservedObject(wrappedValue: state.playbackState)
  }

  var body: some View {
    HStack(spacing: controlsLayout.outerSpacing) {
      leftActions
        .fixedSize(horizontal: true, vertical: false)
        .measureVideoControlsWidth(for: .left)
        .frame(width: reservedSideWidth, alignment: .leading)

      centerTransport
        .frame(maxWidth: .infinity, alignment: .center)

      rightActions
        .fixedSize(horizontal: true, vertical: false)
        .measureVideoControlsWidth(for: .right)
        .frame(width: reservedSideWidth, alignment: .trailing)
    }
    .padding(.vertical, controlsLayout.verticalPadding)
    .frame(maxWidth: .infinity)
    .background(
      GeometryReader { proxy in
        Color.clear.preference(key: VideoControlsContainerWidthKey.self, value: proxy.size.width)
      }
    )
    .onPreferenceChange(VideoControlsSectionWidthKey.self) { widths in
      leftSectionWidth = widths[.left] ?? 0
      rightSectionWidth = widths[.right] ?? 0
    }
    .onPreferenceChange(VideoControlsContainerWidthKey.self) { width in
      containerWidth = width
    }
  }

  private var hasStatusMetadata: Bool {
    !state.zoomSegments.isEmpty || isAutoZoomActiveAtCurrentTime || state.hasUnsavedChanges
  }

  private var isAutoZoomActiveAtCurrentTime: Bool {
    state.activeZoomSegment(at: CMTimeGetSeconds(playbackState.currentTime))?.isAutoMode == true
  }

  private var reservedSideWidth: CGFloat {
    max(leftSectionWidth, rightSectionWidth)
  }

  private var controlsLayout: VideoControlsLayoutStyle {
    VideoControlsLayoutStyle.forWidth(containerWidth > 0 ? containerWidth : 920)
  }

  private var leftActions: some View {
    Color.clear
      .frame(width: 0, height: 1)
  }

  private var centerTransport: some View {
    HStack(spacing: controlsLayout.centerSpacing) {
      timeLabel(playbackState.formattedCurrentTime, alignment: .trailing)

      transportButton(systemName: "backward.fill") {
        state.stepTimeline(by: -stepIntervalSeconds)
      }

      playPauseButton

      transportButton(systemName: "forward.fill") {
        state.stepTimeline(by: stepIntervalSeconds)
      }

      timeLabel(state.formattedDuration, alignment: .leading)
    }
    // Transport siblings merge optically on macOS 26+ and sample once.
    .liquidGlassGroup(spacing: controlsLayout.centerSpacing)
  }

  @ViewBuilder
  private var rightActions: some View {
    if hasStatusMetadata {
      HStack(spacing: controlsLayout.metadataSpacing) {
        statusMetadata
      }
    } else {
      Color.clear
        .frame(width: 0, height: 1)
    }
  }

  /// The transport is the one always-lit surface in the editor, so it keeps its glass at rest
  /// rather than materialising on hover — it is the primary control of the window.
  private var playPauseButton: some View {
    Button(action: { state.togglePlayback() }) {
      Image(systemName: playbackState.isPlaying ? "pause.fill" : "play.fill")
        .font(.system(size: controlsLayout.playIconSize, weight: .bold))
        // Accent-tinted glass, so the glyph is resolved against the tint rather than the app
        // appearance — adaptive ink drew a black triangle on the blue transport in Light theme.
        .foregroundColor(LiquidGlassTokens.inkOnAccent)
        .frame(width: controlsLayout.playButtonSize, height: controlsLayout.playButtonSize)
        .liquidGlassChrome(
          shape: Circle(),
          isVisible: true,
          isActive: true,
          glassTint: .accentColor
        )
    }
    .buttonStyle(.plain)
    .keyboardShortcut(.space, modifiers: [])
  }

  private func transportButton(systemName: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: controlsLayout.transportIconSize, weight: .semibold))
        .foregroundColor(LiquidGlassTokens.inkBody)
        .frame(
          width: controlsLayout.transportButtonSize,
          height: controlsLayout.transportButtonSize
        )
        .liquidGlassControl(isActive: false, in: Circle())
    }
    .buttonStyle(.plain)
  }

  private func timeLabel(_ value: String, alignment: Alignment) -> some View {
    Text(value)
      .font(.system(size: controlsLayout.timeFontSize, weight: .semibold, design: .monospaced))
      .foregroundColor(.secondary)
      .frame(width: controlsLayout.timeLabelWidth, alignment: alignment)
  }

  @ViewBuilder
  private var statusMetadata: some View {
    if !state.zoomSegments.isEmpty {
      statusBadge(systemName: "plus.magnifyingglass", text: "\(state.zoomSegments.count)")
    }

    if isAutoZoomActiveAtCurrentTime {
      statusBadge(systemName: "camera.metering.center.weighted", text: L10n.VideoEditor.auto)
    }

    if state.hasUnsavedChanges {
      statusBadge(systemName: "scissors", text: state.formattedTrimmedDuration)
    }

    // Output length reflects per-segment speed scaling (timelapse).
    if state.hasSpeedSegments {
      statusBadge(systemName: "gauge.with.dots.needle.67percent", text: state.formattedOutputDuration)
    }
  }

  /// Uniform neutral stat chip for the controls bar — secondary glyph + primary value on one
  /// quiet glass capsule, matching the GIF info metadata badges. All metadata shares one
  /// treatment so the row reads as instrument readouts, not a set of colored alerts.
  private func statusBadge(systemName: String, text: String) -> some View {
    HStack(spacing: 5) {
      Image(systemName: systemName)
        .font(.system(size: controlsLayout.badgeIconSize, weight: .medium))
        .foregroundColor(.secondary)

      Text(text)
        .font(.system(size: controlsLayout.badgeFontSize, weight: .medium))
        .foregroundColor(.primary)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .monospacedDigit()
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .liquidGlassChrome(
      shape: Capsule(style: .continuous),
      isVisible: true,
      isActive: false
    )
  }
}
