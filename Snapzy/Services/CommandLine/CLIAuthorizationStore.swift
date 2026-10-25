//
//  CLIAuthorizationStore.swift
//  Snapzy
//
//  Which apps may use the `snapzy` command. Machine-specific, so it lives in
//  UserDefaults only and is never exported to config.toml.
//

import Combine
import Foundation

struct CLIApprovedCaller: Codable, Equatable, Identifiable {
  enum Decision: String, Codable {
    case allow
    case deny
  }

  let key: String
  var displayName: String
  var bundleID: String?
  var teamID: String?
  var path: String
  var decision: Decision
  let createdAt: Date
  var lastUsedAt: Date

  var id: String {
    key
  }
}

@MainActor
final class CLIAuthorizationStore: ObservableObject {
  static let shared = CLIAuthorizationStore(defaults: .standard)

  /// Most recently used first.
  @Published private(set) var callers: [CLIApprovedCaller] = []

  private let defaults: UserDefaults

  init(defaults: UserDefaults) {
    self.defaults = defaults
    callers = Self.load(from: defaults)
  }

  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  deinit {}

  func decision(for key: String) -> CLIApprovedCaller.Decision? {
    callers.first { $0.key == key }?.decision
  }

  func record(_ identity: CLICallerIdentity, decision: CLIApprovedCaller.Decision, now: Date = Date()) {
    if let index = callers.firstIndex(where: { $0.key == identity.key }) {
      callers[index].decision = decision
      callers[index].displayName = identity.displayName
      callers[index].path = identity.path
      callers[index].lastUsedAt = now
    } else {
      callers.append(CLIApprovedCaller(
        key: identity.key,
        displayName: identity.displayName,
        bundleID: identity.bundleID,
        teamID: identity.teamID,
        path: identity.path,
        decision: decision,
        createdAt: now,
        lastUsedAt: now
      ))
    }
    save()
  }

  func touch(_ key: String, now: Date = Date()) {
    guard let index = callers.firstIndex(where: { $0.key == key }) else { return }
    callers[index].lastUsedAt = now
    save()
  }

  func revoke(key: String) {
    callers.removeAll { $0.key == key }
    save()
  }

  func revokeAll() {
    callers.removeAll()
    save()
  }

  private func save() {
    callers.sort { $0.lastUsedAt > $1.lastUsedAt }
    if let data = try? JSONEncoder().encode(callers) {
      defaults.set(data, forKey: PreferencesKeys.cliApprovedCallers)
    }
  }

  private static func load(from defaults: UserDefaults) -> [CLIApprovedCaller] {
    guard
      let data = defaults.data(forKey: PreferencesKeys.cliApprovedCallers),
      let callers = try? JSONDecoder().decode([CLIApprovedCaller].self, from: data)
    else { return [] }
    return callers.sorted { $0.lastUsedAt > $1.lastUsedAt }
  }
}
