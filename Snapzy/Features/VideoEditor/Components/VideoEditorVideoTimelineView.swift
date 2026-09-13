//
//  VideoEditorVideoTimelineView.swift
//  Snapzy
//
//  Timeline container with time ruler, frame strip, playhead, trim handles, and zoom/speed tracks
//

import AVFoundation
import SwiftUI

/// Timeline view with time ruler, frame previews, playhead indicator, trim handles, and zoom/speed tracks
struct VideoTimelineView: View {
  @ObservedObject var state: VideoEditorState

  private let frameStripHeight: CGFloat = 64
  private let segmentTrackHeight: CGFloat = 40
  private let spacing: CGFloat = 6

  private var totalHeight: CGFloat {
    var height = TimelineRulerView.height + spacing + frameStripHeight
    if state.isZoomTrackVisible { height += spacing + segmentTrackHeight }
    if state.isSpeedTrackVisible, !state.isGIF { height += spacing + segmentTrackHeight }
    return height
  }

  var body: some View {
    GeometryReader { geometry in
      let timelineWidth = geometry.size.width

      ZStack(alignment: .topLeading) {
        VStack(spacing: spacing) {
          // Time ruler — measuring-tape ticks and labels along the container's top edge
          TimelineRulerView(duration: state.duration, timelineWidth: timelineWidth)
            .contentShape(Rectangle())
            .gesture(scrubGesture(timelineWidth: timelineWidth))

          // Frame strip with trim handles
          ZStack(alignment: .leading) {
            // Frame thumbnail strip
            VideoTimelineFrameStrip(
              thumbnails: state.frameThumbnails,
              isLoading: state.isExtractingFrames
            )

            // Trim handles overlay
            VideoTrimHandlesView(state: state, timelineWidth: timelineWidth, trackHeight: frameStripHeight)
          }
          .frame(height: frameStripHeight)
          .clipShape(Radius.rect(Radius.tile))
          .contentShape(Rectangle())
          .gesture(scrubGesture(timelineWidth: timelineWidth))

          // Zoom timeline track
          if state.isZoomTrackVisible {
            ZoomTimelineTrack(state: state, timelineWidth: timelineWidth)
          }

          // Speed (timelapse) timeline track — video only; GIF export does not apply timeline edits.
          if state.isSpeedTrackVisible, !state.isGIF {
            SpeedTimelineTrack(state: state, timelineWidth: timelineWidth)
          }
        }

        // Playhead indicator (drawn last so it spans the ruler and every track)
        TimelinePlayheadView(
          playbackState: state.playbackState,
          duration: state.duration,
          timelineWidth: timelineWidth,
          totalHeight: totalHeight
        )
      }
    }
    .frame(height: totalHeight)
  }

  // MARK: - Scrub Gesture

  private func scrubGesture(timelineWidth: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        if !state.playbackState.isScrubbing {
          state.startScrubbing()
        }
        let progress = max(0, min(value.location.x / timelineWidth, 1))
        let newTime = CMTime(
          seconds: progress * CMTimeGetSeconds(state.duration),
          preferredTimescale: 600
        )
        state.scrub(to: newTime)
      }
      .onEnded { _ in
        state.endScrubbing()
      }
  }
}

private struct TimelinePlayheadView: View {
  @ObservedObject var playbackState: VideoEditorPlaybackState
  let duration: CMTime
  let timelineWidth: CGFloat
  let totalHeight: CGFloat

  /// Arrow cap seated in the ruler lane at the top of the playhead line,
  /// Screen-Studio style. The line hangs from the cap's apex.
  private static let arrowWidth: CGFloat = 11
  private static let arrowHeight: CGFloat = 7

  var body: some View {
    VStack(spacing: 0) {
      PlayheadArrowCap()
        .fill(Color.red)
        .frame(width: Self.arrowWidth, height: Self.arrowHeight)

      Rectangle()
        .fill(Color.red)
        .frame(width: 2, height: max(0, totalHeight - Self.arrowHeight))
    }
    .shadow(color: Color.black.opacity(0.30), radius: 1.5, y: 0.5)
    .offset(x: playheadOffset - Self.arrowWidth / 2)
    .allowsHitTesting(false)
  }

  private var playheadOffset: CGFloat {
    let durationSeconds = CMTimeGetSeconds(duration)
    guard durationSeconds > 0 else { return 0 }
    let progress = CMTimeGetSeconds(playbackState.currentTime) / durationSeconds
    return CGFloat(progress) * timelineWidth
  }
}

/// Downward-pointing triangle cap drawn above the playhead line; its apex
/// aligns with the tick the playhead sits on.
private struct PlayheadArrowCap: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}
