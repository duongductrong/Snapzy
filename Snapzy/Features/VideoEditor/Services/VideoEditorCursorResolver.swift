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

  init(samples rawSamples: [RecordedMouseSample], capture: RecordingCursorCapture, settings: VideoEditorCursorSettings) {
    self.settings = settings
    self.capture = capture
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
    return VideoEditorCursorFrame(
      position: sample.normalizedPoint,
      imageID: imageID,
      opacity: opacity,
      pulses: pulses,
      held: held
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
