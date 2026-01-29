//
//  QuickAccessSound.swift
//  ClaudeShot
//
//  Sound feedback for QuickAccess actions - CleanShot X inspired
//

import AppKit

/// Sound effects for QuickAccess interactions
enum QuickAccessSound {
  case appear
  case dismiss
  case copy
  case save
  case delete
  case complete
  case failed

  /// Play the sound effect
  /// - Parameter reduceMotion: When true, sounds are disabled for accessibility
  func play(reduceMotion: Bool = false) {
    guard !reduceMotion else { return }
    guard let sound = sound else { return }
    sound.volume = volume
    sound.play()
  }

  /// System sound for this action
  private var sound: NSSound? {
    switch self {
    case .appear:
      return NSSound(named: "Pop")
    case .dismiss:
      return NSSound(named: "Blow")
    case .copy:
      return NSSound(named: "Pop")
    case .save:
      return NSSound(named: "Pop")
    case .delete:
      return NSSound(named: "Funk")
    case .complete:
      return NSSound(named: "Glass")
    case .failed:
      return NSSound(named: "Basso")
    }
  }

  /// Volume level for this sound (0.0 - 1.0)
  private var volume: Float {
    switch self {
    case .appear:
      return 0.3
    case .dismiss:
      return 0.4
    case .copy:
      return 0.5
    case .save:
      return 0.4
    case .delete:
      return 0.3
    case .complete:
      return 0.3
    case .failed:
      return 0.4
    }
  }
}
