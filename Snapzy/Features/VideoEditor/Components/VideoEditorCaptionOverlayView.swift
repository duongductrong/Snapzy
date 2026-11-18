//
//  VideoEditorCaptionOverlayView.swift
//  Snapzy
//
//  Preview of the caption layer, in the canvas-space host above the camera. Draws the
//  same CoreText bitmap the export burns in (rendered at screen scale), so line breaks
//  and the box match the exported video.
//

import AVFoundation
import SwiftUI

struct VideoEditorCaptionOverlayView: View {
  @ObservedObject var state: VideoEditorState
  @ObservedObject private var playbackState: VideoEditorPlaybackState
  /// Where the video sits inside the canvas host, top-left coordinates.
  let videoRect: CGRect
  @Environment(\.displayScale) private var displayScale
  @State private var cache = VideoEditorCaptionImageCache(capacity: 4)

  init(state: VideoEditorState, videoRect: CGRect) {
    _state = ObservedObject(wrappedValue: state)
    _playbackState = ObservedObject(wrappedValue: state.playbackState)
    self.videoRect = videoRect
  }

  var body: some View {
    let time = CMTimeGetSeconds(playbackState.currentTime)
    if let segment = state.captionSegment(atSequence: time),
       let entry = cache.entry(
         text: segment.text,
         settings: state.captions.settings,
         videoSize: videoRect.size,
         scale: max(displayScale, 1)
       ) {
      let frame = entry.layout.frame(in: videoRect, settings: state.captions.settings)
      Image(decorative: entry.image, scale: max(displayScale, 1))
        .resizable()
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }
  }
}
