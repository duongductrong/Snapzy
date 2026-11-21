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
      DiagnosticLogger.shared.log(
        .warning,
        .cloud,
        "Cloud credential archive export rejected; passphrase too short",
        context: ["minimumLength": "\(minimumPassphraseLength)"]
      )
      throw CloudCredentialTransferError.passphraseTooShort(minimumLength: minimumPassphraseLength)
    }

    DiagnosticLogger.shared.log(
      .info,
      .cloud,
      "Cloud credential archive export started",
      context: [
        "provider": payload.configuration.providerType.rawValue,
        "destination": archiveURL.lastPathComponent,
      ]
    )
    do {
      let archiveData = try exportArchive(payload: payload, passphrase: passphrase)
      try withScopedAccess(to: archiveURL) {
        try archiveData.write(to: archiveURL, options: .atomic)
      }
      DiagnosticLogger.shared.log(
        .info,
        .cloud,
        "Cloud credential archive exported",
        context: [
          "provider": payload.configuration.providerType.rawValue,
          "destination": archiveURL.lastPathComponent,
          "bytes": "\(archiveData.count)",
        ]
      )
    } catch {
      DiagnosticLogger.shared.logError(
        .cloud,
        error,
        "Cloud credential archive export failed",
        context: [
          "provider": payload.configuration.providerType.rawValue,
          "destination": archiveURL.lastPathComponent,
        ]
      )
      throw error
    }
  }

  static func importArchive(
    from archiveURL: URL,
    passphrase: String
  ) throws -> CloudCredentialTransferPayload {
    DiagnosticLogger.shared.log(
      .info,
      .cloud,
      "Cloud credential archive import started",
      context: ["source": archiveURL.lastPathComponent]
    )
    do {
      let archiveData = try withScopedAccess(to: archiveURL) {
        try Data(contentsOf: archiveURL)
      }
      let payload = try importArchive(from: archiveData, passphrase: passphrase)
      DiagnosticLogger.shared.log(
        .info,
        .cloud,
        "Cloud credential archive imported",
        context: [
          "source": archiveURL.lastPathComponent,
          "provider": payload.configuration.providerType.rawValue,
          "bytes": "\(archiveData.count)",
        ]
      )
      return payload
    } catch {
      DiagnosticLogger.shared.logError(
        .cloud,
        error,
        "Cloud credential archive import failed",
        context: ["source": archiveURL.lastPathComponent]
      )
      throw error
    }
  }

  static func exportArchive(
    payload: CloudCredentialTransferPayload,
    passphrase: String
  ) throws -> Data {
    guard passphrase.count >= minimumPassphraseLength else {
      DiagnosticLogger.shared.log(
        .warning,
        .cloud,
        "Cloud credential archive export rejected; passphrase too short",
        context: ["minimumLength": "\(minimumPassphraseLength)"]
      )
      throw CloudCredentialTransferError.passphraseTooShort(minimumLength: minimumPassphraseLength)
    }

    DiagnosticLogger.shared.log(
      .debug,
      .cloud,
      "Cloud credential archive envelope encoding started",
      context: [
        "provider": payload.configuration.providerType.rawValue,
        "schemaVersion": "\(schemaVersion)",
        "algorithm": algorithm,
      ]
    )
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
    let data = try encoder.encode(envelope)
    DiagnosticLogger.shared.log(
      .debug,
      .cloud,
      "Cloud credential archive envelope encoded",
      context: ["payloadBytes": "\(payloadData.count)", "archiveBytes": "\(data.count)"]
    )
    return data
  }

  static func importArchive(
    from archiveData: Data,
    passphrase: String
  ) throws -> CloudCredentialTransferPayload {
    let envelope: CloudCredentialTransferEnvelope
    do {
      envelope = try JSONDecoder().decode(CloudCredentialTransferEnvelope.self, from: archiveData)
    } catch {
      DiagnosticLogger.shared.logError(
        .cloud,
        error,
        "Cloud credential archive envelope decode failed",
        context: ["archiveBytes": "\(archiveData.count)"]
      )
      throw CloudCredentialTransferError.invalidArchive
    }

    guard envelope.schemaVersion == schemaVersion else {
      DiagnosticLogger.shared.log(
        .warning,
        .cloud,
        "Cloud credential archive schema unsupported",
        context: ["schemaVersion": "\(envelope.schemaVersion)"]
      )
      throw CloudCredentialTransferError.unsupportedSchemaVersion(envelope.schemaVersion)
    }
    guard envelope.algorithm == algorithm, envelope.kdf == keyDerivation else {
      DiagnosticLogger.shared.log(
        .warning,
        .cloud,
        "Cloud credential archive format unsupported",
        context: ["algorithm": envelope.algorithm, "kdf": envelope.kdf]
      )
      throw CloudCredentialTransferError.unsupportedArchiveFormat
    }
    guard
      let salt = Data(base64Encoded: envelope.salt),
      let nonceData = Data(base64Encoded: envelope.nonce),
      let ciphertext = Data(base64Encoded: envelope.ciphertext),
      let tag = Data(base64Encoded: envelope.tag)
    else {
      DiagnosticLogger.shared.log(.warning, .cloud, "Cloud credential archive contains invalid base64 fields")
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
      DiagnosticLogger.shared.logError(.cloud, error, "Cloud credential archive unlock failed")
      throw CloudCredentialTransferError.unlockFailed
    }

    let payload: CloudCredentialTransferPayload
    do {
      payload = try JSONDecoder().decode(CloudCredentialTransferPayload.self, from: plaintext)
    } catch {
      DiagnosticLogger.shared.logError(.cloud, error, "Cloud credential archive payload decode failed")
      throw CloudCredentialTransferError.invalidArchive
    }

    guard
      payload.configuration.isValid,
      !payload.accessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      // imgbb has a single API key, carried in `accessKey`.
      payload.configuration.providerType == .imgbb
        || !payload.secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      DiagnosticLogger.shared.log(.warning, .cloud, "Cloud credential archive payload validation failed")
      throw CloudCredentialTransferError.invalidArchive
    }

    DiagnosticLogger.shared.log(
      .debug,
      .cloud,
      "Cloud credential archive payload validated",
      context: ["provider": payload.configuration.providerType.rawValue]
    )
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
      DiagnosticLogger.shared.log(
        .error,
        .cloud,
        "Cloud credential archive random data generation failed",
        context: ["status": "\(status)", "bytes": "\(count)"]
      )
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
