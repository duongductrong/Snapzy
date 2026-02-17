//
//  RecordingAnnotationShortcutConfig.swift
//  Snapzy
//
//  Configurable settings for annotation shortcut activation during recording
//  Modifier key + hold duration to activate tool-switching mode
//

import AppKit
import Combine
import Foundation

/// Modifier key options for activating annotation shortcut mode
enum AnnotationShortcutModifier: String, CaseIterable, Identifiable {
  case shift
  case control
  case option

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .shift: return "Shift (⇧)"
    case .control: return "Control (⌃)"
    case .option: return "Option (⌥)"
    }
  }

  var flag: NSEvent.ModifierFlags {
    switch self {
    case .shift: return .shift
    case .control: return .control
    case .option: return .option
    }
  }
}

/// Configuration for annotation shortcut activation
@MainActor
final class RecordingAnnotationShortcutConfig: ObservableObject {

  static let shared = RecordingAnnotationShortcutConfig()

  @Published var modifier: AnnotationShortcutModifier {
    didSet { save() }
  }

  @Published var holdDuration: TimeInterval {
    didSet { save() }
  }

  static let defaultModifier: AnnotationShortcutModifier = .shift
  static let defaultHoldDuration: TimeInterval = 0.3
  static let durationPresets: [TimeInterval] = [0.3, 0.5, 1.0, 1.5, 2.0]

  static let minHoldDuration: TimeInterval = 0.1
  static let maxHoldDuration: TimeInterval = 5.0

  private init() {
    let storedModifier = UserDefaults.standard.string(
      forKey: PreferencesKeys.annotationShortcutModifier
    )
    self.modifier = storedModifier.flatMap { AnnotationShortcutModifier(rawValue: $0) }
      ?? Self.defaultModifier

    let storedDuration = UserDefaults.standard.double(
      forKey: PreferencesKeys.annotationShortcutHoldDuration
    )
    let raw = storedDuration > 0 ? storedDuration : Self.defaultHoldDuration
    self.holdDuration = min(max(raw, Self.minHoldDuration), Self.maxHoldDuration)
  }

  private func save() {
    UserDefaults.standard.set(modifier.rawValue, forKey: PreferencesKeys.annotationShortcutModifier)
    UserDefaults.standard.set(holdDuration, forKey: PreferencesKeys.annotationShortcutHoldDuration)
  }

  func resetToDefaults() {
    modifier = Self.defaultModifier
    holdDuration = Self.defaultHoldDuration
  }
}
