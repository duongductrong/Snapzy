//
//  VideoEditorCaptionOverlayView.swift
//  Snapzy
//
//  Live preview of the caption layer in the canvas-space host above the camera.
//  Renders the exact same CoreText bitmap, per-word/character stagger, baseline mask,
//  specular light sheen, and motion curves as GPU export.
//

import AVFoundation
import SwiftUI

struct VideoEditorCaptionOverlayView: View {
  @ObservedObject var state: VideoEditorState
  @ObservedObject private var playbackState: VideoEditorPlaybackState
  @ObservedObject private var fontManager = VideoEditorFontManager.shared
  let videoRect: CGRect
  @Environment(\.displayScale) private var displayScale
  @State private var cache = VideoEditorCaptionImageCache(capacity: 96)

  init(state: VideoEditorState, videoRect: CGRect) {
    _state = ObservedObject(wrappedValue: state)
    _playbackState = ObservedObject(wrappedValue: state.playbackState)
    self.videoRect = videoRect
  }

  var body: some View {
    if state.captions.settings.isEnabled, !state.captions.segments.isEmpty {
      let _ = fontManager.revision
      let seqTime = CMTimeGetSeconds(playbackState.currentTime)
      if let resolved = state.captionSegmentWithSourceTime(atSequence: seqTime) {
        let settings = state.captions.settings
        let elapsed = max(0, resolved.sourceTime - resolved.segment.start)
        let motion: VideoEditorCaptionMotionState = (!playbackState.isPlaying && elapsed < 0.025)
          ? .identity
          : VideoEditorCaptionMotion.evaluate(
            atSource: resolved.sourceTime,
            in: resolved.segment,
            settings: settings
          )

        if motion.opacity > 0.002,
           motion.wipeProgress > 0.002,
           motion.verticalRevealProgress > 0.002,
           let entry = cache.entry(
             text: resolved.segment.text,
             segment: resolved.segment,
             sourceTime: resolved.sourceTime,
             settings: settings,
             videoSize: videoRect.size,
             subwordKind: motion.subwordKind,
             subwordProgress: motion.subwordProgress,
             scale: max(displayScale, 1)
           ) {
          let bmpFrame = entry.layout.bitmapFrame(in: videoRect, settings: settings)
          let dx = motion.offsetXFraction * videoRect.height
          let dy = motion.offsetYFraction * videoRect.height
          let blurPt = motion.blurRadiusFraction * videoRect.height

          captionGraphic(entry: entry, size: bmpFrame.size, shimmerProgress: motion.shimmerProgress)
            .mask(alignment: .topLeading) {
              Rectangle()
                .frame(
                  width: bmpFrame.width * motion.wipeProgress,
                  height: bmpFrame.height * motion.verticalRevealProgress
                )
            }
            .scaleEffect(x: motion.scale * motion.scaleX, y: motion.scale * motion.scaleY)
            .blur(radius: blurPt)
            .opacity(motion.opacity)
            .position(x: bmpFrame.midX + dx, y: bmpFrame.midY + dy)
            .allowsHitTesting(false)
            .accessibilityLabel(resolved.segment.text)
        }
      }
    }
  }

  @ViewBuilder
  private func captionGraphic(
    entry: VideoEditorCaptionImageCache.Entry,
    size: CGSize,
    shimmerProgress: CGFloat?
  ) -> some View {
    let scale = max(displayScale, 1)
    let baseImage = Image(decorative: entry.image, scale: scale)
      .resizable()
      .interpolation(.high)
      .frame(width: size.width, height: size.height)

    if let s = shimmerProgress {
      let bandW = max(24, size.width * 0.36)
      let sweepX = -size.width * 0.65 + (size.width * 1.30 + bandW) * s
      baseImage
        .overlay {
          LinearGradient(
            stops: [
              .init(color: .white.opacity(0), location: 0.0),
              .init(color: .white.opacity(0.66), location: 0.5),
              .init(color: .white.opacity(0), location: 1.0),
            ],
            startPoint: .leading,
            endPoint: .trailing
          )
          .frame(width: bandW, height: size.height * 1.8)
          .rotationEffect(.degrees(18))
          .offset(x: sweepX)
          .blendMode(.plusLighter)
          .mask(baseImage)
        }
    } else {
      baseImage
    }
  }
}
