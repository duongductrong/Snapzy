//
//  VideoEditorAddedAudioPlayer.swift
//  Snapzy
//
//  Lightweight live-preview companion audio player for independent audio clips
//  (imported `.file` audio tracks, plus `.primary` audio whenever it is moved,
//  trimmed independently, split, or extends past the end of the video).
//

import AVFoundation
import Foundation

@MainActor
final class VideoEditorAddedAudioPlayer {
  private var players: [UUID: AVAudioPlayer] = [:]
  private var playerURLs: [UUID: URL] = [:]
  private var syncTimer: Timer?
  private var isPlaying = false
  private var currentTimelineTime: () -> TimeInterval = { 0 }
  private var currentPlaybackRate: () -> Float = { 1.0 }
  private var activeClips: [AudioTimelineClip] = []
  private var isMasterMuted = false
  private var mutedLanes: Set<Int> = []

  /// Supported `AVAudioPlayer.rate` range (`0.5× ... 2.0×`). Outside this range (e.g. `0.25×`,
  /// `4×`, `8×`, or reverse shuttle), added audio pauses cleanly instead of stuttering.
  static let minSupportedRate: Float = 0.5
  static let maxSupportedRate: Float = 2.0

  /// Explicit and nonisolated: avoids macOS 13-15 swift_task_deinitOnExecutor abort (#668).
  nonisolated deinit {}

  func configure(
    clips: [AudioTimelineClip],
    includePrimary: Bool,
    urlProvider: (AudioTimelineClip) -> URL,
    isMasterMuted: Bool,
    mutedLanes: Set<Int> = [],
    playbackRateProvider: @escaping () -> Float = { 1.0 },
    timelineTimeProvider: @escaping () -> TimeInterval
  ) {
    activeClips = includePrimary ? clips : clips.filter { !$0.isPrimary }
    self.isMasterMuted = isMasterMuted
    self.mutedLanes = mutedLanes
    currentPlaybackRate = playbackRateProvider
    currentTimelineTime = timelineTimeProvider

    let validIds = Set(activeClips.map(\.id))
    for (id, player) in players where !validIds.contains(id) {
      player.stop()
      players.removeValue(forKey: id)
      playerURLs.removeValue(forKey: id)
    }

    for clip in activeClips {
      let url = urlProvider(clip)
      if players[clip.id] != nil, playerURLs[clip.id] == url {
        continue
      }
      players[clip.id]?.stop()
      guard let audioPlayer = try? AVAudioPlayer(contentsOf: url) else { continue }
      audioPlayer.enableRate = true
      audioPlayer.prepareToPlay()
      players[clip.id] = audioPlayer
      playerURLs[clip.id] = url
    }

    if isPlaying {
      syncAll(to: currentTimelineTime(), forceSeek: false)
    }
  }

  func play(at timelineTime: TimeInterval, forceSeek: Bool = true) {
    isPlaying = true
    syncAll(to: timelineTime, forceSeek: forceSeek)
    startSyncTimer()
  }

  func pause() {
    isPlaying = false
    stopSyncTimer()
    for player in players.values where player.isPlaying {
      player.pause()
    }
  }

  func seek(to timelineTime: TimeInterval) {
    if isPlaying {
      syncAll(to: timelineTime, forceSeek: true)
    } else {
      for player in players.values where player.isPlaying {
        player.pause()
      }
    }
  }

  func stopAll() {
    isPlaying = false
    stopSyncTimer()
    for player in players.values {
      player.stop()
    }
    players.removeAll()
    playerURLs.removeAll()
  }

  // MARK: - Sync

  private func startSyncTimer() {
    stopSyncTimer()
    syncTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
      guard self != nil else {
        timer.invalidate()
        return
      }
      Task { @MainActor [weak self] in
        guard let self, isPlaying else { return }
        syncAll(to: currentTimelineTime(), forceSeek: false)
      }
    }
  }

  private func stopSyncTimer() {
    syncTimer?.invalidate()
    syncTimer = nil
  }

  private func syncAll(to timelineTime: TimeInterval, forceSeek: Bool) {
    let rawRate = currentPlaybackRate()
    let rateSupported = rawRate.isFinite
      && rawRate >= Self.minSupportedRate - 0.01
      && rawRate <= Self.maxSupportedRate + 0.05
    let clampedRate = min(max(rawRate.isFinite ? rawRate : 1.0, Self.minSupportedRate), Self.maxSupportedRate)
    let driftTolerance = max(0.12, 0.12 * Double(clampedRate))

    for clip in activeClips {
      guard let player = players[clip.id] else { continue }

      if !rateSupported
        || isMasterMuted
        || clip.isMuted
        || mutedLanes.contains(clip.trackIndex)
        || !clip.contains(timelineTime: timelineTime) {
        if player.isPlaying {
          player.pause()
        }
        continue
      }

      let targetSourceTime = clip.sourceStart + (timelineTime - clip.timelineStart)
      let drift = abs(player.currentTime - targetSourceTime)
      if forceSeek || !player.isPlaying || drift > driftTolerance {
        player.currentTime = max(0, min(targetSourceTime, player.duration))
      }

      if abs(player.rate - clampedRate) > 0.01 {
        player.rate = clampedRate
      }
      player.volume = effectivePreviewVolume(for: clip, at: timelineTime)
      if !player.isPlaying {
        player.play()
      }
    }
  }

  func previewStateForTesting(clipId: UUID) -> (isPlaying: Bool, volume: Float, rate: Float)? {
    guard let player = players[clipId] else { return nil }
    return (player.isPlaying, player.volume, player.rate)
  }

  private func effectivePreviewVolume(for clip: AudioTimelineClip, at timelineTime: TimeInterval) -> Float {
    let localTime = timelineTime - clip.timelineStart
    let fades = VideoEditorAudioMixFactory.resolvedFadeDurations(
      fadeIn: clip.fadeIn,
      fadeOut: clip.fadeOut,
      totalDuration: clip.duration
    )
    var envelope: Float = 1.0
    if fades.fadeIn > 0.001, localTime < fades.fadeIn {
      envelope *= Float(max(0, min(1, localTime / fades.fadeIn)))
    }
    if fades.fadeOut > 0.001, localTime > clip.duration - fades.fadeOut {
      envelope *= Float(max(0, min(1, (clip.duration - localTime) / fades.fadeOut)))
    }
    return min(max(clip.volume * envelope, 0), AudioTimelineClip.maxVolume)
  }
}
