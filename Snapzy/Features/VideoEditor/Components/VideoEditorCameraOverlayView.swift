//
//  VideoEditorCameraOverlayView.swift
//  Snapzy
//
//  Preview of the Studio camera layer in the canvas-space host (never zoomed): an
//  AVPlayerLayer (hardware decode, no pixel copies) placed and masked from the same
//  `VideoEditorCameraSettings.rect` the export layer uses.
//

import AVFoundation
import SwiftUI

struct VideoEditorCameraOverlayView: View {
  @ObservedObject var state: VideoEditorState
  @ObservedObject private var playbackState: VideoEditorPlaybackState
  /// Video rect inside the canvas host, top-left coordinates.
  let videoRect: CGRect

  init(state: VideoEditorState, videoRect: CGRect) {
    _state = ObservedObject(wrappedValue: state)
    _playbackState = ObservedObject(wrappedValue: state.playbackState)
    self.videoRect = videoRect
  }

  var body: some View {
    if state.hasEditableCamera, let controller = state.cameraPreview,
       let source = state.recordingMetadata?.cameraSource {
      let settings = state.cameraSettings
      let sequenceTime = CMTimeGetSeconds(playbackState.currentTime)
      let sourceTime = state.cursorSourceTime(atSequence: sequenceTime)
      let visible = settings.isVisible && sourceTime.map { !source.isInGap($0) } == true
      let rect = settings.rect(in: videoRect, aspect: source.overlayAspect)
      VideoEditorCameraPlayerLayerView(
        player: controller.player,
        cornerRadius: settings.cornerRadius(for: rect, referencePointWidth: source.pointSize.width),
        isMirrored: settings.isMirrored
      )
      .frame(width: rect.width, height: rect.height)
      .offset(x: rect.minX, y: rect.minY)
      .opacity(visible ? 1 : 0)
      .animation(.easeInOut(duration: 0.2), value: visible)
      .onReceive(playbackState.$currentTime) { time in
        syncCamera(at: CMTimeGetSeconds(time))
      }
      .onReceive(playbackState.$isPlaying) { _ in
        syncCamera(at: CMTimeGetSeconds(playbackState.currentTime))
      }
      .onAppear { syncCamera(at: sequenceTime) }
    }
  }

  private func syncCamera(at sequenceTime: TimeInterval) {
    state.cameraPreview?.update(
      sourceTime: state.cursorSourceTime(atSequence: sequenceTime),
      isPlaying: playbackState.isPlaying,
      rate: state.previewSourceRate(atSequence: sequenceTime)
    )
  }
}

/// AVPlayerLayer host with corner masking and mirroring done by Core Animation.
private struct VideoEditorCameraPlayerLayerView: NSViewRepresentable {
  let player: AVPlayer
  let cornerRadius: CGFloat
  let isMirrored: Bool

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    view.wantsLayer = true
    let layer = AVPlayerLayer(player: player)
    layer.videoGravity = .resizeAspectFill
    view.layer = layer
    return view
  }

  func updateNSView(_ view: NSView, context: Context) {
    guard let layer = view.layer as? AVPlayerLayer else { return }
    if layer.player !== player { layer.player = player }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.cornerRadius = cornerRadius
    layer.masksToBounds = true
    layer.setAffineTransform(isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
    CATransaction.commit()
  }
}
