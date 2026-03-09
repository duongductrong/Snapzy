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
  private let recordingRect: CGRect
  private let sampleInterval: TimeInterval

  private var timer: Timer?
  private var samples: [RecordedMouseSample] = []
  private var startUptime: TimeInterval?
  private var pausedAtUptime: TimeInterval?
  private var accumulatedPausedDuration: TimeInterval = 0

  init(recordingRect: CGRect, fps: Int) {
    self.recordingRect = recordingRect
    let samplesPerSecond = min(max(fps, 15), 60)
    self.sampleInterval = 1.0 / Double(samplesPerSecond)
  }

  var samplesPerSecond: Int {
    Int((1.0 / sampleInterval).rounded())
  }

  func start() {
    reset()

    startUptime = ProcessInfo.processInfo.systemUptime
    appendCurrentSample(force: true)

    let timer = Timer(timeInterval: sampleInterval, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.appendCurrentSample(force: false)
      }
    }
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func pause() {
    guard startUptime != nil, pausedAtUptime == nil else { return }
    appendCurrentSample(force: true)
    pausedAtUptime = ProcessInfo.processInfo.systemUptime
  }

  func resume() {
    guard let pausedAtUptime else { return }

    accumulatedPausedDuration += ProcessInfo.processInfo.systemUptime - pausedAtUptime
    self.pausedAtUptime = nil
    appendCurrentSample(force: true)
  }

  func stop() -> [RecordedMouseSample] {
    appendCurrentSample(force: true)
    timer?.invalidate()
    timer = nil
    pausedAtUptime = nil
    return samples
  }

  func reset() {
    timer?.invalidate()
    timer = nil
    samples.removeAll(keepingCapacity: true)
    startUptime = nil
    pausedAtUptime = nil
    accumulatedPausedDuration = 0
  }

  private func appendCurrentSample(force: Bool) {
    if pausedAtUptime != nil && !force {
      return
    }

    guard let elapsedTime = currentElapsedTime(),
          recordingRect.width > 0,
          recordingRect.height > 0
    else {
      return
    }

    let location = NSEvent.mouseLocation
    let rawX = (location.x - recordingRect.minX) / recordingRect.width
    let rawY = (location.y - recordingRect.minY) / recordingRect.height

    let sample = RecordedMouseSample(
      time: elapsedTime,
      normalizedX: rawX.clamped(to: 0...1),
      normalizedY: rawY.clamped(to: 0...1),
      isInsideCapture: recordingRect.contains(location)
    )

    if !force, let lastSample = samples.last {
      let minimumDelta = sampleInterval * 0.5
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

  private func currentElapsedTime() -> TimeInterval? {
    guard let startUptime else { return nil }

    let referenceUptime = pausedAtUptime ?? ProcessInfo.processInfo.systemUptime
    return max(0, referenceUptime - startUptime - accumulatedPausedDuration)
  }
}

private extension CGFloat {
  func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}
