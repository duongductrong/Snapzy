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

struct CloudKeychainStore {
  private struct Location {
    let service: String
    let account: String
    let usesDataProtection: Bool
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
    case .authRequired, .interactionNotAllowed, .error:
      return primaryOutcome
    }

    for legacyLocation in legacyLocations(for: item) {
      let legacyOutcome = readValue(at: legacyLocation)
      switch legacyOutcome {
      case .success(let value):
        migrateLegacyValue(value, item: item, from: legacyLocation, context: context)
        return .success(value)
      case .itemNotFound:
        continue
      case .authRequired, .interactionNotAllowed, .error:
        return legacyOutcome
      }
    }

    return .itemNotFound
  }

  static func upsert(item: CloudKeychainItem, value: String) throws {
    guard let data = value.data(using: .utf8) else {
      throw CloudError.keychainError("Failed to encode keychain value")
    }

    let location = Location(
      service: currentService,
      account: item.account,
      usesDataProtection: true
    )
    let matchQuery = baseQuery(for: location)
    let updateAttributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
    ]

    let updateStatus = SecItemUpdate(matchQuery as CFDictionary, updateAttributes as CFDictionary)
    if updateStatus == errSecSuccess {
      return
    }
    guard updateStatus == errSecItemNotFound else {
      throw CloudError.keychainError("SecItemUpdate failed: \(updateStatus)")
    }

    var addQuery = matchQuery
    addQuery[kSecValueData as String] = data
    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw CloudError.keychainError("SecItemAdd failed: \(addStatus)")
    }
  }

  static func delete(item: CloudKeychainItem) {
    let primaryLocation = Location(
      service: currentService,
      account: item.account,
      usesDataProtection: true
    )
    deleteValue(at: primaryLocation)

    for legacyLocation in legacyLocations(for: item) {
      deleteValue(at: legacyLocation)
    }
  }

  private static func migrateLegacyValue(
    _ value: String,
    item: CloudKeychainItem,
    from location: Location,
    context: String
  ) {
    do {
      try upsert(item: item, value: value)
      deleteValue(at: location)
      logger.info("Migrated legacy keychain item for \(context, privacy: .public)")
    } catch {
      logger.error("Legacy keychain migration failed for \(context, privacy: .public): \(error.localizedDescription)")
    }
  }

  private static func legacyLocations(for item: CloudKeychainItem) -> [Location] {
    var locations = [
      Location(service: currentService, account: item.account, usesDataProtection: false)
    ]

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
}
