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
    state.isZoomTrackVisible ? frameStripHeight + spacing + zoomTrackHeight : frameStripHeight
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
          Rectangle()
            .fill(Color.red)
            .frame(width: 2, height: totalHeight)
            .offset(x: playheadOffset(in: timelineWidth) - 1)
            .allowsHitTesting(false)
        }
        .frame(height: frameStripHeight)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .gesture(scrubGesture(timelineWidth: timelineWidth))

        // Zoom timeline track
        if state.isZoomTrackVisible {
          ZoomTimelineTrack(state: state, timelineWidth: timelineWidth)
        }
      }
    }
    .frame(height: totalHeight)
    .background(Color.black.opacity(0.2))
    .cornerRadius(6)
  }

  // MARK: - Playhead Position

  private func playheadOffset(in width: CGFloat) -> CGFloat {
    guard CMTimeGetSeconds(state.duration) > 0 else { return 0 }
    let progress = CMTimeGetSeconds(state.currentTime) / CMTimeGetSeconds(state.duration)
    return CGFloat(progress) * width
  }

  // MARK: - Scrub Gesture

  private func scrubGesture(timelineWidth: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        if !state.isScrubbing {
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
