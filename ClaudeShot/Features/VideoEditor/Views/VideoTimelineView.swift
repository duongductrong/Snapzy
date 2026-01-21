//
//  VideoTimelineView.swift
//  ClaudeShot
//
//  Timeline container with frame strip, playhead, and trim handles
//

import AVFoundation
import SwiftUI

/// Timeline view with frame previews, playhead indicator, and trim handles
struct VideoTimelineView: View {
  @ObservedObject var state: VideoEditorState

  var body: some View {
    GeometryReader { geometry in
      let timelineWidth = geometry.size.width

      ZStack(alignment: .leading) {
        // Frame thumbnail strip
        VideoTimelineFrameStrip(
          thumbnails: state.frameThumbnails,
          isLoading: state.isExtractingFrames
        )

        // Trim handles overlay
        VideoTrimHandlesView(state: state, timelineWidth: timelineWidth)

        // Playhead indicator
        Rectangle()
          .fill(Color.red)
          .frame(width: 2, height: 64)
          .offset(x: playheadOffset(in: timelineWidth) - 1)
          .allowsHitTesting(false)
      }
      .contentShape(Rectangle())
      .gesture(scrubGesture(timelineWidth: timelineWidth))
    }
    .frame(height: 64)
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
