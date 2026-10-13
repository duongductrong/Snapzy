//
//  CaptureDelay.swift
//  Snapzy
//
//  Delayed Capture (self-timer): the countdown length setting and the pure
//  countdown state machine driven by CaptureDelayCountdownController.
//

import Foundation

/// Countdown length for Delayed Capture, stored in seconds under
/// `PreferencesKeys.screenshotDelayedCaptureSeconds`.
enum CaptureDelayOption: Int, CaseIterable, Identifiable {
  case threeSeconds = 3
  case fiveSeconds = 5
  case tenSeconds = 10

  static let defaultValue: CaptureDelayOption = .threeSeconds

  var id: Int { rawValue }
  var seconds: Int { rawValue }

  var displayName: String {
    L10n.PreferencesCapture.delayedCaptureSeconds(seconds)
  }

  /// Unset or unknown stored values (hand-edited defaults) fall back to the default.
  static func resolve(_ seconds: Int) -> CaptureDelayOption {
    CaptureDelayOption(rawValue: seconds) ?? defaultValue
  }

  static func current(defaults: UserDefaults = .standard) -> CaptureDelayOption {
    resolve(defaults.integer(forKey: PreferencesKeys.screenshotDelayedCaptureSeconds))
  }
}

/// Whole-second countdown. `tick()` is called once per second and reports
/// when the capture should fire.
struct CaptureDelayCountdown: Equatable {
  private(set) var remainingSeconds: Int

  init(seconds: Int) {
    remainingSeconds = max(0, seconds)
  }

  var isFinished: Bool { remainingSeconds == 0 }

  /// Advance one second. Returns `true` exactly once, on the tick that
  /// reaches zero.
  mutating func tick() -> Bool {
    guard remainingSeconds > 0 else { return false }
    remainingSeconds -= 1
    return remainingSeconds == 0
  }
}
