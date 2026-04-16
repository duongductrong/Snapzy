//
//  AppLanguageManager.swift
//  Snapzy
//
//  Manages the app-specific language override stored in AppleLanguages.
//

import AppKit
import Combine
import Foundation

struct AppLanguageOption: Identifiable, Hashable {
  let identifier: String
  let displayName: String
  let greeting: String

  var id: String { identifier }

  static let supported: [AppLanguageOption] = [
    AppLanguageOption(identifier: "en", displayName: "English", greeting: "Hello"),
    AppLanguageOption(identifier: "vi", displayName: "Tiếng Việt", greeting: "Xin chào"),
    AppLanguageOption(identifier: "zh-Hans", displayName: "简体中文", greeting: "欢迎"),
    AppLanguageOption(identifier: "zh-Hant", displayName: "繁體中文", greeting: "歡迎"),
    AppLanguageOption(identifier: "es", displayName: "Español", greeting: "Hola"),
    AppLanguageOption(identifier: "ja", displayName: "日本語", greeting: "ようこそ"),
    AppLanguageOption(identifier: "ko", displayName: "한국어", greeting: "안녕하세요"),
    AppLanguageOption(identifier: "ru", displayName: "Русский", greeting: "Привет"),
    AppLanguageOption(identifier: "fr", displayName: "Français", greeting: "Bonjour"),
    AppLanguageOption(identifier: "de", displayName: "Deutsch", greeting: "Hallo"),
  ]
}

@MainActor
final class AppLanguageManager: ObservableObject {
  static let shared = AppLanguageManager()

  @Published private(set) var selectedLanguageIdentifier: String

  let availableOptions: [AppLanguageOption]

  // Most app surfaces still resolve localized values through static lets, so a
  // relaunch is required before a new app language fully takes effect
  // everywhere. Onboarding uses a separate controller for in-flow previewing.
  var requiresRelaunch: Bool {
    requiresRelaunch(for: selectedLanguageIdentifier)
  }

  private let activeLanguageIdentifier: String

  private static let appleLanguagesKey = "AppleLanguages"

  private init() {
    let bundledLanguageIdentifiers = Set(Bundle.main.localizations)
    availableOptions = AppLanguageOption.supported.filter { bundledLanguageIdentifiers.contains($0.identifier) }

    let activeLanguageIdentifier = Self.currentOverrideIdentifier()
    self.activeLanguageIdentifier = activeLanguageIdentifier
    selectedLanguageIdentifier = activeLanguageIdentifier
  }

  func selectLanguage(_ identifier: String) {
    guard selectedLanguageIdentifier != identifier else { return }
    selectedLanguageIdentifier = identifier
    Self.persistOverride(identifier)
  }

  var systemResolvedIdentifier: String {
    Self.resolvedSystemIdentifier(availableOptions: availableOptions)
  }

  var systemResolvedOption: AppLanguageOption? {
    option(for: systemResolvedIdentifier)
  }

  var activeEffectiveLanguageIdentifier: String {
    effectiveIdentifier(for: activeLanguageIdentifier)
  }

  func effectiveIdentifier(for selection: String) -> String {
    Self.effectiveIdentifier(
      for: selection,
      systemResolvedIdentifier: systemResolvedIdentifier
    )
  }

  func requiresRelaunch(for selection: String) -> Bool {
    effectiveIdentifier(for: selection) != activeEffectiveLanguageIdentifier
  }

  func option(for identifier: String) -> AppLanguageOption? {
    availableOptions.first(where: { $0.identifier == identifier })
      ?? AppLanguageOption.supported.first(where: { $0.identifier == identifier })
  }

  func relaunchApplication() async throws {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.createsNewApplicationInstance = true

    _ = try await NSWorkspace.shared.openApplication(
      at: Bundle.main.bundleURL,
      configuration: configuration
    )

    NSApp.terminate(nil)
  }

  private static func currentOverrideIdentifier() -> String {
    guard
      let bundleIdentifier = Bundle.main.bundleIdentifier,
      let domain = UserDefaults.standard.persistentDomain(forName: bundleIdentifier),
      let overrideLanguages = domain[appleLanguagesKey] as? [String],
      let firstOverride = overrideLanguages.first,
      let normalizedIdentifier = normalizedIdentifier(from: firstOverride)
    else {
      return ""
    }

    return normalizedIdentifier
  }

  private static func persistOverride(_ identifier: String) {
    let defaults = UserDefaults.standard

    if identifier.isEmpty {
      defaults.removeObject(forKey: appleLanguagesKey)
    } else {
      defaults.set([identifier], forKey: appleLanguagesKey)
    }

    defaults.synchronize()
  }

  private static func normalizedIdentifier(from identifier: String) -> String? {
    let normalized = identifier.lowercased()

    if normalized.contains("hant") || normalized.hasPrefix("zh-tw") || normalized.hasPrefix("zh-hk") || normalized.hasPrefix("zh-mo") {
      return "zh-Hant"
    }

    if normalized.contains("hans") || normalized.hasPrefix("zh-cn") || normalized.hasPrefix("zh-sg") {
      return "zh-Hans"
    }

    let prefixMap: [(prefix: String, identifier: String)] = [
      ("en", "en"),
      ("vi", "vi"),
      ("es", "es"),
      ("ja", "ja"),
      ("ko", "ko"),
      ("ru", "ru"),
      ("fr", "fr"),
      ("de", "de"),
    ]

    for entry in prefixMap where normalized.hasPrefix(entry.prefix) {
      return entry.identifier
    }

    return nil
  }

  private static func resolvedSystemIdentifier(availableOptions: [AppLanguageOption]) -> String {
    let availableIdentifiers = availableOptions.map(\.identifier)
    let preferredIdentifiers = Bundle.preferredLocalizations(
      from: availableIdentifiers,
      forPreferences: Locale.preferredLanguages
    )

    if let preferredIdentifier = preferredIdentifiers.first,
       let normalizedIdentifier = normalizedIdentifier(from: preferredIdentifier) {
      return normalizedIdentifier
    }

    return "en"
  }

  private static func effectiveIdentifier(
    for selection: String,
    systemResolvedIdentifier: String
  ) -> String {
    if selection.isEmpty {
      return systemResolvedIdentifier
    }

    return normalizedIdentifier(from: selection) ?? systemResolvedIdentifier
  }
}
