//
//  VideoEditorCursorResolver.swift
//  Snapzy
//
//  Pure resolver for the Studio cursor layer: given recording (source) time, where the
//  cursor is, which image it shows, how visible it is, and which click effects are
//  running. Shared by the export compositor and the editor preview.
//

import CoreGraphics
import Foundation

nonisolated struct VideoEditorCursorFrame: Equatable, Sendable {
  struct Pulse: Equatable, Sendable {
    /// Normalized, top-left.
    var point: CGPoint
    /// 0 at mouse-down → 1 when the effect ends.
    var progress: CGFloat
  }

  /// Normalized cursor position, top-left origin.
  var position: CGPoint
  /// Captured image to draw; `nil` means the arrow fallback.
  var imageID: Int?
  var opacity: CGFloat
  var pulses: [Pulse]
  /// Points where a button is held down (ring effect).
  var held: [CGPoint]
  /// Instantaneous cursor velocity in normalized top-left units per second.
  var velocity: CGVector = .zero
}

nonisolated struct VideoEditorCursorResolver: Sendable {
  static let pulseDuration: TimeInterval = 0.45
  /// Largest smoothing time constant (smoothing = 1).
  static let maxSmoothingTau: TimeInterval = 0.12
  private static let movementEpsilon: CGFloat = 0.0005

  let settings: VideoEditorCursorSettings
  let capture: RecordingCursorCapture
  let samples: [RecordedMouseSample]
  /// Sorted times with movement or clicks (idle detection).
  private let activityTimes: [TimeInterval]

  /// Raw samples, kept so a smoothing change can re-smooth without the recording.
  private let rawSamples: [RecordedMouseSample]

  /// Shape changes shorter than this are treated as capture noise and skipped.
  static let minimumAppearanceDwell: TimeInterval = 0.1

  init(samples rawSamples: [RecordedMouseSample], capture: RecordingCursorCapture, settings: VideoEditorCursorSettings) {
    self.settings = settings
    var stabilized = capture
    stabilized.appearance = Self.stabilizedAppearance(capture.appearance)
    self.capture = stabilized
    self.rawSamples = rawSamples
    let smoothed = Self.smooth(rawSamples, tau: settings.smoothing * Self.maxSmoothingTau)
    samples = smoothed
    var activity: [TimeInterval] = []
    for index in rawSamples.indices.dropFirst() {
      let a = rawSamples[index - 1], b = rawSamples[index]
      if abs(a.normalizedX - b.normalizedX) > Self.movementEpsilon || abs(a.normalizedY - b.normalizedY) > Self.movementEpsilon {
        activity.append(b.time)
      }
    }
    if let first = rawSamples.first { activity.append(first.time) }
    activity.append(contentsOf: capture.clicks.map(\.time))
    activityTimes = activity.sorted()
  }

  private init(
    settings: VideoEditorCursorSettings,
    capture: RecordingCursorCapture,
    rawSamples: [RecordedMouseSample],
    samples: [RecordedMouseSample],
    activityTimes: [TimeInterval]
  ) {
    self.settings = settings
    self.capture = capture
    self.rawSamples = rawSamples
    self.samples = samples
    self.activityTimes = activityTimes
  }

  /// Drops visible cursor-shape changes that last under `minimumAppearanceDwell`, so the
  /// previous shape carries through. Recordings captured before the content-keyed cursor
  /// fix flip between a stale and the real shape every poll (~33 ms); real shape changes
  /// virtually never last that briefly. Hidden periods are always kept.
  static func stabilizedAppearance(_ appearance: [RecordedCursorChange]) -> [RecordedCursorChange] {
    guard appearance.count > 1 else { return appearance }
    var result: [RecordedCursorChange] = []
    result.reserveCapacity(appearance.count)
    for index in appearance.indices {
      let change = appearance[index]
      let isLast = index == appearance.count - 1
      let dwell = isLast ? .infinity : appearance[index + 1].time - change.time
      guard change.isHidden || dwell >= minimumAppearanceDwell || result.isEmpty else { continue }
      if let last = result.last, last.imageID == change.imageID, last.isHidden == change.isHidden {
        continue
      }
      result.append(change)
    }
    return result
  }

  /// The same recording with new settings. Activity times never depend on settings, and
  /// the smoothed path only on `smoothing`, so a slider tick on size, idle delay, click
  /// effect or volume reuses both instead of re-smoothing every mouse sample.
  func updating(settings newSettings: VideoEditorCursorSettings) -> VideoEditorCursorResolver {
    let smoothed = newSettings.smoothing == settings.smoothing
      ? samples
      : Self.smooth(rawSamples, tau: newSettings.smoothing * Self.maxSmoothingTau)
    return VideoEditorCursorResolver(
      settings: newSettings,
      capture: capture,
      rawSamples: rawSamples,
      samples: smoothed,
      activityTimes: activityTimes
    )
  }

  func resolve(sourceTime time: TimeInterval) -> VideoEditorCursorFrame? {
    guard settings.isVisible,
          let sample = RecordedMouseSampleInterpolator.sample(at: time, in: samples)
    else { return nil }

    var pulses: [VideoEditorCursorFrame.Pulse] = []
    var held: [CGPoint] = []
    if settings.clickEffect != .none {
      var openDowns: [RecordedClickButton: RecordedClick] = [:]
      for click in capture.clicks {
        if click.time > time { break }
        switch click.phase {
        case .down:
          openDowns[click.button] = click
          let age = time - click.time
          if settings.clickEffect == .ripple, age < Self.pulseDuration {
            pulses.append(.init(point: position(at: click.time), progress: CGFloat(age / Self.pulseDuration)))
          }
        case .up:
          openDowns[click.button] = nil
        }
      }
      if settings.clickEffect == .ring {
        held = openDowns.values.sorted { $0.time < $1.time }.map { _ in sample.normalizedPoint }
      }
    }

    let change = capture.appearance(at: time)
    let isHidden = change?.isHidden == true || !sample.isInsideCapture
    let opacity = isHidden ? 0 : idleOpacity(at: time)
    let imageID = settings.alwaysUseArrow ? nil : change?.imageID
    guard opacity > 0 || !pulses.isEmpty || !held.isEmpty else { return nil }
    let velocity = opacity > 0 ? velocity(at: time) : .zero
    return VideoEditorCursorFrame(
      position: sample.normalizedPoint,
      imageID: imageID,
      opacity: opacity,
      pulses: pulses,
      held: held,
      velocity: velocity
    )
  }

  private func velocity(at time: TimeInterval) -> CGVector {
    guard samples.count >= 2 else { return .zero }
    let halfWindow: TimeInterval = 0.008
    let t0 = max(samples[0].time, time - halfWindow)
    let t1 = min(samples[samples.count - 1].time, time + halfWindow)
    let dt = t1 - t0
    guard dt > 0.0005,
          let a = RecordedMouseSampleInterpolator.sample(at: t0, in: samples),
          let b = RecordedMouseSampleInterpolator.sample(at: t1, in: samples),
          a.isInsideCapture, b.isInsideCapture
    else { return .zero }
    return CGVector(
      dx: (b.normalizedX - a.normalizedX) / CGFloat(dt),
      dy: (b.normalizedY - a.normalizedY) / CGFloat(dt)
    )
  }

  private func position(at time: TimeInterval) -> CGPoint {
    RecordedMouseSampleInterpolator.sample(at: time, in: samples)?.normalizedPoint ?? .zero
  }

  /// 1 while active, fading to 0 over `idleFadeDuration` once idle for `idleDelay`.
  func idleOpacity(at time: TimeInterval) -> CGFloat {
    guard settings.hideWhenIdle, !activityTimes.isEmpty else { return 1 }
    var low = 0, high = activityTimes.count - 1
    guard activityTimes[0] <= time else { return 1 }
    while low < high {
      let mid = (low + high + 1) / 2
      if activityTimes[mid] <= time { low = mid } else { high = mid - 1 }
    }
    let idleFor = time - activityTimes[low] - settings.idleDelay
    guard idleFor > 0 else { return 1 }
    return CGFloat(max(0, 1 - idleFor / VideoEditorCursorSettings.idleFadeDuration))
  }

  /// Zero-lag smoothing: exponential filter forward, then backward.
  static func smooth(_ samples: [RecordedMouseSample], tau: TimeInterval) -> [RecordedMouseSample] {
    guard tau > 0.0001, samples.count > 2 else { return samples }
    var result = samples
    func alpha(_ dt: TimeInterval) -> CGFloat { CGFloat(1 - exp(-max(dt, 0) / tau)) }
    for index in result.indices.dropFirst() {
      let a = alpha(result[index].time - result[index - 1].time)
      result[index].normalizedX = result[index - 1].normalizedX + a * (result[index].normalizedX - result[index - 1].normalizedX)
      result[index].normalizedY = result[index - 1].normalizedY + a * (result[index].normalizedY - result[index - 1].normalizedY)
    }
    for index in result.indices.dropLast().reversed() {
      let a = alpha(result[index + 1].time - result[index].time)
      result[index].normalizedX = result[index + 1].normalizedX + a * (result[index].normalizedX - result[index + 1].normalizedX)
      result[index].normalizedY = result[index + 1].normalizedY + a * (result[index].normalizedY - result[index + 1].normalizedY)
    }
    return result
  }
}
