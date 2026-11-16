//
//  AnnotateAgentAISettings.swift
//  Snapzy
//
//  Stored options of the Annotate AI prompt that Settings › AI, the config file
//  and the providers share.
//

import Foundation

nonisolated enum AnnotateAgentAISettings {
  static let defaultCLITimeout: TimeInterval = 180
  /// Accepted from the config file; Settings offers `cliTimeoutChoices`.
  static let cliTimeoutRange: ClosedRange<TimeInterval> = 30...1800
  static let cliTimeoutChoices: [TimeInterval] = [60, 120, 180, 300, 600, 900]

  /// Any positive stored value is honored (`defaults write` may go past the config range).
  static func cliTimeout(defaults: UserDefaults = .standard) -> TimeInterval {
    let value = defaults.double(forKey: PreferencesKeys.annotateAgentCLITimeout)
    return value > 0 ? value : defaultCLITimeout
  }

  static func sendsImage(defaults: UserDefaults = .standard) -> Bool {
    defaults.object(forKey: PreferencesKeys.annotateAgentSendImage) == nil
      || defaults.bool(forKey: PreferencesKeys.annotateAgentSendImage)
  }

  /// Providers the user already allowed to receive screenshots.
  static func consentedProviderCount(defaults: UserDefaults = .standard) -> Int {
    defaults.stringArray(forKey: PreferencesKeys.annotateAgentConsentedProviders)?.count ?? 0
  }

  /// Ask again before the next screenshot goes to any endpoint or CLI.
  static func resetConsents(defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: PreferencesKeys.annotateAgentConsentedProviders)
  }
}

@MainActor
extension AnnotateAgentAISettings {
  /// Preferences › AI.
  static func open() {
    // Capture Markup covers the screen above every window; it steps aside for Settings.
    NotificationCenter.default.post(name: .annotateAgentWillOpenSettings, object: nil)
    AppStatusBarController.shared.openPreferencesWindow(tab: .ai)
  }
}

extension Notification.Name {
  static let annotateAgentWillOpenSettings = Notification.Name("annotateAgentWillOpenSettings")
}
