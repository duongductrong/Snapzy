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
  @ObservedObject private var viewport: VideoEditorTimelineViewport
  @ObservedObject private var playbackState: VideoEditorPlaybackState

  private let frameStripHeight: CGFloat = 64
  private let segmentTrackHeight: CGFloat = 40
  private let spacing: CGFloat = 6

  /// Gap kept between the playhead and the viewport edge when auto-following.
  private static let playheadFollowMargin: CGFloat = 24

  init(state: VideoEditorState) {
    _state = ObservedObject(wrappedValue: state)
    _viewport = ObservedObject(wrappedValue: state.timelineViewport)
    _playbackState = ObservedObject(wrappedValue: state.playbackState)
  }

  private var totalHeight: CGFloat {
    var height = TimelineRulerView.height + spacing + frameStripHeight
    if state.isZoomTrackVisible { height += spacing + segmentTrackHeight }
    if state.isSpeedTrackVisible, !state.isGIF { height += spacing + segmentTrackHeight }
    return height
  }

  /// Playhead position in content coordinates.
  private var playheadContentX: CGFloat {
    viewport.x(for: CMTimeGetSeconds(playbackState.currentTime))
  }

  var body: some View {
    GeometryReader { geometry in
      let viewportWidth = geometry.size.width

      timelineContent
        .frame(width: viewport.contentWidth, alignment: .leading)
        .overlay(alignment: .topLeading) {
          TimelinePlayheadView(
            playbackState: playbackState,
            duration: state.duration,
            timelineWidth: viewport.contentWidth,
            totalHeight: totalHeight
          )
        }
        .offset(x: -viewport.scrollOffset)
        .frame(width: viewportWidth, alignment: .topLeading)
        .clipped()
        .background(TimelineScrollCatcher(viewport: viewport))
        .simultaneousGesture(magnificationGesture)
        .onAppear {
          syncViewport(width: viewportWidth)
        }
        .onChange(of: viewportWidth) { newWidth in
          syncViewport(width: newWidth)
        }
        .onChange(of: state.duration) { _ in
          viewport.durationSeconds = max(0, CMTimeGetSeconds(state.duration))
          viewport.clampScroll()
        }
        .onChange(of: playheadContentX) { newX in
          followPlayheadIfNeeded(newX)
        }
    }
    .frame(height: totalHeight)
  }

  // MARK: - Content

  private var timelineContent: some View {
    let contentWidth = viewport.contentWidth

    return VStack(spacing: spacing) {
      // Time ruler — measuring-tape ticks and labels along the container's top edge
      TimelineRulerView(duration: state.duration, timelineWidth: contentWidth)
        .contentShape(Rectangle())
        .gesture(scrubGesture(timelineWidth: contentWidth))

      // Frame strip with trim handles
      ZStack(alignment: .leading) {
        // Frame thumbnail strip
        VideoTimelineFrameStrip(
          thumbnails: state.frameThumbnails,
          isLoading: state.isExtractingFrames
        )

        // Trim handles overlay
        VideoTrimHandlesView(state: state, timelineWidth: contentWidth, trackHeight: frameStripHeight)
      }
      .frame(height: frameStripHeight)
      .clipShape(Radius.rect(Radius.tile))
      .contentShape(Rectangle())
      .gesture(scrubGesture(timelineWidth: contentWidth))

      // Zoom timeline track
      if state.isZoomTrackVisible {
        ZoomTimelineTrack(state: state, timelineWidth: contentWidth)
      }

      // Speed (timelapse) timeline track — video only; GIF export does not apply timeline edits.
      if state.isSpeedTrackVisible, !state.isGIF {
        SpeedTimelineTrack(state: state, timelineWidth: contentWidth)
      }
    }
  }

  // MARK: - Viewport Sync

  private func syncViewport(width: CGFloat) {
    viewport.viewportWidth = width
    viewport.durationSeconds = max(0, CMTimeGetSeconds(state.duration))
    viewport.clampScroll()
  }

  // MARK: - Playhead Follow

  private func followPlayheadIfNeeded(_ contentX: CGFloat) {
    guard playbackState.isPlaying, !playbackState.isScrubbing else { return }
    guard let target = viewport.targetScrollToKeepVisible(
      contentX: contentX,
      margin: Self.playheadFollowMargin
    ) else { return }
    viewport.scrollOffset = target
  }

  // MARK: - Pinch Zoom

  /// Pinch zooms around the playhead so the moment being edited stays put.
  private var magnificationGesture: some Gesture {
    MagnificationGesture()
      .onChanged { value in
        if pinchBaselineZoom == nil {
          pinchBaselineZoom = viewport.zoomLevel
          pinchAnchorTime = CMTimeGetSeconds(playbackState.currentTime)
        }
        guard let baseline = pinchBaselineZoom else { return }
        viewport.setZoom(
          baseline * value,
          keepingTimeAtViewportX: pinchAnchorTime ?? 0,
          anchorViewportX: anchorViewportX(for: pinchAnchorTime ?? 0)
        )
      }
      .onEnded { _ in
        pinchBaselineZoom = nil
        pinchAnchorTime = nil
      }
  }

  @State private var pinchBaselineZoom: CGFloat?
  @State private var pinchAnchorTime: TimeInterval?

  private func anchorViewportX(for time: TimeInterval) -> CGFloat {
    let x = viewport.x(for: time) - viewport.scrollOffset
    return max(0, min(x, max(0, viewport.viewportWidth)))
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
