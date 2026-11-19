//
//  CameraPreviewSyncPrototype.swift
//  SnapzyTests
//
//  SPIKE (phase 0, Decision D2) — not production code. Mirrors a primary AVPlayer onto
//  a muted camera player that plays an item with the same timeline construction:
//  shared host clock, preroll + `setRate(_:time:atHostTime:)` +50 ms, and self-correction
//  (drift > 1 frame on 2 consecutive checks ⇒ exact seek + re-arm). Phase 4 promotes the
//  surviving parts into `CameraPreviewSync`.
//

import AVFoundation
import CoreMedia

@MainActor
final class CameraPreviewSyncPrototype {
  let primary: AVPlayer
  let camera: AVPlayer
  let primaryOutput: AVPlayerItemVideoOutput
  let cameraOutput: AVPlayerItemVideoOutput
  /// Tolerance before self-correction kicks in (one camera frame).
  let frameDuration: Double
  private(set) var corrections = 0
  private var consecutiveDriftChecks = 0
  private let armDelay: Double = 0.05

  init(primaryItem: AVPlayerItem, cameraItem: AVPlayerItem, frameDuration: Double) {
    let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    primaryOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
    cameraOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
    primaryItem.add(primaryOutput)
    cameraItem.add(cameraOutput)
    primary = AVPlayer(playerItem: primaryItem)
    camera = AVPlayer(playerItem: cameraItem)
    camera.isMuted = true
    self.frameDuration = frameDuration
    let hostClock = CMClockGetHostTimeClock()
    for player in [primary, camera] {
      player.masterClock = hostClock
      player.automaticallyWaitsToMinimizeStalling = false
    }
  }

  // MARK: - Mirrored transport

  func play(rate: Float = 1) async {
    let start = primary.currentTime()
    await preroll(at: start, rate: rate)
    arm(rate: rate, itemTime: start)
  }

  func pause() {
    primary.pause()
    camera.pause()
    // Freeze the camera exactly on the primary's frame.
    camera.seek(to: primary.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
  }

  /// Exact seek of both players (playhead release, programmatic seek).
  func seekExact(to time: CMTime) async {
    async let a: Bool = primary.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    async let b: Bool = camera.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    _ = await (a, b)
  }

  /// Scrub: exact primary (as the editor does today), loose camera (¼ s) for smoothness.
  func scrub(to time: CMTime) {
    let quarter = CMTime(seconds: 0.25, preferredTimescale: 600)
    primary.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    camera.seek(to: time, toleranceBefore: quarter, toleranceAfter: quarter)
  }

  // MARK: - Measurement + self-correction

  /// Item-time difference camera − primary at the same host time (timebase level).
  func clockDrift(atHostTime host: CMTime = CMClockGetTime(CMClockGetHostTimeClock())) -> Double {
    let p = primaryOutput.itemTime(forHostTime: CMTimeGetSeconds(host))
    let c = cameraOutput.itemTime(forHostTime: CMTimeGetSeconds(host))
    return CMTimeGetSeconds(c) - CMTimeGetSeconds(p)
  }

  private var lastPrimaryPTS = CMTime.invalid
  private var lastCameraPTS = CMTime.invalid

  /// Pulls any new frame from both outputs (what a display link would do) and returns
  /// the PTS difference camera − primary of the latest frames (frame level), or `nil`
  /// until both delivered one.
  func sampleDisplayedFrameDrift() -> Double? {
    let host = CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))
    lastPrimaryPTS = pull(primaryOutput, host: host) ?? lastPrimaryPTS
    lastCameraPTS = pull(cameraOutput, host: host) ?? lastCameraPTS
    guard lastPrimaryPTS.isValid, lastCameraPTS.isValid else { return nil }
    return CMTimeGetSeconds(lastCameraPTS) - CMTimeGetSeconds(lastPrimaryPTS)
  }

  func resetFrameSampling() {
    lastPrimaryPTS = .invalid
    lastCameraPTS = .invalid
  }

  private func pull(_ output: AVPlayerItemVideoOutput, host: CFTimeInterval) -> CMTime? {
    let itemTime = output.itemTime(forHostTime: host)
    guard output.hasNewPixelBuffer(forItemTime: itemTime) else { return nil }
    var display = CMTime.invalid
    guard output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &display) != nil,
          display.isValid else { return nil }
    return display
  }

  /// Called from the editor's existing periodic observer. Returns true if it corrected.
  @discardableResult
  func checkAndCorrect() async -> Bool {
    let drift = abs(clockDrift())
    guard drift > frameDuration else {
      consecutiveDriftChecks = 0
      return false
    }
    consecutiveDriftChecks += 1
    guard consecutiveDriftChecks >= 2 else { return false }
    consecutiveDriftChecks = 0
    corrections += 1
    let rate = primary.rate
    if rate == 0 {
      await camera.seek(to: primary.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
      return true
    }
    // Re-arm the camera onto the primary's future position on the shared clock.
    let host = CMClockGetTime(CMClockGetHostTimeClock())
    let armHost = CMTimeAdd(host, CMTime(seconds: armDelay * 2, preferredTimescale: 1_000_000_000))
    let target = primaryOutput.itemTime(forHostTime: CMTimeGetSeconds(armHost))
    camera.pause()
    await camera.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    _ = await camera.preroll(atRate: rate)
    camera.setRate(rate, time: target, atHostTime: armHost)
    return true
  }

  // MARK: - Private

  private func preroll(at time: CMTime, rate: Float) async {
    await camera.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    async let a: Bool = primary.preroll(atRate: rate)
    async let b: Bool = camera.preroll(atRate: rate)
    _ = await (a, b)
  }

  private func arm(rate: Float, itemTime: CMTime) {
    let host = CMClockGetTime(CMClockGetHostTimeClock())
    let armHost = CMTimeAdd(host, CMTime(seconds: armDelay, preferredTimescale: 1_000_000_000))
    primary.setRate(rate, time: itemTime, atHostTime: armHost)
    camera.setRate(rate, time: itemTime, atHostTime: armHost)
  }
}
