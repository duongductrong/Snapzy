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

  var id: String { identifier }
}

@MainActor
final class AppLanguageManager: ObservableObject {
  static let shared = AppLanguageManager()

  @Published private(set) var selectedLanguageIdentifier: String

  let availableOptions: [AppLanguageOption]

  // L10n.swift resolves localized values through static lets, so a relaunch is
  // required before the new app language can fully take effect everywhere.
  var requiresRelaunch: Bool {
    selectedLanguageIdentifier != activeLanguageIdentifier
  }

  private let activeLanguageIdentifier: String

  private static let appleLanguagesKey = "AppleLanguages"
  private static let supportedOptions: [AppLanguageOption] = [
    AppLanguageOption(identifier: "en", displayName: "English"),
    AppLanguageOption(identifier: "vi", displayName: "Tiếng Việt"),
    AppLanguageOption(identifier: "zh-Hans", displayName: "简体中文"),
    AppLanguageOption(identifier: "zh-Hant", displayName: "繁體中文"),
    AppLanguageOption(identifier: "es", displayName: "Español"),
    AppLanguageOption(identifier: "ja", displayName: "日本語"),
    AppLanguageOption(identifier: "ko", displayName: "한국어"),
    AppLanguageOption(identifier: "ru", displayName: "Русский"),
    AppLanguageOption(identifier: "fr", displayName: "Français"),
    AppLanguageOption(identifier: "de", displayName: "Deutsch"),
  ]

  private init() {
    let bundledLanguageIdentifiers = Set(Bundle.main.localizations)
    availableOptions = Self.supportedOptions.filter { bundledLanguageIdentifiers.contains($0.identifier) }

    let activeLanguageIdentifier = Self.currentOverrideIdentifier()
    self.activeLanguageIdentifier = activeLanguageIdentifier
    selectedLanguageIdentifier = activeLanguageIdentifier
  }

  func selectLanguage(_ identifier: String) {
    guard selectedLanguageIdentifier != identifier else { return }
    selectedLanguageIdentifier = identifier
    Self.persistOverride(identifier)
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
}
