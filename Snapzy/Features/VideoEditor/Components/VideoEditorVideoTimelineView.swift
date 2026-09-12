//
//  VideoTimelineView.swift
//  Snapzy
//
//  Timeline container with frame strip, playhead, trim handles, and zoom track
//

import AVFoundation
import SwiftUI

/// Timeline view with frame previews, playhead indicator, trim handles, and zoom track
struct VideoTimelineView: View {
  @ObservedObject var state: VideoEditorState

  private let frameStripHeight: CGFloat = 64
  private let zoomTrackHeight: CGFloat = 32
  private let spacing: CGFloat = 6

  private var totalHeight: CGFloat {
    var height = frameStripHeight
    if state.isZoomTrackVisible { height += spacing + zoomTrackHeight }
    if state.isSpeedTrackVisible && !state.isGIF { height += spacing + zoomTrackHeight }
    return height
  }

  var body: some View {
    GeometryReader { geometry in
      let timelineWidth = geometry.size.width

      VStack(spacing: spacing) {
        // Frame strip with trim handles and playhead
        ZStack(alignment: .leading) {
          // Frame thumbnail strip
          VideoTimelineFrameStrip(
            thumbnails: state.frameThumbnails,
            isLoading: state.isExtractingFrames
          )

          // Trim handles overlay
          VideoTrimHandlesView(state: state, timelineWidth: timelineWidth)

          // Playhead indicator (extends across both tracks)
          TimelinePlayheadView(
            playbackState: state.playbackState,
            duration: state.duration,
            timelineWidth: timelineWidth,
            totalHeight: totalHeight
          )
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
        if state.isSpeedTrackVisible && !state.isGIF {
          SpeedTimelineTrack(state: state, timelineWidth: timelineWidth)
        }
      }
    }
    .frame(height: totalHeight)
    .background(Color.black.opacity(0.2))
    .cornerRadius(Radius.tile)
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

  var body: some View {
    Rectangle()
      .fill(Color.red)
      .frame(width: 2, height: totalHeight)
      .offset(x: playheadOffset - 1)
      .allowsHitTesting(false)
  }

  private var playheadOffset: CGFloat {
    let durationSeconds = CMTimeGetSeconds(duration)
    guard durationSeconds > 0 else { return 0 }
    let progress = CMTimeGetSeconds(playbackState.currentTime) / durationSeconds
    return CGFloat(progress) * timelineWidth
  }
}
