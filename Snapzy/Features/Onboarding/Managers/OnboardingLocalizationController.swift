//
//  OnboardingLocalizationController.swift
//  Snapzy
//
//  Drives immediate in-flow localization updates for onboarding without an app relaunch.
//

import Combine
import Foundation

@MainActor
final class OnboardingLocalizationController: ObservableObject {
  @Published var selectedLanguageIdentifier: String

  private let languageManager: AppLanguageManager

  init(languageManager: AppLanguageManager? = nil) {
    let resolvedLanguageManager = languageManager ?? .shared
    self.languageManager = resolvedLanguageManager
    selectedLanguageIdentifier = resolvedLanguageManager.selectedLanguageIdentifier
  }

  var availableOptions: [AppLanguageOption] {
    languageManager.availableOptions
  }

  var systemResolvedIdentifier: String {
    languageManager.systemResolvedIdentifier
  }

  var systemResolvedOption: AppLanguageOption? {
    languageManager.systemResolvedOption
  }

  var effectiveLanguageIdentifier: String {
    languageManager.effectiveIdentifier(for: selectedLanguageIdentifier)
  }

  var requiresRelaunchOnCompletion: Bool {
    languageManager.requiresRelaunch(for: selectedLanguageIdentifier)
  }

  func selectLanguage(_ identifier: String) {
    selectedLanguageIdentifier = identifier
  }

  func commitLanguageSelection() {
    guard selectedLanguageIdentifier != languageManager.selectedLanguageIdentifier else { return }
    languageManager.selectLanguage(selectedLanguageIdentifier)
  }

  func relaunchApplication() async throws {
    try await languageManager.relaunchApplication()
  }

  func string(_ key: String, defaultValue: String, comment: String) -> String {
    L10n.string(
      key,
      defaultValue: defaultValue,
      localeIdentifier: effectiveLanguageIdentifier,
      comment: comment
    )
  }

  func format(
    _ key: String,
    defaultValue: String,
    comment: String,
    arguments: [CVarArg]
  ) -> String {
    let format = string(key, defaultValue: defaultValue, comment: comment)
    return String(
      format: format,
      locale: Locale(identifier: effectiveLanguageIdentifier),
      arguments: arguments
    )
  }
}
