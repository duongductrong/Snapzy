//
//  RecordingMouseTracker.swift
//  Snapzy
//
//  Polls the global mouse location while recording so the editor can
//  reconstruct a smooth follow-camera path later.
//

import AppKit
import Foundation

@MainActor
final class RecordingMouseTracker {
  struct TrackingDiagnostics {
    let sampleCount: Int
    let duration: TimeInterval
    let effectiveSamplesPerSecond: Double
    let averageIntervalMs: Double
    let p95IntervalMs: Double
  }

  private let recordingRect: CGRect
  private let samplesPerSecondValue: Int
  private let sampleInterval: TimeInterval
  private let uptimeProvider: () -> TimeInterval
  private let mouseLocationProvider: () -> CGPoint
  private let mouseMonitorInstaller: (@escaping () -> Void) -> Any?
  private let mouseMonitorRemover: (Any) -> Void

  private var timer: Timer?
  private var globalMouseMonitor: Any?
  private var samples: [RecordedMouseSample] = []
  private var startUptime: TimeInterval?
  private var pausedAtUptime: TimeInterval?
  private var accumulatedPausedDuration: TimeInterval = 0
  private(set) var diagnostics: TrackingDiagnostics?

  nonisolated static func resolvedSamplesPerSecond(for fps: Int) -> Int {
    min(max(fps * 2, 60), 120)
  }

  init(
    recordingRect: CGRect,
    fps: Int,
    uptimeProvider: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    mouseLocationProvider: @escaping () -> CGPoint = { NSEvent.mouseLocation },
    mouseMonitorInstaller: @escaping (@escaping () -> Void) -> Any? = { onMouseEvent in
      NSEvent.addGlobalMonitorForEvents(
        matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
      ) { _ in
        onMouseEvent()
      }
    },
    mouseMonitorRemover: @escaping (Any) -> Void = { NSEvent.removeMonitor($0) }
  ) {
    self.recordingRect = recordingRect
    let samplesPerSecond = Self.resolvedSamplesPerSecond(for: fps)
    self.samplesPerSecondValue = samplesPerSecond
    self.sampleInterval = 1.0 / Double(samplesPerSecond)
    self.uptimeProvider = uptimeProvider
    self.mouseLocationProvider = mouseLocationProvider
    self.mouseMonitorInstaller = mouseMonitorInstaller
    self.mouseMonitorRemover = mouseMonitorRemover
  }

  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  var samplesPerSecond: Int {
    samplesPerSecondValue
  }

  /// Recording time on this tracker's clock (pauses excluded); `nil` before `start()`.
  /// Studio cursor/click capture stamps events with it so they line up with samples.
  var elapsedTime: TimeInterval? {
    currentElapsedTime()
  }

  var isPaused: Bool {
    pausedAtUptime != nil
  }

  var isRunning: Bool {
    startUptime != nil
  }

  /// Global capture rect in AppKit coordinates (bottom-left origin).
  var captureRect: CGRect {
    recordingRect
  }

  func start() {
    reset()

    startUptime = uptimeProvider()
    appendCurrentSample(force: true, location: nil)
    installGlobalMouseMonitor()

    let timer = Timer(timeInterval: sampleInterval, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.appendCurrentSample(force: false, location: nil)
      }
    }
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func pause() {
    guard startUptime != nil, pausedAtUptime == nil else { return }
    appendCurrentSample(force: true, location: nil)
    pausedAtUptime = uptimeProvider()
  }

  func resume() {
    guard let pausedAtUptime else { return }

    accumulatedPausedDuration += uptimeProvider() - pausedAtUptime
    self.pausedAtUptime = nil
    appendCurrentSample(force: true, location: nil)
  }

  func stop() -> [RecordedMouseSample] {
    appendCurrentSample(force: true, location: nil)
    timer?.invalidate()
    timer = nil
    if let globalMouseMonitor {
      mouseMonitorRemover(globalMouseMonitor)
      self.globalMouseMonitor = nil
    }
    pausedAtUptime = nil
    diagnostics = buildDiagnostics(from: samples)
    return samples
  }

  func reset() {
    timer?.invalidate()
    timer = nil
    if let globalMouseMonitor {
      mouseMonitorRemover(globalMouseMonitor)
      self.globalMouseMonitor = nil
    }
    samples.removeAll(keepingCapacity: true)
    startUptime = nil
    pausedAtUptime = nil
    accumulatedPausedDuration = 0
    diagnostics = nil
  }

  private func appendCurrentSample(force: Bool, location: CGPoint?) {
    if pausedAtUptime != nil && !force {
      return
    }

    guard let elapsedTime = currentElapsedTime(),
          recordingRect.width > 0,
          recordingRect.height > 0
    else {
      return
    }

    let cursorLocation = location ?? mouseLocationProvider()
    let rawX = (cursorLocation.x - recordingRect.minX) / recordingRect.width
    let rawY = (cursorLocation.y - recordingRect.minY) / recordingRect.height
    // Convert AppKit global coordinates (bottom-left origin) into top-left normalized space.
    let topLeftY = 1 - rawY

    let sample = RecordedMouseSample(
      time: elapsedTime,
      normalizedX: rawX.clamped(to: 0...1),
      normalizedY: topLeftY.clamped(to: 0...1),
      isInsideCapture: recordingRect.contains(cursorLocation)
    )

    if !force, let lastSample = samples.last {
      let minimumDelta = min(sampleInterval * 0.5, 1.0 / 240.0)
      if sample.time - lastSample.time < minimumDelta,
         sample.normalizedX == lastSample.normalizedX,
         sample.normalizedY == lastSample.normalizedY,
         sample.isInsideCapture == lastSample.isInsideCapture
      {
        return
      }
    }

    samples.append(sample)
  }

  private func installGlobalMouseMonitor() {
    guard globalMouseMonitor == nil else { return }

    globalMouseMonitor = mouseMonitorInstaller { [weak self] in
      Task { @MainActor [weak self] in
        self?.appendCurrentSample(force: false, location: nil)
      }
    }
  }

  private func buildDiagnostics(from samples: [RecordedMouseSample]) -> TrackingDiagnostics? {
    guard samples.count >= 2,
          let first = samples.first,
          let last = samples.last
    else {
      return nil
    }

    let duration = max(last.time - first.time, 0)
    guard duration > 0 else {
      return TrackingDiagnostics(
        sampleCount: samples.count,
        duration: 0,
        effectiveSamplesPerSecond: 0,
        averageIntervalMs: 0,
        p95IntervalMs: 0
      )
    }

    var deltasMs: [Double] = []
    deltasMs.reserveCapacity(samples.count - 1)
    for idx in 1..<samples.count {
      deltasMs.append((samples[idx].time - samples[idx - 1].time) * 1000)
    }

    let averageIntervalMs = deltasMs.reduce(0, +) / Double(max(deltasMs.count, 1))
    let sorted = deltasMs.sorted()
    let p95Index = min(max(Int(Double(sorted.count - 1) * 0.95), 0), max(sorted.count - 1, 0))
    let p95IntervalMs = sorted.isEmpty ? 0 : sorted[p95Index]

    return TrackingDiagnostics(
      sampleCount: samples.count,
      duration: duration,
      effectiveSamplesPerSecond: Double(samples.count - 1) / duration,
      averageIntervalMs: averageIntervalMs,
      p95IntervalMs: p95IntervalMs
    )
  }

  private func currentElapsedTime() -> TimeInterval? {
    guard let startUptime else { return nil }

    let referenceUptime = pausedAtUptime ?? uptimeProvider()
    return max(0, referenceUptime - startUptime - accumulatedPausedDuration)
  }
}

private extension CGFloat {
  func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}
