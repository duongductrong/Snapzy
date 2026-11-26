//
//  VideoEditorVideoTimelineView.swift
//  Snapzy
//
//  Timeline container with time ruler, clip strip, playhead, and zoom/speed tracks
//

import AVFoundation
import Combine
import SwiftUI

/// Timeline view with time ruler, the clip sequence strip, playhead, and zoom/speed tracks
struct VideoTimelineView: View {
  let state: VideoEditorState
  @StateObject private var observation: VideoEditorTimelineObservation
  @ObservedObject private var viewport: VideoEditorTimelineViewport
  private let playbackState: VideoEditorPlaybackState

  private let frameStripHeight: CGFloat = 64
  private let segmentTrackHeight: CGFloat = 40
  private let spacing: CGFloat = 6

  /// Gap kept between the playhead and the viewport edge when auto-following.
  private static let playheadFollowMargin: CGFloat = 24

  init(state: VideoEditorState) {
    self.state = state
    _observation = StateObject(wrappedValue: VideoEditorTimelineObservation(state: state, surface: .container))
    _viewport = ObservedObject(wrappedValue: state.timelineViewport)
    self.playbackState = state.playbackState
  }

  private var totalHeight: CGFloat {
    var height = TimelineRulerView.height + spacing + frameStripHeight
    if showsTextTrack {
      height += spacing + TextTimelineLaneLayout.totalHeight(forLaneCount: state.textLaneCount)
    }
    if showsAudioTrack {
      height += spacing + VideoEditorAudioTimelineTrack.totalHeight(forLaneCount: state.audioLaneCount)
    }
    if state.isZoomTrackVisible { height += spacing + segmentTrackHeight }
    if state.isSpeedTrackVisible, !state.isGIF { height += spacing + segmentTrackHeight }
    if state.showsCameraTrack { height += spacing + segmentTrackHeight }
    if showsCaptionTrack { height += spacing + segmentTrackHeight }
    return height
  }

  var body: some View {
    let _ = observation.revision
    let _ = bookmarkRevision
    return GeometryReader { geometry in
      let viewportWidth = geometry.size.width

      timelineContent
        .frame(width: viewport.contentWidth, alignment: .leading)
        .overlay(alignment: .topLeading) {
          TimelineSkimmerOverlay(
            skimmerX: skimmerContentX,
            duration: state.timelineDuration,
            timelineWidth: viewport.contentWidth,
            totalHeight: totalHeight
          )
        }
        .overlay(alignment: .topLeading) {
          VideoEditorTimelineSnapGuideView(
            snapGuide: state.timelineSnapGuide,
            duration: state.timelineDuration,
            timelineWidth: viewport.contentWidth,
            totalHeight: totalHeight
          )
        }
        .overlay(alignment: .topLeading) {
          TimelinePlayheadView(
            playbackState: playbackState,
            duration: state.timelineDuration,
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
          syncViewportDuration()
        }
        .onChange(of: state.clips) { _ in
          syncViewportDuration()
        }
        .onReceive(state.$audioClips.receive(on: DispatchQueue.main)) { _ in
          syncViewportDuration()
        }
        .onReceive(state.$timelineBookmarks) { _ in
          bookmarkRevision &+= 1
        }
        .onReceive(playbackState.$currentTime) { time in
          followPlayheadIfNeeded(viewport.x(for: CMTimeGetSeconds(time)))
        }
    }
    .frame(height: totalHeight)
  }

  // MARK: - Content

  private var timelineContent: some View {
    let contentWidth = viewport.contentWidth

    return VStack(spacing: spacing) {
      // Time ruler — measuring-tape ticks, labels, skimmer hover, and bookmark markers
      ZStack(alignment: .topLeading) {
        TimelineRulerView(duration: state.timelineDuration, timelineWidth: contentWidth, visibleRange: renderRange)
          .contentShape(Rectangle())
          .onContinuousHover { phase in
            switch phase {
            case .active(let location):
              skimmerContentX = max(0, min(contentWidth, location.x))
            case .ended:
              skimmerContentX = nil
            }
          }
          .gesture(scrubGesture(timelineWidth: contentWidth))

        ForEach(state.timelineBookmarks, id: \.self) { markerTime in
          let axisSeconds = max(0.0001, CMTimeGetSeconds(state.timelineDuration))
          let markerX = CGFloat(min(1, max(0, markerTime / axisSeconds))) * contentWidth
          Image(systemName: "bookmark.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.orange)
            .shadow(color: .black.opacity(0.45), radius: 1.5, y: 0.5)
            .offset(x: markerX - 4, y: 2)
            .onTapGesture {
              state.seek(to: CMTime(seconds: markerTime, preferredTimescale: 600))
            }
            .contextMenu {
              Button(role: .destructive) {
                state.removeBookmark(at: markerTime)
              } label: {
                Label(L10n.VideoEditor.removeBookmark, systemImage: "trash")
              }
            }
            .help(L10n.VideoEditor.jumpToBookmarkHint)
        }
      }

      // Text / Title overlay track — sits directly above video like a pro NLE layer.
      if showsTextTrack {
        VideoEditorTextTimelineTrack(
          state: state,
          timelineWidth: contentWidth,
          visibleRange: renderRange
        )
        .equatable()
      }

      // Clip sequence: one block per clip, selectable, draggable, trimmable.
      //
      // The blocks own the pointer: a drag reorders once the sequence has
      // multiple clips, and scrubs the playhead while it is still a single
      // clip. A plain click inside a block selects and moves the playhead, and
      // the ruler above remains the always-available scrub surface.
      if state.isGIF {
        VideoTimelineFrameStrip(
          thumbnails: state.frameThumbnails,
          isLoading: state.isExtractingFrames
        )
        .frame(height: frameStripHeight)
        .contentShape(Rectangle())
        .gesture(scrubGesture(timelineWidth: contentWidth))
      } else {
        VideoEditorClipStripView(
          state: state,
          thumbnailCache: state.clipThumbnailCache,
          timelineWidth: contentWidth,
          trackHeight: frameStripHeight,
          visibleRange: renderRange,
          stickyLeadingX: viewport.scrollOffset
        )
        .equatable()
        .frame(height: frameStripHeight)
      }

      // Multi-Track Audio waveform lanes — shown for videos.
      if showsAudioTrack {
        VideoEditorAudioTimelineTrack(
          state: state,
          waveformCache: state.audioWaveformCache,
          timelineWidth: contentWidth,
          visibleRange: renderRange,
          stickyLeadingX: viewport.scrollOffset
        )
        .equatable()
      }

      // Zoom timeline track
      if state.isZoomTrackVisible {
        ZoomTimelineTrack(state: state, timelineWidth: contentWidth, visibleRange: renderRange).equatable()
      }

      // Speed (timelapse) timeline track — video only; GIF export does not apply timeline edits.
      if state.isSpeedTrackVisible, !state.isGIF {
        SpeedTimelineTrack(state: state, timelineWidth: contentWidth, visibleRange: renderRange).equatable()
      }

      // Camera track (hidden stretches) — Studio recordings with a camera sidecar.
      if state.showsCameraTrack {
        VideoEditorCameraTimelineTrack(state: state, timelineWidth: contentWidth).equatable()
      }

      // Captions track — shown once the video has captions.
      if showsCaptionTrack {
        VideoEditorCaptionTimelineTrack(state: state, timelineWidth: contentWidth, visibleRange: renderRange)
          .equatable()
      }
    }
  }

  private var showsTextTrack: Bool {
    !state.isGIF && !state.textOverlays.isEmpty
  }

  private var showsAudioTrack: Bool {
    !state.isGIF
  }

  private var showsCaptionTrack: Bool {
    !state.isGIF && !state.captions.isEmpty
  }

  /// One viewport of overscan on either side, snapped to whole viewports (see
  /// `VideoEditorTimelineViewport.renderRange`).
  private var renderRange: ClosedRange<CGFloat> {
    viewport.renderRange
  }

  // MARK: - Viewport Sync

  private func syncViewport(width: CGFloat) {
    viewport.setGeometry(
      viewportWidth: width,
      durationSeconds: max(0, CMTimeGetSeconds(state.timelineDuration))
    )
  }

  private func syncViewportDuration() {
    syncViewport(width: viewport.viewportWidth)
  }

  // MARK: - Playhead Follow

  private func followPlayheadIfNeeded(_ contentX: CGFloat) {
    guard playbackState.isPlaying, !playbackState.isScrubbing else { return }
    guard let target = viewport.targetScrollToKeepVisible(
      contentX: contentX,
      margin: Self.playheadFollowMargin
    ) else { return }
    viewport.setScrollOffset(target)
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
  @State private var bookmarkRevision: UInt64 = 0
  @State private var skimmerContentX: CGFloat?

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
        let axisSeconds = max(0.0001, CMTimeGetSeconds(state.timelineDuration))
        let progress = max(0, min(value.location.x / timelineWidth, 1))
        let newTime = CMTime(
          seconds: progress * axisSeconds,
          preferredTimescale: 600
        )
        state.scrub(to: newTime)
      }
      .onEnded { _ in
        state.endScrubbing()
      }
  }
}

/// Final Cut Pro style hover skimmer line + floating timecode pill on the ruler.
private struct TimelineSkimmerOverlay: View {
  let skimmerX: CGFloat?
  let duration: CMTime
  let timelineWidth: CGFloat
  let totalHeight: CGFloat

  var body: some View {
    if let x = skimmerX, timelineWidth > 0 {
      let durationSeconds = max(0, CMTimeGetSeconds(duration))
      let hoveredSeconds = max(0, min(durationSeconds, Double(x / timelineWidth) * durationSeconds))
      ZStack(alignment: .topLeading) {
        Rectangle()
          .fill(Color.primary.opacity(0.32))
          .frame(width: 1, height: totalHeight)
          .offset(x: x)

        Text(Self.formatTimecode(hoveredSeconds))
          .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
          .lineLimit(1)
          .foregroundColor(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(
            Capsule(style: .continuous)
              .fill(Color.black.opacity(0.78))
          )
          .overlay(
            Capsule(style: .continuous)
              .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
          )
          .offset(x: min(max(4, x - 24), max(4, timelineWidth - 56)), y: 2)
      }
      .allowsHitTesting(false)
    }
  }

  private static func formatTimecode(_ seconds: TimeInterval) -> String {
    let tenths = Int((max(0, seconds) * 10).rounded())
    let mins = tenths / 600
    let secs = (tenths % 600) / 10
    let dec = tenths % 10
    return String(format: "%02d:%02d.%d", mins, secs, dec)
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
