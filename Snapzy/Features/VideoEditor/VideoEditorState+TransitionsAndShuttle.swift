//
//  VideoEditorState+TransitionsAndShuttle.swift
//  Snapzy
//
//  Video clip transitions (Crossfade / Dip to Black) between abutting clips,
//  plus pro NLE transport controls: J / K / L multi-speed shuttle and
//  single-frame stepping (, / .).
//

import AVFoundation
import Foundation
import QuartzCore

extension VideoEditorState {
  // MARK: - Video Transitions (Crossfade / Dip to Black)

  /// Resolved seam descriptor between two abutting video clips on the structural timeline.
  struct AbuttingClipSeam: Identifiable, Equatable {
    let incomingClipId: UUID
    let incomingClipIndex: Int
    let outgoingClipId: UUID
    let cutTime: TimeInterval
    let outgoingDuration: TimeInterval
    let incomingDuration: TimeInterval
    let transition: TimelineClipTransition?

    var id: UUID {
      incomingClipId
    }

    var effectiveDuration: TimeInterval {
      guard let transition, transition.isActive else { return 0 }
      return TimelineClipTransition.effectiveDuration(
        requested: transition.duration,
        outgoingClipDuration: outgoingDuration,
        incomingClipDuration: incomingDuration
      )
    }
  }

  /// Every seam where two consecutive clips touch without an empty black-screen gap.
  var abuttingClipSeams: [AbuttingClipSeam] {
    guard !isGIF else { return [] }
    let laid = placements
    guard laid.count >= 2 else { return [] }
    var seams: [AbuttingClipSeam] = []
    for idx in 1 ..< laid.count {
      let prev = laid[idx - 1]
      let curr = laid[idx]
      guard abs(curr.activeStart - prev.activeEnd) <= TimelineClipTransition.abuttingGapTolerance else { continue }
      seams.append(
        AbuttingClipSeam(
          incomingClipId: curr.clip.id,
          incomingClipIndex: curr.index,
          outgoingClipId: prev.clip.id,
          cutTime: curr.activeStart,
          outgoingDuration: prev.clip.duration,
          incomingDuration: curr.clip.duration,
          transition: curr.clip.leadingTransition
        )
      )
    }
    return seams
  }

  /// Set or clear the transition on the leading seam of `clipId` (between the previous clip
  /// and `clipId`). Records a single Undo step.
  func setClipTransition(
    clipId: UUID,
    style: TimelineClipTransition.Style,
    duration: TimeInterval = TimelineClipTransition.defaultDuration
  ) {
    guard !isGIF,
          let idx = clips.firstIndex(where: { $0.id == clipId }),
          idx > 0
    else { return }

    let prevClip = clips[idx - 1]
    let currClip = clips[idx]
    let nextTransition: TimelineClipTransition?
    if style == .none {
      nextTransition = nil
    } else {
      let laid = placements
      guard idx < laid.count,
            abs(laid[idx].activeStart - laid[idx - 1].activeEnd) <= TimelineClipTransition.abuttingGapTolerance
      else { return }
      let effective = TimelineClipTransition.effectiveDuration(
        requested: duration,
        outgoingClipDuration: prevClip.duration,
        incomingClipDuration: currClip.duration
      )
      guard effective >= TimelineClipTransition.minDuration - 0.0001 else { return }
      nextTransition = TimelineClipTransition(style: style, duration: effective)
    }

    guard currClip.leadingTransition != nextTransition else { return }
    var updated = clips
    updated[idx].leadingTransition = nextTransition
    applyClipsReplacing(updated, recordUndo: true)
  }

  /// Live preview state for an active video transition at `timelineTime`.
  struct TransitionPreviewState: Equatable {
    let style: TimelineClipTransition.Style
    /// Normalized `[0, 1]` progress across `[cutTime - duration/2, cutTime + duration/2]`.
    let progress: Double
    /// Smooth black dip alpha (`0 → 1 → 0`) for `.dipToBlack`.
    let dipAlpha: Double
    /// Outgoing clip id so `.crossfade` preview can blend its trailing thumbnail smoothly.
    let outgoingClipId: UUID
    /// Outgoing source timestamp near the cut seam.
    let outgoingSourceEnd: TimeInterval
  }

  func activeTransitionPreview(at timelineTime: TimeInterval) -> TransitionPreviewState? {
    guard !isGIF, hasActiveTransitions else { return nil }
    for seam in abuttingClipSeams {
      guard let transition = seam.transition, transition.isActive else { continue }
      let eff = seam.effectiveDuration
      guard eff > 0.01 else { continue }
      let half = eff / 2.0
      let start = seam.cutTime - half
      let end = seam.cutTime + half
      guard timelineTime >= start, timelineTime <= end else { continue }
      let p = min(max((timelineTime - start) / eff, 0), 1)
      let dip = transition.style == .dipToBlack ? min(max(sin(p * .pi), 0), 1) : 0
      let outgoingEnd = clips.first(where: { $0.id == seam.outgoingClipId })?.sourceEnd ?? 0
      return TransitionPreviewState(
        style: transition.style,
        progress: p,
        dipAlpha: dip,
        outgoingClipId: seam.outgoingClipId,
        outgoingSourceEnd: outgoingEnd
      )
    }
    return nil
  }

  // MARK: - J / K / L Shuttle & Frame Stepping (, / .)

  /// `L` key: play forward and step shuttle speed `1× → 2× → 4×`.
  func shuttleForward() {
    guard !isGIF else { return }
    let current = playbackState.shuttleRate
    let wasReversing = reverseShuttleTimer != nil || current < 0
    stopReverseShuttleTimer()

    let nextRate: Float = if !playbackState.isPlaying || current <= 0 {
      1.0
    } else if current < 1.5 {
      2.0
    } else {
      4.0
    }

    if wasReversing {
      playbackState.setPlaying(false)
    }

    playbackState.setShuttleRate(nextRate)
    if wasReversing {
      syncPlayerAudioWithExportSettings()
    }
    if !playbackState.isPlaying {
      play()
    }
    player.isMuted = shouldMutePreviewPlayer

    if audioTailPlaybackTimer == nil {
      if nextRate > 1.05 {
        setPreviewRateControllerEnabled(false)
        addedAudioPlayer.pause()
      } else {
        setPreviewRateControllerEnabled(true)
        if playbackState.isPlaying {
          addedAudioPlayer.play(at: CMTimeGetSeconds(playbackState.currentTime), forceSeek: true)
        }
      }
      if playbackState.isPlaying {
        player.defaultRate = nextRate
        if isPreviewTransportReadyForImmediateRateChange {
          player.rate = nextRate
        }
      }
    }
  }

  /// `K` key: immediate stop / pause shuttle and reset rate to `0`.
  func shuttlePause() {
    guard !isGIF else { return }
    stopReverseShuttleTimer()
    playbackState.setShuttleRate(0)
    pause()
    syncPlayerAudioWithExportSettings()
  }

  /// `J` key: shuttle backward `-1× → -2× → -4×` using a lightweight coalesced wall-clock
  /// reverse stepper that works universally across every codec and across black-screen gaps.
  func shuttleReverse() {
    guard !isGIF else { return }
    let current = playbackState.shuttleRate
    let nextRate: Float = if current >= 0 {
      -1.0
    } else if current > -1.5 {
      -2.0
    } else {
      -4.0
    }

    // Stop forward playback and rate-controller resume intent cleanly so async seek
    // completions never restart forward AVPlayer playback or emit audio blips between ticks.
    stopAudioTailPlayback()
    addedAudioPlayer.pause()
    setPreviewRateControllerEnabled(false)
    player.isMuted = true
    player.pause()
    player.rate = 0
    playbackState.setShuttleRate(nextRate)
    playbackState.setPlaying(true)

    if reverseShuttleTimer == nil {
      reverseShuttleLastTick = CACurrentMediaTime()
      let step: TimeInterval = 1.0 / 30.0
      reverseShuttleTimer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.tickReverseShuttle()
        }
      }
    }
  }

  private func tickReverseShuttle() {
    guard playbackState.isPlaying, playbackState.shuttleRate < 0 else {
      stopReverseShuttleTimer()
      return
    }
    let now = CACurrentMediaTime()
    let dt = min(0.1, max(0, now - reverseShuttleLastTick))
    reverseShuttleLastTick = now

    let currentSec = CMTimeGetSeconds(playbackState.currentTime)
    let speed = Double(abs(playbackState.shuttleRate))
    let nextSec = max(0, currentSec - dt * speed)

    let target = CMTime(seconds: nextSec, preferredTimescale: 600)
    playbackState.setCurrentTime(target)
    seekPlayerForReverseShuttle(to: nextSec)
    updateClipActionAvailability()

    if nextSec <= 0.001 {
      shuttlePause()
    }
  }

  func stopReverseShuttleTimer() {
    reverseShuttleTimer?.invalidate()
    reverseShuttleTimer = nil
  }

  /// Step playhead by exactly one video frame forward (`.`) or backward (`,`).
  func stepFrame(forward: Bool) {
    guard !isGIF else { return }
    if playbackState.isPlaying || playbackState.shuttleRate != 0 {
      shuttlePause()
    }
    let fps = max(1.0, nominalFrameRate)
    let frameDuration = 1.0 / fps
    let currentSec = CMTimeGetSeconds(playbackState.currentTime)
    let totalSec = max(0, CMTimeGetSeconds(timelineDuration))
    let delta = forward ? frameDuration : -frameDuration
    let targetSec = max(0, min(totalSec, currentSec + delta))
    seek(to: CMTime(seconds: targetSec, preferredTimescale: 600))
  }
}
