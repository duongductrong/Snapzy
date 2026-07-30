//
//  CaptureHistoryPreferences.swift
//  Snapzy
//
//  Shared reader for the Capture History enabled flag.
//

import Foundation

extension UserDefaults {
  /// Whether Capture History is enabled.
  ///
  /// Single source of truth so every reader applies the same default (`true`,
  /// matching the launch-time default written by `AppCoordinator`). Reading via
  /// `bool(forKey:)` instead silently defaults to `false` when the key has
  /// never been written, which previously let dismiss cleanup delete temp
  /// captures that history preservation should have kept.
  var snapzyHistoryEnabled: Bool {
    (object(forKey: PreferencesKeys.historyEnabled) as? Bool) ?? true
  }
}
