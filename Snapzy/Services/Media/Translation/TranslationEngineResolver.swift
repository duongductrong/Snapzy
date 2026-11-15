//
//  TranslationEngineResolver.swift
//  Snapzy
//
//  Picks the translation engine for Snip to Translate.
//

import Foundation

/// Persisted engine choice. Same encoding as the OCR model selection:
/// `builtin` = Apple Translation, `custom:<uuid>` = custom endpoint.
typealias TranslationEngineSelection = OCRModelSelection

/// Where a translation runs.
enum TranslationRoute: Equatable {
  /// Apple Translation, on device (macOS 15+).
  case apple
  /// A user-configured OpenAI-compatible endpoint. Text leaves the device.
  case remote(CustomOCRModel)
  /// Nothing can translate right now.
  case unavailable(TranslationUnavailableReason)
}

enum TranslationUnavailableReason: Equatable {
  /// Apple Translation is selected but this macOS is older than 15.
  case requiresMacOS15
}

/// Resolves the persisted engine selection to a `TranslationRoute`.
///
/// Rules (plan 261115-0310):
/// - `builtin` → Apple on macOS 15+, otherwise `.unavailable(.requiresMacOS15)`.
/// - `custom:<id>` → that endpoint; a removed endpoint is canonicalized back to `builtin`.
/// - Never falls back from Apple to an endpoint on its own: text may only
///   leave the device after an explicit user action.
@MainActor
struct TranslationEngineResolver {
  private let defaults: UserDefaults
  private let isAppleTranslationSupported: Bool

  init(defaults: UserDefaults = .standard, isAppleTranslationSupported: Bool? = nil) {
    self.defaults = defaults
    self.isAppleTranslationSupported = isAppleTranslationSupported ?? Self.systemSupportsAppleTranslation
  }

  static var systemSupportsAppleTranslation: Bool {
    if #available(macOS 15.0, *) {
      return true
    }
    return false
  }

  func storedSelection() -> TranslationEngineSelection {
    guard let rawValue = defaults.string(forKey: PreferencesKeys.translateSelectedEngine) else {
      return .builtIn
    }
    return TranslationEngineSelection(persistedValue: rawValue)
  }

  func store(_ selection: TranslationEngineSelection) {
    defaults.set(selection.persistedValue, forKey: PreferencesKeys.translateSelectedEngine)
  }

  func resolve() -> TranslationRoute {
    switch storedSelection() {
    case .builtIn:
      return isAppleTranslationSupported ? .apple : .unavailable(.requiresMacOS15)
    case .custom(let id):
      if let model = customModels().first(where: { $0.id == id }) {
        return .remote(model)
      }
      store(.builtIn)
      DiagnosticLogger.shared.log(
        .warning,
        .ocr,
        "Translation endpoint missing; selection reset to Apple Translation",
        context: ["selection": TranslationEngineSelection.custom(id).persistedValue]
      )
      return isAppleTranslationSupported ? .apple : .unavailable(.requiresMacOS15)
    }
  }

  /// First configured endpoint, offered as an explicit one-off alternative
  /// when Apple Translation can't help. Never used automatically.
  func firstAvailableEndpoint() -> CustomOCRModel? {
    customModels().first
  }

  private func customModels() -> [CustomOCRModel] {
    guard let data = defaults.data(forKey: PreferencesKeys.ocrCustomModels) else { return [] }
    return (try? JSONDecoder().decode([CustomOCRModel].self, from: data)) ?? []
  }
}
