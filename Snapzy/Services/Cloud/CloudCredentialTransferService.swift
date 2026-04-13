//
//  CloudCredentialTransferService.swift
//  Snapzy
//
//  Encrypts and decrypts manual cloud credential archives for transfer between Macs.
//

import CommonCrypto
import CryptoKit
import Foundation
import Security
import UniformTypeIdentifiers

enum CloudCredentialTransferError: LocalizedError {
  case passphraseTooShort(minimumLength: Int)
  case invalidArchive
  case unsupportedSchemaVersion(Int)
  case unsupportedArchiveFormat
  case unlockFailed
  case randomizationFailed(OSStatus)

  var errorDescription: String? {
    switch self {
    case .passphraseTooShort(let minimumLength):
      return L10n.CloudTransfer.exportPassphraseTooShort(minimumLength)
    case .invalidArchive:
      return L10n.CloudTransfer.invalidArchive
    case .unsupportedSchemaVersion(let version):
      return L10n.CloudTransfer.unsupportedSchemaVersion(version)
    case .unsupportedArchiveFormat:
      return L10n.CloudTransfer.unsupportedArchiveFormat
    case .unlockFailed:
      return L10n.CloudTransfer.unlockFailed
    case .randomizationFailed:
      return L10n.CloudTransfer.randomizationFailed
    }
  }
}

enum CloudCredentialTransferService {
  static let archiveFileExtension = "snapzycloud"
  static let archiveContentType = UTType(filenameExtension: archiveFileExtension) ?? .data
  static let minimumPassphraseLength = 12

  private static let schemaVersion = 1
  private static let algorithm = "AES.GCM.256"
  private static let keyDerivation = "PBKDF2-SHA256"
  private static let keyLength = 32
  private static let saltLength = 16
  private static let iterationCount = 300_000

  static func exportArchive(
    payload: CloudCredentialTransferPayload,
    to archiveURL: URL,
    passphrase: String
  ) throws {
    guard passphrase.count >= minimumPassphraseLength else {
      throw CloudCredentialTransferError.passphraseTooShort(minimumLength: minimumPassphraseLength)
    }

    let archiveData = try exportArchive(payload: payload, passphrase: passphrase)
    try withScopedAccess(to: archiveURL) {
      try archiveData.write(to: archiveURL, options: .atomic)
    }
  }

  static func importArchive(
    from archiveURL: URL,
    passphrase: String
  ) throws -> CloudCredentialTransferPayload {
    let archiveData = try withScopedAccess(to: archiveURL) {
      try Data(contentsOf: archiveURL)
    }
    return try importArchive(from: archiveData, passphrase: passphrase)
  }

  static func exportArchive(
    payload: CloudCredentialTransferPayload,
    passphrase: String
  ) throws -> Data {
    let payloadData = try JSONEncoder().encode(payload)
    let salt = try randomData(count: saltLength)
    let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterationCount)
    let sealedBox = try AES.GCM.seal(payloadData, using: key)

    let envelope = CloudCredentialTransferEnvelope(
      schemaVersion: schemaVersion,
      algorithm: algorithm,
      kdf: keyDerivation,
      salt: salt.base64EncodedString(),
      iterations: iterationCount,
      nonce: sealedBox.nonce.withUnsafeBytes { Data($0).base64EncodedString() },
      ciphertext: sealedBox.ciphertext.base64EncodedString(),
      tag: sealedBox.tag.base64EncodedString()
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(envelope)
  }

  static func importArchive(
    from archiveData: Data,
    passphrase: String
  ) throws -> CloudCredentialTransferPayload {
    let envelope: CloudCredentialTransferEnvelope
    do {
      envelope = try JSONDecoder().decode(CloudCredentialTransferEnvelope.self, from: archiveData)
    } catch {
      throw CloudCredentialTransferError.invalidArchive
    }

    guard envelope.schemaVersion == schemaVersion else {
      throw CloudCredentialTransferError.unsupportedSchemaVersion(envelope.schemaVersion)
    }
    guard envelope.algorithm == algorithm, envelope.kdf == keyDerivation else {
      throw CloudCredentialTransferError.unsupportedArchiveFormat
    }
    guard
      let salt = Data(base64Encoded: envelope.salt),
      let nonceData = Data(base64Encoded: envelope.nonce),
      let ciphertext = Data(base64Encoded: envelope.ciphertext),
      let tag = Data(base64Encoded: envelope.tag)
    else {
      throw CloudCredentialTransferError.invalidArchive
    }

    let key = try deriveKey(
      passphrase: passphrase,
      salt: salt,
      iterations: envelope.iterations
    )

    let plaintext: Data
    do {
      let nonce = try AES.GCM.Nonce(data: nonceData)
      let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
      plaintext = try AES.GCM.open(sealedBox, using: key)
    } catch {
      throw CloudCredentialTransferError.unlockFailed
    }

    let payload: CloudCredentialTransferPayload
    do {
      payload = try JSONDecoder().decode(CloudCredentialTransferPayload.self, from: plaintext)
    } catch {
      throw CloudCredentialTransferError.invalidArchive
    }

    guard
      payload.configuration.isValid,
      !payload.accessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !payload.secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw CloudCredentialTransferError.invalidArchive
    }

    return payload
  }

  static func suggestedArchiveFileName(for payload: CloudCredentialTransferPayload) -> String {
    let provider = payload.configuration.providerType.rawValue.replacingOccurrences(of: "_", with: "-")
    let bucket = sanitizedFileNameComponent(payload.configuration.bucket)
    return "snapzy-cloud-\(provider)-\(bucket).\(archiveFileExtension)"
  }

  private static func deriveKey(
    passphrase: String,
    salt: Data,
    iterations: Int
  ) throws -> SymmetricKey {
    var derivedKey = [UInt8](repeating: 0, count: keyLength)
    let status = salt.withUnsafeBytes { saltBytes in
      passphrase.withCString { passphraseBytes in
        CCKeyDerivationPBKDF(
          CCPBKDFAlgorithm(kCCPBKDF2),
          passphraseBytes,
          passphrase.lengthOfBytes(using: .utf8),
          saltBytes.bindMemory(to: UInt8.self).baseAddress,
          salt.count,
          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
          UInt32(iterations),
          &derivedKey,
          derivedKey.count
        )
      }
    }

    guard status == kCCSuccess else {
      throw CloudCredentialTransferError.unlockFailed
    }
    return SymmetricKey(data: Data(derivedKey))
  }

  private static func randomData(count: Int) throws -> Data {
    var data = Data(count: count)
    let status = data.withUnsafeMutableBytes { bytes in
      SecRandomCopyBytes(kSecRandomDefault, count, bytes.baseAddress!)
    }
    guard status == errSecSuccess else {
      throw CloudCredentialTransferError.randomizationFailed(status)
    }
    return data
  }

  private static func withScopedAccess<T>(to url: URL, _ operation: () throws -> T) rethrows -> T {
    let didStart = url.startAccessingSecurityScopedResource()
    defer {
      if didStart {
        url.stopAccessingSecurityScopedResource()
      }
    }
    return try operation()
  }

  private static func sanitizedFileNameComponent(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let replaced = trimmed.map { character -> Character in
      character.isLetter || character.isNumber || character == "-" ? character : "-"
    }
    let collapsed = String(replaced)
      .replacingOccurrences(of: "--", with: "-")
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return collapsed.isEmpty ? "bucket" : collapsed
  }
}
