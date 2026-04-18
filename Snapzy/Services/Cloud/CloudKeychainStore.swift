//
//  CloudKeychainStore.swift
//  Snapzy
//
//  Shared local-only keychain access for cloud secrets and password hash.
//

import Foundation
import Security
import os.log

enum CloudKeychainItem {
  case accessKey
  case secretKey
  case passwordHash

  var account: String {
    switch self {
    case .accessKey:
      return "com.trongduong.snapzy.cloud.accessKey"
    case .secretKey:
      return "com.trongduong.snapzy.cloud.secretKey"
    case .passwordHash:
      return "com.trongduong.snapzy.cloud.passwordHash"
    }
  }

  var legacyAccounts: [String] {
    switch self {
    case .accessKey:
      return ["com.snapzy.cloud.accessKey"]
    case .secretKey:
      return ["com.snapzy.cloud.secretKey"]
    case .passwordHash:
      return []
    }
  }
}

enum CloudKeychainReadOutcome {
  case success(String)
  case itemNotFound
  case authRequired(OSStatus)
  case interactionNotAllowed
  case error(OSStatus)
}

struct CloudKeychainDeleteIssue {
  let locationDescription: String
  let status: OSStatus
}

struct CloudKeychainStore {
  private struct Location: Equatable {
    let service: String
    let account: String
    let usesDataProtection: Bool

    var description: String {
      "\(service):\(account):\(usesDataProtection ? "dp" : "legacy")"
    }
  }

  private enum UpsertAttemptResult {
    case success
    case updateFailed(OSStatus)
    case addFailed(OSStatus)
  }

  private static let logger = Logger(subsystem: "Snapzy", category: "CloudKeychainStore")
  private static let currentService = "com.trongduong.snapzy.cloud"
  private static let legacyService = "com.snapzy.cloud"

  static func read(item: CloudKeychainItem, context: String) -> CloudKeychainReadOutcome {
    let primaryLocation = Location(
      service: currentService,
      account: item.account,
      usesDataProtection: true
    )
    let primaryOutcome = readValue(at: primaryLocation)

    switch primaryOutcome {
    case .success(let value):
      return .success(value)
    case .itemNotFound:
      break
    case .error(let status) where status == errSecMissingEntitlement:
      logger.notice(
        "Data-protection keychain unavailable (\(status, privacy: .public)); falling back [\(context, privacy: .public)]"
      )
      break
    case .authRequired, .interactionNotAllowed, .error:
      return primaryOutcome
    }

    for legacyLocation in legacyLocations(for: item) {
      let legacyOutcome = readValue(at: legacyLocation)
      switch legacyOutcome {
      case .success(let value):
        if shouldMigrateLegacyValue(
          from: legacyLocation,
          item: item,
          primaryOutcome: primaryOutcome
        ) {
          migrateLegacyValue(value, item: item, from: legacyLocation, context: context)
        }
        return .success(value)
      case .itemNotFound:
        continue
      case .authRequired, .interactionNotAllowed, .error:
        return legacyOutcome
      }
    }

    return .itemNotFound
  }

  @discardableResult
  static func upsert(item: CloudKeychainItem, value: String) throws -> String {
    guard let data = value.data(using: .utf8) else {
      throw CloudError.keychainError(L10n.CloudOperation.failedToEncodeKeychainValue)
    }

    let dataProtectionLocation = Location(
      service: currentService,
      account: item.account,
      usesDataProtection: true
    )
    let primaryAttempt = upsertValue(data, at: dataProtectionLocation)
    switch primaryAttempt {
    case .success:
      cleanupLegacyLocations(for: item)
      return dataProtectionLocation.description
    case .updateFailed(let status), .addFailed(let status):
      guard status == errSecMissingEntitlement else {
        throw keychainError(for: primaryAttempt)
      }
    }

    let fileBasedLocation = Location(
      service: currentService,
      account: item.account,
      usesDataProtection: false
    )
    let fallbackAttempt = upsertValue(data, at: fileBasedLocation)
    switch fallbackAttempt {
    case .success:
      logger.notice(
        "Stored cloud secret in file-based keychain due missing entitlement [\(item.account, privacy: .public)]"
      )
      cleanupLegacyLocations(for: item, excluding: fileBasedLocation)
      return fileBasedLocation.description
    case .updateFailed, .addFailed:
      throw keychainError(for: fallbackAttempt)
    }
  }

  @discardableResult
  static func delete(item: CloudKeychainItem) -> [CloudKeychainDeleteIssue] {
    var issues: [CloudKeychainDeleteIssue] = []
    let primaryLocation = Location(
      service: currentService,
      account: item.account,
      usesDataProtection: true
    )
    collectDeleteIssue(at: primaryLocation, into: &issues)

    for legacyLocation in legacyLocations(for: item) {
      collectDeleteIssue(at: legacyLocation, into: &issues)
    }
    return issues
  }

  private static func migrateLegacyValue(
    _ value: String,
    item: CloudKeychainItem,
    from location: Location,
    context: String
  ) {
    do {
      let storedLocationDescription = try upsert(item: item, value: value)
      guard storedLocationDescription != location.description else { return }
      deleteValue(at: location)
      logger.info("Migrated legacy keychain item for \(context, privacy: .public)")
    } catch {
      logger.error("Legacy keychain migration failed for \(context, privacy: .public): \(error.localizedDescription)")
    }
  }

  private static func shouldMigrateLegacyValue(
    from location: Location,
    item: CloudKeychainItem,
    primaryOutcome: CloudKeychainReadOutcome
  ) -> Bool {
    guard case .error(let status) = primaryOutcome, status == errSecMissingEntitlement else {
      return true
    }

    return !(location.service == currentService && location.account == item.account)
  }

  private static func legacyLocations(for item: CloudKeychainItem) -> [Location] {
    var locations = [
      Location(service: currentService, account: item.account, usesDataProtection: false)
    ]

    // Legacy service + legacy account names
    for account in item.legacyAccounts {
      locations.append(Location(service: legacyService, account: account, usesDataProtection: false))
    }

    return locations
  }

  private static func readValue(at location: Location) -> CloudKeychainReadOutcome {
    var query = baseQuery(for: location)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    switch status {
    case errSecSuccess:
      guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
        return .error(errSecDecode)
      }
      return .success(value)
    case errSecItemNotFound:
      return .itemNotFound
    case errSecAuthFailed, errSecUserCanceled:
      return .authRequired(status)
    case errSecInteractionNotAllowed:
      return .interactionNotAllowed
    default:
      return .error(status)
    }
  }

  private static func deleteValue(at location: Location) {
    let query = baseQuery(for: location)
    SecItemDelete(query as CFDictionary)
  }

  private static func cleanupLegacyLocations(
    for item: CloudKeychainItem,
    excluding preservedLocation: Location? = nil
  ) {
    for location in legacyLocations(for: item) {
      guard location != preservedLocation else { continue }
      let status = SecItemDelete(baseQuery(for: location) as CFDictionary)
      guard status != errSecSuccess, status != errSecItemNotFound else { continue }
      logger.error(
        "Legacy cleanup failed at \(location.description, privacy: .public): \(status, privacy: .public)"
      )
    }
  }

  private static func collectDeleteIssue(
    at location: Location,
    into issues: inout [CloudKeychainDeleteIssue]
  ) {
    let status = SecItemDelete(baseQuery(for: location) as CFDictionary)
    guard !(location.usesDataProtection && status == errSecMissingEntitlement) else { return }
    guard status != errSecSuccess, status != errSecItemNotFound else { return }
    issues.append(
      CloudKeychainDeleteIssue(
        locationDescription: location.description,
        status: status
      )
    )
  }

  private static func baseQuery(for location: Location) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: location.account,
      kSecAttrService as String: location.service,
    ]

    if location.usesDataProtection {
      query[kSecUseDataProtectionKeychain as String] = true
    }

    return query
  }

  private static func upsertValue(_ data: Data, at location: Location) -> UpsertAttemptResult {
    let matchQuery = baseQuery(for: location)
    let updateStatus = SecItemUpdate(
      matchQuery as CFDictionary,
      updateAttributes(for: location, data: data) as CFDictionary
    )
    if updateStatus == errSecSuccess {
      return .success
    }
    guard updateStatus == errSecItemNotFound else {
      return .updateFailed(updateStatus)
    }

    var addQuery = matchQuery
    addAttributes(for: location, data: data).forEach { addQuery[$0.key] = $0.value }

    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      return .addFailed(addStatus)
    }
    return .success
  }

  private static func updateAttributes(for location: Location, data: Data) -> [String: Any] {
    var attributes: [String: Any] = [
      kSecValueData as String: data
    ]
    if location.usesDataProtection {
      attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
    }
    return attributes
  }

  private static func addAttributes(for location: Location, data: Data) -> [String: Any] {
    var attributes = updateAttributes(for: location, data: data)
    attributes[kSecValueData as String] = data
    return attributes
  }

  private static func keychainError(for result: UpsertAttemptResult) -> CloudError {
    switch result {
    case .success:
      return CloudError.keychainError(L10n.CloudOperation.secItemAddFailed(Int(errSecInternalError)))
    case .updateFailed(let status):
      return CloudError.keychainError(L10n.CloudOperation.secItemUpdateFailed(Int(status)))
    case .addFailed(let status):
      return CloudError.keychainError(L10n.CloudOperation.secItemAddFailed(Int(status)))
    }
  }
}
