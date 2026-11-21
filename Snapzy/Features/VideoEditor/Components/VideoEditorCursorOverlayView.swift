//
//  VideoEditorCursorOverlayView.swift
//  Snapzy
//
//  Preview of the Studio cursor layer. Lives in the source-space host (inside the zoom
//  transform) and redraws from the same resolver the export uses on every playback
//  time tick; `size` is the displayed video rect.
//

import AVFoundation
import SwiftUI

struct VideoEditorCursorOverlayView: View {
  @ObservedObject var state: VideoEditorState
  @ObservedObject private var playbackState: VideoEditorPlaybackState
  let size: CGSize

  init(state: VideoEditorState, size: CGSize) {
    _state = ObservedObject(wrappedValue: state)
    _playbackState = ObservedObject(wrappedValue: state.playbackState)
    self.size = size
  }

  var body: some View {
    if let resolver = state.cursorResolver, let metadata = state.recordingMetadata,
       metadata.captureSize.width > 0 {
      let sequenceTime = CMTimeGetSeconds(playbackState.currentTime)
      Canvas { context, canvasSize in
        guard let sourceTime = state.cursorSourceTime(atSequence: sequenceTime),
              let frame = resolver.resolve(sourceTime: sourceTime)
        else { return }
        draw(frame, settings: resolver.settings, in: &context, size: canvasSize,
             pointsPerSourcePoint: canvasSize.width / metadata.captureSize.width)
      }
      .frame(width: size.width, height: size.height)
      .onReceive(playbackState.$currentTime) { time in
        updateClickSound(at: CMTimeGetSeconds(time))
      }
      .onReceive(playbackState.$isPlaying) { _ in
        updateClickSound(at: CMTimeGetSeconds(playbackState.currentTime))
      }
      .onAppear { prepareClickSoundIfEnabled() }
      .onChange(of: state.cursorSettings.clickSound) { _ in prepareClickSoundIfEnabled() }
      .onDisappear { state.clickSoundPlayer.reset() }
    }
  }

  /// Off the Play path: one main-queue turn after the overlay appears or the setting
  /// turns on, never inside the tick that starts playback.
  private func prepareClickSoundIfEnabled() {
    guard state.cursorSettings.clickSound,
          state.recordingMetadata?.cursorCapture?.clicks.isEmpty == false
    else { return }
    let player = state.clickSoundPlayer
    DispatchQueue.main.async { player.prepare() }
  }

  private func updateClickSound(at sequenceTime: TimeInterval) {
    let settings = state.cursorSettings
    state.clickSoundPlayer.update(
      enabled: settings.clickSound && !state.isMuted,
      clickSourceTimes: (state.recordingMetadata?.cursorCapture?.clicks ?? [])
        .filter { $0.phase == .down }.map(\.time),
      placements: state.placements,
      sequenceTime: sequenceTime,
      rate: state.player.rate,
      isPlaying: playbackState.isPlaying,
      volume: Float(settings.clickSoundVolume)
    )
  }

  private func draw(
    _ frame: VideoEditorCursorFrame,
    settings: VideoEditorCursorSettings,
    in context: inout GraphicsContext,
    size: CGSize,
    pointsPerSourcePoint scale: CGFloat
  ) {
    let color = settings.clickColor
    func ring(at point: CGPoint, radius: CGFloat, alpha: CGFloat) {
      let center = CGPoint(x: point.x * size.width, y: point.y * size.height)
      let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
      let width = max(VideoEditorCursorLayer.ringWidth * scale, 0.5)
      context.stroke(
        Path(ellipseIn: rect.insetBy(dx: width / 2, dy: width / 2)),
        with: .color(Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: alpha)),
        lineWidth: width
      )
    }
    for pulse in frame.pulses {
      ring(at: pulse.point, radius: (0.2 + 0.8 * pulse.progress) * VideoEditorCursorLayer.rippleDiameter / 2 * scale,
           alpha: color.alpha * (1 - pulse.progress))
    }
    for point in frame.held {
      ring(at: point, radius: VideoEditorCursorLayer.holdDiameter / 2 * scale, alpha: color.alpha)
    }

    guard frame.opacity > 0, let sprite = state.cursorSprites.sprite(for: frame.imageID) else { return }
    let spriteScale = settings.scale * scale
    let rect = CGRect(
      x: frame.position.x * size.width - sprite.hotspot.x * spriteScale,
      y: frame.position.y * size.height - sprite.hotspot.y * spriteScale,
      width: sprite.pointSize.width * spriteScale,
      height: sprite.pointSize.height * spriteScale
    )
    context.opacity = frame.opacity
    context.draw(Image(decorative: sprite.cgImage, scale: 1), in: rect)
  }
}
