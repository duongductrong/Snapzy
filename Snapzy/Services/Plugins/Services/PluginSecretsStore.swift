import Foundation
import Security
import SnapzyPluginAPI

/// `snapzy.secrets` — one Keychain item per (plugin, name). Values written by
/// the plugin's own settings form; reads are brokered and never logged.
/// Mirrors `CloudKeychainStore`'s SecItem patterns.
struct PluginSecretsStore: Sendable {
  private static let service = "com.trongduong.snapzy.plugins"

  func get(name: String, pluginID: String) async throws -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: Self.account(name: name, pluginID: pluginID),
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecUseDataProtectionKeychain as String: true,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      guard let data = result as? Data else { return nil }
      return String(data: data, encoding: .utf8)
    case errSecItemNotFound:
      return nil
    default:
      throw PluginServiceError(code: "keychainError", message: "Keychain read failed (\(status)).")
    }
  }

  func set(name: String, value: String?, pluginID: String) async throws {
    guard let value, !value.isEmpty else {
      try delete(name: name, pluginID: pluginID)
      return
    }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: Self.account(name: name, pluginID: pluginID),
      kSecUseDataProtectionKeychain as String: true,
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: Data(value.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
    ]
    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecItemNotFound {
      var addQuery = query
      addQuery[kSecValueData as String] = Data(value.utf8)
      addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
      let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw PluginServiceError(code: "keychainError", message: "Keychain write failed (\(addStatus)).")
      }
    } else if updateStatus != errSecSuccess {
      throw PluginServiceError(code: "keychainError", message: "Keychain write failed (\(updateStatus)).")
    }
  }

  func delete(name: String, pluginID: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: Self.account(name: name, pluginID: pluginID),
      kSecUseDataProtectionKeychain as String: true,
    ]
    SecItemDelete(query as CFDictionary)
  }

  /// Removes every item for a plugin (plugin removal).
  func deleteAll(pluginID: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecUseDataProtectionKeychain as String: true,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return }
    // Iterate accounts matching the plugin prefix and delete them.
    let prefix = "\(pluginID)."
    let items = (result as? [Any]) ?? []
    for case let item as [String: Any] in items {
      guard let account = item[kSecAttrAccount as String] as? String, account.hasPrefix(prefix) else { continue }
      var deleteQuery = query
      deleteQuery[kSecAttrAccount as String] = account
      SecItemDelete(deleteQuery as CFDictionary)
    }
  }

  private static func account(name: String, pluginID: String) -> String {
    "\(pluginID).\(name)"
  }
}
