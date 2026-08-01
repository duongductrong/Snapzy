//
//  OCRKeychainStore.swift
//  Snapzy
//
//  Local-only keychain access for custom OCR endpoint API keys.
//

import Foundation
import Security

/// Storage seam for custom OCR model API keys. Keeps `CustomOCRModelStore`
/// and `RemoteOCRProvider` testable with in-memory fakes.
protocol OCRKeychainStoring: Sendable {
  func readKey(for modelID: UUID) -> String?
  func saveKey(_ key: String, for modelID: UUID) throws
  func deleteKey(for modelID: UUID)
}

enum OCRKeychainError: LocalizedError, Equatable {
  case encodingFailed
  case saveFailed(OSStatus)

  var errorDescription: String? {
    switch self {
    case .encodingFailed:
      return "Failed to encode the API key for Keychain storage"
    case .saveFailed(let status):
      return "Failed to save the API key to the Keychain (error \(status))"
    }
  }
}

/// Keychain-backed API key store for custom OCR endpoints.
///
/// Mirrors `CloudKeychainStore`: generic-password items in the data-protection
/// keychain (`kSecAttrAccessibleWhenUnlocked`), falling back to the file-based
/// keychain when the data-protection entitlement is unavailable (unsigned dev
/// builds). Account = model UUID string.
struct OCRKeychainStore: OCRKeychainStoring {
  private static let service = "com.trongduong.snapzy.ocr"

  private struct Location: Equatable {
    let usesDataProtection: Bool
  }

  init() {}

  func readKey(for modelID: UUID) -> String? {
    for location in [Location(usesDataProtection: true), Location(usesDataProtection: false)] {
      switch readValue(at: location, account: account(for: modelID)) {
      case .success(let value):
        return value
      case .itemNotFound, .unavailable, .failed:
        continue
      }
    }
    return nil
  }

  func saveKey(_ key: String, for modelID: UUID) throws {
    guard let data = key.data(using: .utf8) else {
      throw OCRKeychainError.encodingFailed
    }

    let account = account(for: modelID)
    let dataProtectionLocation = Location(usesDataProtection: true)
    switch upsertValue(data, at: dataProtectionLocation, account: account) {
    case .success:
      // Keep a single copy; drop any fallback-location duplicate.
      deleteValue(at: Location(usesDataProtection: false), account: account)
      return
    case .unavailable:
      break
    case .failed(let status):
      throw OCRKeychainError.saveFailed(status)
    }

    let fileBasedLocation = Location(usesDataProtection: false)
    switch upsertValue(data, at: fileBasedLocation, account: account) {
    case .success:
      DiagnosticLogger.shared.log(
        .warning,
        .ocr,
        "OCR API key stored in file-based keychain due missing data-protection entitlement",
        context: ["account": account]
      )
      return
    case .unavailable:
      throw OCRKeychainError.saveFailed(errSecMissingEntitlement)
    case .failed(let status):
      throw OCRKeychainError.saveFailed(status)
    }
  }

  func deleteKey(for modelID: UUID) {
    let account = account(for: modelID)
    deleteValue(at: Location(usesDataProtection: true), account: account)
    deleteValue(at: Location(usesDataProtection: false), account: account)
  }

  // MARK: - Private

  private enum OperationResult {
    case success(String)
    case itemNotFound
    case unavailable
    case failed(OSStatus)
  }

  private enum UpsertResult {
    case success
    case unavailable
    case failed(OSStatus)
  }

  private func account(for modelID: UUID) -> String {
    modelID.uuidString
  }

  private func baseQuery(at location: Location, account: String) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: account,
      kSecAttrService as String: Self.service,
    ]
    if location.usesDataProtection {
      query[kSecUseDataProtectionKeychain as String] = true
    }
    return query
  }

  private func readValue(at location: Location, account: String) -> OperationResult {
    var query = baseQuery(at: location, account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    switch status {
    case errSecSuccess:
      guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
        return .failed(errSecDecode)
      }
      return .success(value)
    case errSecItemNotFound:
      return .itemNotFound
    case errSecMissingEntitlement:
      return .unavailable
    default:
      DiagnosticLogger.shared.log(
        .error,
        .ocr,
        "OCR keychain read failed",
        context: ["account": account, "status": "\(status)"]
      )
      return .failed(status)
    }
  }

  private func deleteValue(at location: Location, account: String) {
    SecItemDelete(baseQuery(at: location, account: account) as CFDictionary)
  }

  private func upsertValue(_ data: Data, at location: Location, account: String) -> UpsertResult {
    let matchQuery = baseQuery(at: location, account: account)
    var attributes: [String: Any] = [kSecValueData as String: data]
    if location.usesDataProtection {
      attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
    }

    let updateStatus = SecItemUpdate(matchQuery as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess {
      return .success
    }
    if updateStatus == errSecMissingEntitlement {
      return .unavailable
    }
    guard updateStatus == errSecItemNotFound else {
      return .failed(updateStatus)
    }

    var addQuery = matchQuery
    attributes.forEach { addQuery[$0.key] = $0.value }
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    if addStatus == errSecMissingEntitlement {
      return .unavailable
    }
    guard addStatus == errSecSuccess else {
      return .failed(addStatus)
    }
    return .success
  }
}
