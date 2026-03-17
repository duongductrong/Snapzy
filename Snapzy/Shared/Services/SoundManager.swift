//
//  SoundManager.swift
//  Snapzy
//
//  Centralized sound playback gated by the user's "Play Sounds" preference
//

import AppKit

/// Gates all sound playback on the `playSounds` user preference.
enum SoundManager {

  /// Play a named system sound only if the user hasn't disabled sounds.
  /// - Parameter name: System sound name (e.g. "Glass", "Pop", "Funk")
  static func play(_ name: String) {
    guard UserDefaults.standard.object(forKey: PreferencesKeys.playSounds) as? Bool ?? true else { return }
    NSSound(named: name)?.play()
  }
}
