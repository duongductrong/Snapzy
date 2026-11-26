//
//  AutomationSecretStore.swift
//  Snapzy
//
//  Named secrets for webhooks and custom uploaders (`{secret:NAME}`). Names
//  and their Keychain accounts are indexed in UserDefaults; values live only in
//  the Keychain (service `com.trongduong.snapzy.automations`). Values are
//  write-only in the UI, never exported to TOML, never logged: run logs and
//  errors pass through `mask(_:)`.
//

import Combine
import Foundation

enum AutomationSecretError: LocalizedError, Equatable {
  case invalidName
  case duplicateName
  case emptyValue
  case limitReached
  case notFound(String)

  var errorDescription: String? {
    switch self {
    case .invalidName: L10n.Automations.secretErrorInvalidName
    case .duplicateName: L10n.Automations.secretErrorDuplicate
    case .emptyValue: L10n.Automations.secretErrorEmptyValue
    case .limitReached: L10n.Automations.secretErrorLimit(AutomationSecretStore.maxSecrets)
    case .notFound(let name): L10n.Automations.secretErrorNotFound(name)
    }
  }
}

@MainActor
final class AutomationSecretStore: ObservableObject {
  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  static let shared = AutomationSecretStore(
    defaults: .standard,
    keychain: KeychainPasswordStore(service: "com.trongduong.snapzy.automations")
  )

  static let maxNameLength = 64
  static let maxSecrets = 50
  /// Shown in place of a secret value.
  static let maskText = "••••"

  struct Entry: Codable, Equatable, Identifiable, Sendable {
    var name: String
    /// Keychain account.
    let id: UUID
  }

  @Published private(set) var entries: [Entry] = []

  private let defaults: UserDefaults
  private let keychain: KeychainPasswordStoring

  init(defaults: UserDefaults, keychain: KeychainPasswordStoring) {
    self.defaults = defaults
    self.keychain = keychain
    if let data = defaults.data(forKey: PreferencesKeys.automationSecrets),
       let decoded = try? JSONDecoder().decode([Entry].self, from: data)
    {
      entries = decoded
    }
  }

  var names: [String] { entries.map(\.name) }

  static func isValidName(_ name: String) -> Bool {
    guard !name.isEmpty, name.count <= maxNameLength else { return false }
    return name.unicodeScalars.allSatisfy { scalar in
      (scalar.isASCII && CharacterSet.alphanumerics.contains(scalar)) || "_-.".unicodeScalars.contains(scalar)
    }
  }

  func contains(_ name: String) -> Bool {
    entry(named: name) != nil
  }

  func value(for name: String) -> String? {
    entry(named: name).flatMap { keychain.read(account: $0.id.uuidString) }
  }

  /// Adds a secret or replaces the value of an existing one.
  func set(name rawName: String, value: String) throws {
    let name = rawName.trimmingCharacters(in: .whitespaces)
    guard Self.isValidName(name) else { throw AutomationSecretError.invalidName }
    guard !value.isEmpty else { throw AutomationSecretError.emptyValue }
    if let existing = entry(named: name) {
      try keychain.save(value, account: existing.id.uuidString)
      return
    }
    guard entries.count < Self.maxSecrets else { throw AutomationSecretError.limitReached }
    let entry = Entry(name: name, id: UUID())
    try keychain.save(value, account: entry.id.uuidString)
    entries.append(entry)
    entries.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    persist()
  }

  func rename(_ oldName: String, to rawName: String) throws {
    let name = rawName.trimmingCharacters(in: .whitespaces)
    guard Self.isValidName(name) else { throw AutomationSecretError.invalidName }
    guard let index = entries.firstIndex(where: { $0.name == oldName }) else {
      throw AutomationSecretError.notFound(oldName)
    }
    guard name == oldName || !contains(name) else { throw AutomationSecretError.duplicateName }
    entries[index].name = name
    persist()
  }

  func delete(name: String) {
    guard let entry = entry(named: name) else { return }
    keychain.delete(account: entry.id.uuidString)
    entries.removeAll { $0.id == entry.id }
    persist()
  }

  private func entry(named name: String) -> Entry? {
    entries.first { $0.name == name }
  }

  private func persist() {
    if let data = try? JSONEncoder().encode(entries) {
      defaults.set(data, forKey: PreferencesKeys.automationSecrets)
    }
  }

  // MARK: - Templates

  /// `{secret:NAME}` references in `template`, in order of appearance.
  nonisolated static func references(in template: String) -> [String] {
    var names: [String] = []
    var rest = Substring(template)
    while let start = rest.range(of: "{secret:") {
      let after = rest[start.upperBound...]
      guard let close = after.firstIndex(of: "}") else { break }
      let name = String(after[..<close])
      if !name.isEmpty, !names.contains(name) { names.append(name) }
      rest = after[after.index(after: close)...]
    }
    return names
  }

  /// Replaces every `{secret:NAME}` in `template` through `resolve`; throws for
  /// the first one that has no value. Values are inserted with `escape`.
  nonisolated static func resolve(
    _ template: String,
    escape: AutomationEscape = .none,
    resolve: (String) -> String?
  ) throws -> (text: String, values: [String]) {
    var text = template
    var values: [String] = []
    for name in references(in: template) {
      guard let value = resolve(name) else { throw AutomationSecretError.notFound(name) }
      values.append(value)
      text = text.replacingOccurrences(of: "{secret:\(name)}", with: AutomationVariables.escaped(value, mode: escape))
    }
    return (text, values)
  }

  /// `text` with every secret value replaced by `maskText`. Longest values
  /// first so a value containing another is masked whole.
  nonisolated static func mask(_ text: String, values: some Collection<String>) -> String {
    var masked = text
    for value in values.filter({ $0.count >= 3 }).sorted(by: { $0.count > $1.count }) {
      masked = masked.replacingOccurrences(of: value, with: maskText)
    }
    return masked
  }
}

// MARK: - Custom uploaders

/// Custom uploaders (Settings → Cloud) resolve `{secret:NAME}` through the same store.
extension AutomationSecretStore: CustomUploaderSecretResolving {
  func secretValue(named name: String) -> String? {
    value(for: name)
  }

  func storeSecret(name: String, value: String) throws {
    try set(name: name, value: value)
  }
}
