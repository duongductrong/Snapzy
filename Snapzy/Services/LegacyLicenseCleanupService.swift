//
//  LegacyLicenseCleanupService.swift
//  Snapzy
//
//  Removes persisted license data left over from the retired Polar integration.
//

import Foundation
import Security

@MainActor
final class LegacyLicenseCleanupService {
  static let shared = LegacyLicenseCleanupService()

  private let defaults = UserDefaults.standard
  private let keychainService = "com.snapzy.license"
  private let defaultsKeys = [
    "com.snapzy.license.cache",
    "com.snapzy.license.key",
    "com.snapzy.telemetry.events",
    "polar_org_id",
    "device_limit",
  ]

  private init() {}

  func runIfNeeded() {
    guard !defaults.bool(forKey: PreferencesKeys.legacyLicenseCleanupCompleted) else { return }

    defaultsKeys.forEach { defaults.removeObject(forKey: $0) }
    deleteLegacyKeychainItems()
    defaults.set(true, forKey: PreferencesKeys.legacyLicenseCleanupCompleted)

    DiagnosticLogger.shared.log(.info, .system, "Cleared legacy license data")
  }

  private func deleteLegacyKeychainItems() {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: keychainService,
    ]

    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      DiagnosticLogger.shared.log(
        .warning,
        .system,
        "Legacy license keychain cleanup failed with status \(status)"
      )
      return
    }
  }
}
