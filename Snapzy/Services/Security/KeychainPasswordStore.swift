//
//  KeychainPasswordStore.swift
//  Snapzy
//
//  Generic-password items under one Keychain service, keyed by account.
//  Same policy as `OCRKeychainStore` / `CloudKeychainStore`: the
//  data-protection keychain (`kSecAttrAccessibleWhenUnlocked`) first, the
//  file-based keychain as a fallback for unsigned dev builds that lack the
//  entitlement.
//

import Foundation
import Security

/// Storage seam so stores built on the Keychain can be tested in memory.
nonisolated protocol KeychainPasswordStoring: Sendable {
  func read(account: String) -> String?
  func save(_ value: String, account: String) throws
  func delete(account: String)
}

nonisolated enum KeychainPasswordError: LocalizedError, Equatable {
  case encodingFailed
  case saveFailed(OSStatus)

  var errorDescription: String? {
    switch self {
    case .encodingFailed:
      return "Failed to encode the value for Keychain storage"
    case .saveFailed(let status):
      return "Failed to save the value to the Keychain (error \(status))"
    }
  }
}

nonisolated struct KeychainPasswordStore: KeychainPasswordStoring {
  let service: String

  init(service: String) {
    self.service = service
  }

  func read(account: String) -> String? {
    for usesDataProtection in [true, false] {
      var query = baseQuery(account: account, usesDataProtection: usesDataProtection)
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var result: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      if status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) {
        return value
      }
    }
    return nil
  }

  func save(_ value: String, account: String) throws {
    guard let data = value.data(using: .utf8) else { throw KeychainPasswordError.encodingFailed }
    switch upsert(data, account: account, usesDataProtection: true) {
    case errSecSuccess:
      // Keep a single copy.
      SecItemDelete(baseQuery(account: account, usesDataProtection: false) as CFDictionary)
      return
    case errSecMissingEntitlement:
      break
    case let status:
      throw KeychainPasswordError.saveFailed(status)
    }
    let status = upsert(data, account: account, usesDataProtection: false)
    guard status == errSecSuccess else { throw KeychainPasswordError.saveFailed(status) }
  }

  func delete(account: String) {
    SecItemDelete(baseQuery(account: account, usesDataProtection: true) as CFDictionary)
    SecItemDelete(baseQuery(account: account, usesDataProtection: false) as CFDictionary)
  }

  private func baseQuery(account: String, usesDataProtection: Bool) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: account,
      kSecAttrService as String: service,
    ]
    if usesDataProtection {
      query[kSecUseDataProtectionKeychain as String] = true
    }
    return query
  }

  private func upsert(_ data: Data, account: String, usesDataProtection: Bool) -> OSStatus {
    let match = baseQuery(account: account, usesDataProtection: usesDataProtection)
    var attributes: [String: Any] = [kSecValueData as String: data]
    if usesDataProtection {
      attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
    }
    let update = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
    guard update == errSecItemNotFound else { return update }
    var add = match
    attributes.forEach { add[$0.key] = $0.value }
    return SecItemAdd(add as CFDictionary, nil)
  }
}

/// In-memory store for tests and previews.
nonisolated final class InMemoryKeychainPasswordStore: KeychainPasswordStoring, @unchecked Sendable {
  private var values: [String: String] = [:]
  private let lock = NSLock()

  init() {}

  func read(account: String) -> String? {
    lock.withLock { values[account] }
  }

  func save(_ value: String, account: String) throws {
    lock.withLock { values[account] = value }
  }

  func delete(account: String) {
    lock.withLock { values[account] = nil }
  }
}
