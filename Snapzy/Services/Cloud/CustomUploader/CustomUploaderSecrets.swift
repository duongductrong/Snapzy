//
//  CustomUploaderSecrets.swift
//  Snapzy
//
//  Seam between custom uploaders and whatever stores secret values.
//  Uploader definitions only hold `{secret:NAME}` references; the values are
//  looked up here at request time and never logged or persisted with the uploader.
//

import Foundation

/// Looks up and stores named secrets for `{secret:NAME}` template tokens.
protocol CustomUploaderSecretResolving {
  /// The secret value for `name`, or nil when no such secret exists.
  func secretValue(named name: String) -> String?
  /// Creates or replaces the secret `name`.
  func storeSecret(name: String, value: String) throws
}

enum CustomUploaderSecrets {
  /// The app-wide secret store. Nil until a Keychain-backed store is installed; while nil,
  /// any `{secret:…}` token fails the upload and the UI hides "Store as secret".
  @MainActor static var provider: CustomUploaderSecretResolving?

  /// Secret names: letters, digits, `_`, `-`, `.`; 1–64 characters.
  nonisolated static func isValidName(_ name: String) -> Bool {
    guard (1...64).contains(name.count) else { return false }
    return name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == ".") }
  }

  /// Builds a secret name such as `ZIPLINE_AUTHORIZATION` from an uploader and field name.
  nonisolated static func suggestedName(uploaderName: String, fieldName: String) -> String {
    func sanitize(_ text: String) -> String {
      var result = ""
      var lastWasUnderscore = false
      for char in text.uppercased() {
        if char.isASCII && (char.isLetter || char.isNumber) {
          result.append(char)
          lastWasUnderscore = false
        } else if !lastWasUnderscore, !result.isEmpty {
          result.append("_")
          lastWasUnderscore = true
        }
      }
      while result.hasSuffix("_") { result.removeLast() }
      return result
    }
    let parts = [sanitize(uploaderName), sanitize(fieldName)].filter { !$0.isEmpty }
    let joined = parts.isEmpty ? "SECRET" : parts.joined(separator: "_")
    return String(joined.prefix(64))
  }

  /// A `{secret:NAME}` reference token.
  nonisolated static func reference(to name: String) -> String {
    "{secret:\(name)}"
  }
}
