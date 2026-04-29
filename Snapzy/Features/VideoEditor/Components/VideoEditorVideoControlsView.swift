//
//  VideoControlsView.swift
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

  var badgeHorizontalPadding: CGFloat {
    switch self {
    case .compact: 5
    case .regular: 6
    case .expanded: 7
    }
  }

  var badgeVerticalPadding: CGFloat {
    switch self {
    case .compact: 2
    case .regular, .expanded: 3
    }
  }

  var trimFontSize: CGFloat {
    switch self {
    case .compact: 11
    case .regular, .expanded: 12
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

  private var playPauseButton: some View {
    Button(action: { state.togglePlayback() }) {
      Image(systemName: playbackState.isPlaying ? "pause.fill" : "play.fill")
        .font(.system(size: controlsLayout.playIconSize, weight: .bold))
        .foregroundColor(.black.opacity(0.9))
        .frame(width: controlsLayout.playButtonSize, height: controlsLayout.playButtonSize)
        .background(Color.white)
        .clipShape(Circle())
    }
    .buttonStyle(.plain)
    .keyboardShortcut(.space, modifiers: [])
  }

  private func transportButton(systemName: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: controlsLayout.transportIconSize, weight: .semibold))
        .foregroundColor(.secondary)
        .frame(
          width: controlsLayout.transportButtonSize,
          height: controlsLayout.transportButtonSize
        )
        .contentShape(Rectangle())
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
      HStack(spacing: 4) {
        Image(systemName: "plus.magnifyingglass")
          .font(.system(size: controlsLayout.badgeIconSize))
          .foregroundColor(ZoomColors.primary)

        Text("\(state.zoomSegments.count)")
          .font(.system(size: controlsLayout.badgeFontSize, weight: .medium))
          .foregroundColor(ZoomColors.primary)
      }
      .padding(.horizontal, controlsLayout.badgeHorizontalPadding)
      .padding(.vertical, controlsLayout.badgeVerticalPadding)
      .background(ZoomColors.primary.opacity(0.15))
      .cornerRadius(4)
    }

    if isAutoZoomActiveAtCurrentTime {
      HStack(spacing: 4) {
        Image(systemName: "camera.metering.center.weighted")
          .font(.system(size: controlsLayout.badgeIconSize))
          .foregroundColor(.green)

        Text(L10n.VideoEditor.auto)
          .font(.system(size: controlsLayout.badgeFontSize, weight: .medium))
          .foregroundColor(.green)
      }
      .padding(.horizontal, controlsLayout.badgeHorizontalPadding)
      .padding(.vertical, controlsLayout.badgeVerticalPadding)
      .background(Color.green.opacity(0.12))
      .cornerRadius(4)
    }

    if state.hasUnsavedChanges {
      HStack(spacing: 4) {
        Image(systemName: "scissors")
          .font(.system(size: controlsLayout.trimFontSize))
          .foregroundColor(.yellow)

        Text(state.formattedTrimmedDuration)
          .font(.system(size: controlsLayout.trimFontSize, design: .monospaced))
          .foregroundColor(.yellow)
      }
    }
  }
}
