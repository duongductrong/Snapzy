//
//  CameraPreviewSyncSpikeTests.swift
//  SnapzyTests
//
//  SPIKE (Decision D2). Gated: runs only with SNAPZY_SPIKE_CAMERA_SYNC=1
//  (xcodebuild: TEST_RUNNER_SNAPZY_SPIKE_CAMERA_SYNC=1) plus SNAPZY_SPIKE_SCREEN /
//  SNAPZY_SPIKE_CAMERA movie paths (≥ 16 s each). Prints one JSON line per scenario;
//  see plans/…/reports/spike-camera-preview-sync.md for how to read it.
//

import AppKit
import AVFoundation
import XCTest

@MainActor
final class CameraPreviewSyncSpikeTests: XCTestCase {
  private struct Stats {
    var clock: [Double] = []
    var frame: [Double] = []
    func json(_ name: String, corrections: Int, extra: String = "") -> String {
      func p(_ v: [Double], _ q: Double) -> String {
        guard !v.isEmpty else { return "null" }
        let s = v.map(abs).sorted()
        return String(format: "%.2f", s[min(s.count - 1, Int(Double(s.count - 1) * q))] * 1000)
      }
      return "{\"scenario\":\"\(name)\",\"samples\":\(frame.count),\"clockP50ms\":\(p(clock, 0.5)),"
        + "\"clockMaxMs\":\(p(clock, 1)),\"frameP50ms\":\(p(frame, 0.5)),\"frameP95ms\":\(p(frame, 0.95)),"
        + "\"frameMaxMs\":\(p(frame, 1)),\"corrections\":\(corrections)\(extra)}"
    }
  }

  private var window: NSWindow?

  func testCameraPreviewSyncSpike() async throws {
    let env = ProcessInfo.processInfo.environment
    guard env["SNAPZY_SPIKE_CAMERA_SYNC"] == "1",
          let screenPath = env["SNAPZY_SPIKE_SCREEN"], let cameraPath = env["SNAPZY_SPIKE_CAMERA"]
    else { throw XCTSkip("Set SNAPZY_SPIKE_CAMERA_SYNC=1, SNAPZY_SPIKE_SCREEN, SNAPZY_SPIKE_CAMERA") }
    let cameraFPS = Double(env["SNAPZY_SPIKE_CAMERA_FPS"] ?? "30") ?? 30

    // Same timeline construction for both items: clip [0,5) + clip [10,16), and the
    // span 2–4 s sped up 4× — a clip handoff and a speed section in one item.
    let screenItem = AVPlayerItem(asset: try await Self.edited(URL(fileURLWithPath: screenPath)))
    let cameraItem = AVPlayerItem(asset: try await Self.edited(URL(fileURLWithPath: cameraPath)))
    let sync = CameraPreviewSyncPrototype(primaryItem: screenItem, cameraItem: cameraItem, frameDuration: 1 / cameraFPS)
    showLayers(primary: sync.primary, camera: sync.camera)
    defer { window?.orderOut(nil); window = nil }
    try await waitReady(sync.primary, sync.camera)

    // 1. Continuous play across the speed section and the clip handoff.
    await sync.seekExact(to: .zero)
    await sync.play()
    print(try await measure(sync, seconds: 7.5).json("play-1x-handoff-speed4x", corrections: sync.corrections))

    // 2. Pause/play cycles.
    var stats = Stats()
    for _ in 0 ..< 5 {
      sync.pause()
      try await Task.sleep(nanoseconds: 300_000_000)
      stats.clock.append(sync.clockDrift())
      await sync.play()
      let s = try await measure(sync, seconds: 0.8)
      stats.clock += s.clock; stats.frame += s.frame
    }
    print(stats.json("pause-play-x5", corrections: sync.corrections))

    // 3. Exact seeks, then play.
    stats = Stats()
    for target in [1.0, 6.2, 3.1, 7.9, 0.4, 5.05, 2.7, 6.9] {
      sync.pause()
      await sync.seekExact(to: CMTime(seconds: target, preferredTimescale: 600))
      await sync.play()
      let s = try await measure(sync, seconds: 0.6)
      stats.clock += s.clock; stats.frame += s.frame
    }
    print(stats.json("seek-exact-x8", corrections: sync.corrections))

    // 4. Scrub burst (camera ¼ s tolerance), then release with an exact seek.
    sync.pause()
    for step in 0 ..< 40 {
      sync.scrub(to: CMTime(seconds: 1 + Double(step) * 0.15, preferredTimescale: 600))
      try await Task.sleep(nanoseconds: 33_000_000)
    }
    let releasedAt = Date()
    await sync.seekExact(to: CMTime(seconds: 7, preferredTimescale: 600))
    let settleMs = Date().timeIntervalSince(releasedAt) * 1000
    print("{\"scenario\":\"scrub-release\",\"clockAtRestMs\":\(String(format: "%.2f", abs(sync.clockDrift()) * 1000)),\"releaseSeekMs\":\(String(format: "%.0f", settleMs))}")

    // 5. Player rate 2×.
    await sync.seekExact(to: CMTime(seconds: 0.5, preferredTimescale: 600))
    await sync.play(rate: 2)
    print(try await measure(sync, seconds: 3).json("play-rate-2x", corrections: sync.corrections))
    sync.pause()

    // 6. CPU: primary alone vs primary + camera (both on screen).
    let both = try await cpuPercent(seconds: 6) {
      await sync.seekExact(to: .zero); await sync.play()
    }
    sync.pause()
    let solo = try await cpuPercent(seconds: 6) {
      sync.camera.replaceCurrentItem(with: nil)
      await sync.primary.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
      sync.primary.play()
    }
    sync.primary.pause()
    print(String(
      format: "{\"scenario\":\"cpu\",\"processPrimaryOnly\":%.1f,\"processWithCamera\":%.1f,"
        + "\"machinePrimaryOnly\":%.2f,\"machineWithCamera\":%.2f}",
      solo.process, both.process, solo.machine, both.machine
    ))
  }

  // MARK: - Helpers

  private func measure(_ sync: CameraPreviewSyncPrototype, seconds: Double) async throws -> Stats {
    var stats = Stats()
    sync.resetFrameSampling()
    let start = Date()
    var lastCheck = start
    try await Task.sleep(nanoseconds: 250_000_000) // settle after arm
    while Date().timeIntervalSince(start) < seconds {
      if sync.primary.rate != 0 {
        stats.clock.append(sync.clockDrift())
        if let drift = sync.sampleDisplayedFrameDrift() { stats.frame.append(drift) }
      }
      if Date().timeIntervalSince(lastCheck) >= 0.1 { // editor periodic observer interval
        lastCheck = Date()
        await sync.checkAndCorrect()
      }
      try await Task.sleep(nanoseconds: 16_000_000)
    }
    return stats
  }

  /// (process % of one core, whole-machine busy % — includes VTDecoderXPCService/WindowServer).
  private func cpuPercent(seconds: Double, start: () async -> Void) async throws -> (process: Double, machine: Double) {
    await start()
    try await Task.sleep(nanoseconds: 500_000_000)
    let cpu0 = SpikeMetrics.processCPUTime(), wall0 = Date(), ticks0 = SpikeMetrics.machineTicks()
    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    let ticks1 = SpikeMetrics.machineTicks()
    let busy = Double(ticks1.busy - ticks0.busy), total = Double(ticks1.total - ticks0.total)
    return ((SpikeMetrics.processCPUTime() - cpu0) / Date().timeIntervalSince(wall0) * 100, total > 0 ? busy / total * 100 : 0)
  }

  private func showLayers(primary: AVPlayer, camera: AVPlayer) {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540), styleMask: [.borderless], backing: .buffered, defer: false)
    let root = CALayer()
    window.contentView?.wantsLayer = true
    window.contentView?.layer = root
    let screenLayer = AVPlayerLayer(player: primary)
    screenLayer.frame = root.bounds.isEmpty ? CGRect(x: 0, y: 0, width: 960, height: 540) : root.bounds
    let cameraLayer = AVPlayerLayer(player: camera)
    cameraLayer.frame = CGRect(x: 760, y: 20, width: 180, height: 180)
    cameraLayer.videoGravity = .resizeAspectFill
    cameraLayer.cornerRadius = 90
    cameraLayer.masksToBounds = true
    root.addSublayer(screenLayer)
    root.addSublayer(cameraLayer)
    window.orderFrontRegardless()
    self.window = window
  }

  private func waitReady(_ players: AVPlayer...) async throws {
    for _ in 0 ..< 200 where players.contains(where: { $0.currentItem?.status != .readyToPlay }) {
      try await Task.sleep(nanoseconds: 25_000_000)
    }
    XCTAssertTrue(players.allSatisfy { $0.currentItem?.status == .readyToPlay })
  }

  static func edited(_ url: URL) async throws -> AVComposition {
    let asset = AVURLAsset(url: url)
    let composition = AVMutableComposition()
    let sourceTracks = try await asset.loadTracks(withMediaType: .video)
    let source = try XCTUnwrap(sourceTracks.first)
    let track = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
    func t(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }
    try track.insertTimeRange(CMTimeRange(start: .zero, duration: t(5)), of: source, at: .zero)
    try track.insertTimeRange(CMTimeRange(start: t(10), duration: t(6)), of: source, at: t(5))
    track.scaleTimeRange(CMTimeRange(start: t(2), duration: t(2)), toDuration: t(0.5))
    return composition
  }
}
