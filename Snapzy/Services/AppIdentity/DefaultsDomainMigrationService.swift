//
//  DefaultsDomainMigrationService.swift
//  Snapzy
//
//  Migrates persisted defaults into the current bundle domain after bundle ID changes.
//

import Foundation

@MainActor
final class DefaultsDomainMigrationService {
  static let shared = DefaultsDomainMigrationService()

  private let defaults = UserDefaults.standard

  private init() {}

  func runIfNeeded() {
    guard Bundle.main.bundleIdentifier == AppBundleIdentity.expected else { return }
    guard !defaults.bool(forKey: PreferencesKeys.defaultsDomainMigrationCompleted) else { return }

    let targetDomain = AppBundleIdentity.expected
    var mergedDomain = defaults.persistentDomain(forName: targetDomain) ?? [:]
    var migratedKeyCount = 0

    for domain in AppBundleIdentity.legacyDomains {
      guard let sourceDomain = defaults.persistentDomain(forName: domain) else { continue }

      for (key, value) in sourceDomain where mergedDomain[key] == nil {
        mergedDomain[key] = value
        migratedKeyCount += 1
      }
    }

    mergedDomain[PreferencesKeys.defaultsDomainMigrationCompleted] = true
    defaults.setPersistentDomain(mergedDomain, forName: targetDomain)
    defaults.synchronize()

    if migratedKeyCount > 0 {
      DiagnosticLogger.shared.log(
        .info,
        .system,
        "Migrated \(migratedKeyCount) defaults key(s) into \(targetDomain)"
      )
    }
  }
}
