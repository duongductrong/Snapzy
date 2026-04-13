//
//  CloudPasswordService.swift
//  Snapzy
//
//  Manages optional password protection for cloud credentials.
//  Stores a SHA-256 hash in the macOS Keychain — no plaintext passwords are ever persisted.
//

import CryptoKit
import Foundation
import os.log

enum CloudPasswordVerificationResult {
  case verified
  case incorrectPassword
  case unavailable(String)
}

/// Manages the optional protection password for cloud credentials.
/// The password is hashed with SHA-256 before storage; verification compares hashes.
@MainActor
final class CloudPasswordService {
  static let shared = CloudPasswordService()
  private let logger = Logger(subsystem: "Snapzy", category: "CloudPasswordService")
  private let defaults = UserDefaults.standard

  private init() {}

  // MARK: - Public API

  /// Cached non-sensitive state used to avoid passive keychain reads.
  var hasPasswordConfigured: Bool {
    defaults.bool(forKey: PreferencesKeys.cloudPasswordEnabled)
  }

  /// Hash and store a new protection password in the Keychain.
  func savePassword(_ password: String) throws {
    let hash = sha256(password)
    try CloudKeychainStore.upsert(item: .passwordHash, value: hash)
    setPasswordConfigured(true)
  }

  /// Explicit check used when the user taps Edit.
  /// Reads keychain only when necessary to preserve existing password-protected installs.
  func shouldRequirePasswordForEdit() -> Bool {
    if hasPasswordConfigured {
      return true
    }

    switch loadHash(context: "shouldRequirePasswordForEdit") {
    case .success:
      setPasswordConfigured(true)
      return true
    case .itemNotFound:
      return false
    case .authRequired(let status):
      logger.notice("Keychain auth required (\(status, privacy: .public)) [shouldRequirePasswordForEdit]")
      return true
    case .interactionNotAllowed:
      logger.notice("Keychain interaction not allowed [shouldRequirePasswordForEdit]")
      return true
    case .error(let status):
      logger.error("Keychain read failed (\(status, privacy: .public)) [shouldRequirePasswordForEdit]")
      return true
    }
  }

  /// Verify a password against the stored hash.
  func verifyPassword(_ password: String) -> CloudPasswordVerificationResult {
    switch loadHash(context: "verifyPassword") {
    case .success(let storedHash):
      setPasswordConfigured(true)
      return sha256(password) == storedHash ? .verified : .incorrectPassword
    case .itemNotFound:
      setPasswordConfigured(false)
      return .unavailable(L10n.CloudPassword.notConfigured)
    case .authRequired:
      return .unavailable(L10n.CloudPassword.keychainAccessDenied)
    case .interactionNotAllowed:
      return .unavailable(L10n.CloudPassword.keychainInteractionUnavailable)
    case .error:
      return .unavailable(L10n.CloudPassword.couldntReadSavedPassword)
    }
  }

  /// Remove the stored password hash from the Keychain.
  func removePassword() {
    CloudKeychainStore.delete(item: .passwordHash)
    setPasswordConfigured(false)
  }

  // MARK: - Hashing

  private func sha256(_ input: String) -> String {
    let data = Data(input.utf8)
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  // MARK: - Helpers

  private func loadHash(context: String) -> CloudKeychainReadOutcome {
    CloudKeychainStore.read(item: .passwordHash, context: context)
  }

  private func setPasswordConfigured(_ enabled: Bool) {
    defaults.set(enabled, forKey: PreferencesKeys.cloudPasswordEnabled)
  }
}
