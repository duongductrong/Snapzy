//
//  TranslationEngineResolver.swift
//  Snapzy
//
//  Picks the translation engine for Snip to Translate.
//

import Foundation

/// Persisted engine choice: `builtin` = Apple Translation, `custom:<uuid>` = custom
/// endpoint (shared with OCR), `cli:<kind>` = an agent CLI set up in Settings › AI.
enum TranslationEngineSelection: Hashable {
  case builtIn
  case custom(UUID)
  case agentCLI(AnnotateAgentCLIKind)

  private static let customPrefix = "custom:"
  private static let cliPrefix = "cli:"

  var persistedValue: String {
    switch self {
    case .builtIn: "builtin"
    case .custom(let id): Self.customPrefix + id.uuidString
    case .agentCLI(let kind): Self.cliPrefix + kind.rawValue
    }
  }

  /// Unknown or corrupt values read as `.builtIn`, so a bad write can't break translation.
  init(persistedValue: String) {
    if persistedValue.hasPrefix(Self.customPrefix),
       let id = UUID(uuidString: String(persistedValue.dropFirst(Self.customPrefix.count))) {
      self = .custom(id)
    } else if persistedValue.hasPrefix(Self.cliPrefix),
              let kind = AnnotateAgentCLIKind(rawValue: String(persistedValue.dropFirst(Self.cliPrefix.count))) {
      self = .agentCLI(kind)
    } else {
      self = .builtIn
    }
  }
}

/// An engine that sends the text off this Mac.
enum RemoteTranslationEngine: Equatable {
  /// A user-configured OpenAI-compatible endpoint.
  case endpoint(CustomOCRModel)
  /// An agent CLI (Claude Code, Codex, OpenCode) run headless with no tools; the
  /// text goes to whatever model provider the CLI is signed in to.
  case agentCLI(AnnotateAgentCLIKind)

  var displayName: String {
    switch self {
    case .endpoint(let model): model.name
    case .agentCLI(let kind): kind.displayName
    }
  }

  /// Short engine name for logs.
  var logName: String {
    switch self {
    case .endpoint: "remote"
    case .agentCLI(let kind): "cli:\(kind.rawValue)"
    }
  }
}

/// Where a translation runs.
enum TranslationRoute: Equatable {
  /// Apple Translation, on device (macOS 15+).
  case apple
  /// A custom endpoint or an agent CLI. Text leaves the device.
  case remote(RemoteTranslationEngine)
  /// Nothing can translate right now.
  case unavailable(TranslationUnavailableReason)
}

enum TranslationUnavailableReason: Equatable {
  /// Apple Translation is selected but this macOS is older than 15.
  case requiresMacOS15
}

/// Resolves the persisted engine selection to a `TranslationRoute`.
///
/// Rules (plan 261115-0310, 261128 agent CLIs):
/// - `builtin` → Apple on macOS 15+, otherwise `.unavailable(.requiresMacOS15)`.
/// - `custom:<id>` → that endpoint; a removed endpoint is canonicalized back to `builtin`.
/// - `cli:<kind>` → that agent CLI. Whether it is installed is checked when it runs
///   (locating it can take seconds), so a missing CLI fails with a setup message.
/// - Never falls back from Apple to a remote engine on its own: text may only
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
      return appleRoute
    case .agentCLI(let kind):
      return .remote(.agentCLI(kind))
    case .custom(let id):
      if let model = customModels().first(where: { $0.id == id }) {
        return .remote(.endpoint(model))
      }
      store(.builtIn)
      DiagnosticLogger.shared.log(
        .warning,
        .ocr,
        "Translation endpoint missing; selection reset to Apple Translation",
        context: ["selection": TranslationEngineSelection.custom(id).persistedValue]
      )
      return appleRoute
    }
  }

  private var appleRoute: TranslationRoute {
    isAppleTranslationSupported ? .apple : .unavailable(.requiresMacOS15)
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
