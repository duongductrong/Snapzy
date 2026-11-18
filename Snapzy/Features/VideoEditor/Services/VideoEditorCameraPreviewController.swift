//
//  VideoEditorCameraPreviewController.swift
//  Snapzy
//
//  Editor preview of the Studio camera (Decision D2, simplified): a second, muted
//  AVPlayer on the camera sidecar. The sidecar's time axis is the recording's source
//  time, so each playback tick maps the playhead to source time (the same mapping the
//  cursor uses) and keeps the camera player there: while playing it runs at the speed
//  of the current speed segment and re-seeks once drift exceeds a few frames; while
//  paused or scrubbing it seeks exactly, coalescing seeks so scrubbing never queues up.
//

import AVFoundation
import Foundation

@MainActor
final class VideoEditorCameraPreviewController {
  /// Playing drift tolerated before a corrective seek.
  static let playingDriftTolerance: TimeInterval = 0.12

  let player: AVPlayer
  private var seekInFlight = false
  private var pending: (time: TimeInterval, rate: Float)?

  init(url: URL) {
    let player = AVPlayer(url: url)
    player.isMuted = true
    player.automaticallyWaitsToMinimizeStalling = false
    player.actionAtItemEnd = .pause
    self.player = player
  }

  /// `sourceTime` nil (inserted clip, trimmed footage) pauses the camera.
  func update(sourceTime: TimeInterval?, isPlaying: Bool, rate: Float) {
    guard let target = sourceTime else {
      if player.rate != 0 { player.pause() }
      return
    }
    let current = player.currentTime().seconds
    if isPlaying, rate > 0 {
      if !current.isFinite || abs(current - target) > Self.playingDriftTolerance {
        seek(to: target, tolerance: 1.0 / 30, thenRate: rate)
      } else if !seekInFlight, player.rate != rate {
        player.rate = rate
      }
    } else {
      if player.rate != 0 { player.pause() }
      if !current.isFinite || abs(current - target) > 1.0 / 120 {
        seek(to: target, tolerance: 0, thenRate: 0)
      }
    }
  }

  func stop() {
    player.pause()
    pending = nil
  }

  private func seek(to time: TimeInterval, tolerance: TimeInterval, thenRate rate: Float) {
    if seekInFlight {
      pending = (time, rate)
      return
    }
    seekInFlight = true
    let toleranceTime = CMTime(seconds: tolerance, preferredTimescale: 600)
    player.seek(
      to: CMTime(seconds: max(time, 0), preferredTimescale: 600),
      toleranceBefore: toleranceTime,
      toleranceAfter: toleranceTime
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        seekInFlight = false
        if let next = pending {
          pending = nil
          seek(to: next.time, tolerance: next.rate > 0 ? 1.0 / 30 : 0, thenRate: next.rate)
        } else if rate > 0 {
          player.rate = rate
        }
      }
    }
  }
}
