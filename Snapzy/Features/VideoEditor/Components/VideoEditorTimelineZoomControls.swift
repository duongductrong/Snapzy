//
//  VideoEditorTimelineZoomControls.swift
//  Snapzy
//
//  Compact zoom in/out/fit cluster beside the playback status badges.
//

import SwiftUI

/// Zoom controls for the track timeline: zoom out, zoom level (tap to fit),
/// zoom in. Pinch and keyboard shortcuts mirror the same viewport state.
///
/// Sized to match the status badges in the controls bar so the row reads as
/// one set of instrument chips.
struct TimelineZoomControls: View {
  @ObservedObject var viewport: VideoEditorTimelineViewport
  /// Time the zoom anchors on (typically the playhead).
  let anchorTime: TimeInterval

  private let badgeIconSize: CGFloat = 11
  private let badgeFontSize: CGFloat = 11
  private let badgeContentHeight: CGFloat = 13

  private var zoomPercentText: String {
    if viewport.isFit {
      return L10n.VideoEditorTimeline.fit
    }
    return "\(Int((viewport.zoomLevel * 100).rounded()))%"
  }

  var body: some View {
    HStack(spacing: 2) {
      controlButton(systemName: "minus") {
        viewport.zoomOut(anchorTime: anchorTime)
      }
      .disabled(!viewport.canZoomOut)
      .help(L10n.VideoEditorTimeline.zoomOut)

      Button {
        viewport.fit()
      } label: {
        Text(zoomPercentText)
          .font(.system(size: badgeFontSize, weight: .medium).monospacedDigit())
          .foregroundColor(viewport.isFit ? .secondary : .primary)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
          .padding(.horizontal, 2)
          .frame(height: badgeContentHeight)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(L10n.VideoEditorTimeline.fit)

      controlButton(systemName: "plus") {
        viewport.zoomIn(anchorTime: anchorTime)
      }
      .disabled(!viewport.canZoomIn)
      .help(L10n.VideoEditorTimeline.zoomIn)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .liquidGlassChrome(
      shape: Capsule(style: .continuous),
      isVisible: true,
      isActive: false
    )
  }

  private func controlButton(systemName: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: badgeIconSize, weight: .medium))
        .foregroundColor(.secondary)
        .frame(width: badgeContentHeight, height: badgeContentHeight)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
