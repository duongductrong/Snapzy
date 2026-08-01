//
//  OCRModelSelection.swift
//  Snapzy
//
//  Persisted OCR model selection with stable string encoding.
//

import Foundation

/// Which OCR model the user selected in Settings.
enum OCRModelSelection: Equatable, Codable {
  /// Apple Vision OCR bundled with macOS — always available, and the fallback.
  case builtIn
  /// Downloadable PP-OCR model, identified by its catalog id (Phase 2).
  case downloadable(String)
  /// User-added custom endpoint, identified by its model UUID (Phase 4).
  case custom(UUID)

  // MARK: - String Persistence

  /// Stable string form stored in UserDefaults and the TOML configuration.
  var persistedValue: String {
    switch self {
    case .builtIn:
      return "builtin"
    case .downloadable(let id):
      return "dl:\(id)"
    case .custom(let id):
      return "custom:\(id.uuidString)"
    }
  }

  /// Unknown or corrupt values map to `.builtIn` so a bad write can never
  /// break OCR routing.
  init(persistedValue: String) {
    if persistedValue == "builtin" {
      self = .builtIn
    } else if persistedValue.hasPrefix("dl:") {
      let id = String(persistedValue.dropFirst(3))
      self = id.isEmpty ? .builtIn : .downloadable(id)
    } else if persistedValue.hasPrefix("custom:"),
              let id = UUID(uuidString: String(persistedValue.dropFirst(7))) {
      self = .custom(id)
    } else {
      self = .builtIn
    }
  }

  // MARK: - Codable

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(persistedValue: try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(persistedValue)
  }
}
