//
//  VideoEditorCameraOverlayView.swift
//  Snapzy
//
//  Preview of the Studio camera layer in the canvas-space host (never zoomed): an
//  AVPlayerLayer (hardware decode, no pixel copies) placed and masked from the same
//  `VideoEditorCameraSettings.rect` the export layer uses. Drag it to move it; it snaps
//  to the nine anchors within 32 pt, like the recording overlay. Hidden ranges fade it.
//

import AVFoundation
import SwiftUI

struct VideoEditorCameraOverlayView: View {
  @ObservedObject var state: VideoEditorState
  @ObservedObject private var playbackState: VideoEditorPlaybackState
  /// Video rect inside the canvas host, top-left coordinates.
  let videoRect: CGRect
  /// Settings when the drag began; non-nil while dragging.
  @State private var dragStart: VideoEditorCameraSettings?
  @State private var isHandCursorPushed = false

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
      let opacity = settings.isVisible && sourceTime.map { !source.isInGap($0) } == true
        ? sourceTime.map { settings.visibility(atSource: $0) } ?? 0
        : 0
      let rect = settings.rect(in: videoRect, aspect: source.overlayAspect)
      VideoEditorCameraPlayerLayerView(
        player: controller.player,
        cornerRadius: settings.cornerRadius(for: rect, referencePointWidth: source.pointSize.width),
        isMirrored: settings.isMirrored
      )
      .frame(width: rect.width, height: rect.height)
      .contentShape(Rectangle())
      .gesture(dragGesture(cameraSize: rect.size))
      .onHover { setHandCursor($0) }
      .allowsHitTesting(opacity > 0)
      .offset(x: rect.minX, y: rect.minY)
      .opacity(opacity)
      .animation(.easeInOut(duration: 0.2), value: opacity == 0)
      .onReceive(playbackState.$currentTime) { time in
        syncCamera(at: CMTimeGetSeconds(time))
      }
      .onReceive(playbackState.$isPlaying) { _ in
        syncCamera(at: CMTimeGetSeconds(playbackState.currentTime))
      }
      .onAppear { syncCamera(at: sequenceTime) }
      .onDisappear { setHandCursor(false) }
    }
  }

  private func dragGesture(cameraSize: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 2)
      .onChanged { value in
        let start = dragStart ?? state.cameraSettings
        if dragStart == nil { dragStart = start }
        var settings = state.cameraSettings
        settings.center = VideoEditorCameraSettings.draggedCenter(
          from: start.center,
          translation: value.translation,
          videoSize: videoRect.size,
          cameraSize: cameraSize,
          threshold: RecordingCameraOverlayPlacement.snapThreshold
        )
        state.setCameraSettings(settings, recordUndo: false)
      }
      .onEnded { _ in
        if let start = dragStart { state.commitCameraSettings(from: start) }
        dragStart = nil
      }
  }

  private func setHandCursor(_ inside: Bool) {
    guard inside != isHandCursorPushed else { return }
    isHandCursorPushed = inside
    if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
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

  func makeNSView(context: Context) -> VideoEditorCameraPlayerHostView {
    VideoEditorCameraPlayerHostView(player: player)
  }

  func updateNSView(_ view: VideoEditorCameraPlayerHostView, context: Context) {
    view.update(player: player, cornerRadius: cornerRadius, isMirrored: isMirrored)
  }
}

/// Keeps the AVPlayerLayer as a sublayer anchored at its center. AppKit pins a
/// layer-backed view's own layer to anchorPoint (0, 0), so flipping that layer would
/// mirror it around the left edge and shift the camera by its width; flipping a
/// centered sublayer mirrors the picture in place.
private final class VideoEditorCameraPlayerHostView: NSView {
  private let playerLayer = AVPlayerLayer()
  private var isMirrored = false

  init(player: AVPlayer) {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = true
    playerLayer.player = player
    playerLayer.videoGravity = .resizeAspectFill
    playerLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    layer?.addSublayer(playerLayer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func update(player: AVPlayer, cornerRadius: CGFloat, isMirrored: Bool) {
    if playerLayer.player !== player { playerLayer.player = player }
    self.isMirrored = isMirrored
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer?.cornerRadius = cornerRadius
    layer?.masksToBounds = true
    layoutPlayerLayer()
    CATransaction.commit()
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layoutPlayerLayer()
    CATransaction.commit()
  }

  private func layoutPlayerLayer() {
    // Set bounds/position (not frame) so the transform never feeds back into geometry.
    playerLayer.setAffineTransform(.identity)
    playerLayer.bounds = CGRect(origin: .zero, size: bounds.size)
    playerLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    playerLayer.setAffineTransform(isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
  }
}
