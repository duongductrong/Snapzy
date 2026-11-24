//
//  CaptureToolbarConfigurationStore.swift
//  Snapzy
//
//  Persists the capture toolbar configuration (UserDefaults JSON, TOML
//  `[capture.toolbar]`).
//

import Combine
import Foundation

@MainActor
final class CaptureToolbarConfigurationStore: ObservableObject {
  static let shared = CaptureToolbarConfigurationStore()

  @Published private(set) var configuration: CaptureToolbarConfiguration

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: PreferencesKeys.captureToolbarConfiguration),
       let decoded = try? JSONDecoder().decode(CaptureToolbarConfiguration.self, from: data)
    {
      configuration = decoded
    } else {
      configuration = .default
    }
  }

  func update(_ configuration: CaptureToolbarConfiguration) {
    let normalized = configuration.normalized()
    guard normalized != self.configuration else { return }
    self.configuration = normalized
    do {
      defaults.set(try JSONEncoder().encode(normalized), forKey: PreferencesKeys.captureToolbarConfiguration)
    } catch {
      DiagnosticLogger.shared.logError(.preferences, error, "Capture toolbar configuration save failed")
    }
  }

  func reset() {
    update(.default)
  }

  /// Automations offered as toolbar buttons: enabled, reviewed, with the
  /// "Capture toolbar" trigger, and able to work on a still image.
  static func toolbarAutomations(_ store: AutomationStore = .shared) -> [Automation] {
    store.automations.filter { automation in
      automation.isEnabled && !automation.needsReview && !automation.hasUnsupportedSource
        && automation.showsInCaptureToolbar && automation.acceptsFile(of: .image)
    }
  }
}
