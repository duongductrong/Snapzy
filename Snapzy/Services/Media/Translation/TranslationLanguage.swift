//
//  TranslationLanguage.swift
//  Snapzy
//
//  Target languages offered by Snip to Translate.
//

import Foundation

/// A translation target, stored by its BCP-47 identifier (`ocr`-style raw ids
/// stay stable; display names are localized at the view layer).
struct TranslationLanguage: Hashable, Identifiable {
  let identifier: String

  var id: String { identifier }

  var localeLanguage: Locale.Language {
    Locale.Language(identifier: identifier)
  }

  /// Name in the app's current display language, e.g. "Vietnamese" / "Tiếng Việt".
  var displayName: String {
    let displayLocale = Locale(identifier: AppLanguageManager.shared.activeEffectiveLanguageIdentifier)
    return displayLocale.localizedString(forIdentifier: identifier)?.localizedCapitalized(with: displayLocale)
      ?? identifier
  }

  /// English name, used inside prompts sent to custom endpoints.
  var englishName: String {
    Locale(identifier: "en").localizedString(forIdentifier: identifier) ?? identifier
  }

  /// Languages supported by Apple Translation (macOS 15) — also offered for
  /// custom endpoints so one picker serves both engines.
  static let all: [TranslationLanguage] = [
    "ar", "de", "en", "es", "fr", "hi", "id", "it", "ja", "ko", "nl", "pl",
    "pt", "ru", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant",
  ].map(TranslationLanguage.init(identifier:))

  static func language(for identifier: String?) -> TranslationLanguage? {
    guard let identifier, !identifier.isEmpty else { return nil }
    return all.first { $0.identifier == identifier }
  }

  /// Persisted target, or nil when the user has not chosen one yet.
  static func storedTarget(defaults: UserDefaults = .standard) -> TranslationLanguage? {
    language(for: defaults.string(forKey: PreferencesKeys.translateTargetLanguage))
  }

  static func storeTarget(_ language: TranslationLanguage, defaults: UserDefaults = .standard) {
    defaults.set(language.identifier, forKey: PreferencesKeys.translateTargetLanguage)
  }
}

private extension String {
  func localizedCapitalized(with locale: Locale) -> String {
    guard let first else { return self }
    return String(first).uppercased(with: locale) + dropFirst()
  }
}
