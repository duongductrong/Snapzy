//
//  CloudCredentialTransferModels.swift
//  Snapzy
//
//  Versioned models for encrypted cloud credential transfer archives.
//

import Foundation

struct CloudCredentialTransferPayload: Codable, Equatable {
  let configuration: CloudConfiguration
  let accessKey: String
  let secretKey: String
  var googleClientId: String? = nil
  var googleClientSecret: String? = nil
  var googleRefreshToken: String? = nil
  /// Raw `CloudShareLinkStyle` value. Optional and stored as a string so archives from older
  /// versions (no field) and newer versions (unknown style) still import.
  var shareLinkStyle: String? = nil

  var providerDisplayName: String {
    configuration.providerType.displayName
  }

  /// The share link style to apply on import. Nil for Google Drive, which doesn't use object keys,
  /// and for archives that don't carry a known style.
  var resolvedShareLinkStyle: CloudShareLinkStyle? {
    guard configuration.providerType != .googleDrive, let shareLinkStyle else { return nil }
    return CloudShareLinkStyle(rawValue: shareLinkStyle)
  }
}

struct CloudCredentialTransferEnvelope: Codable {
  let schemaVersion: Int
  let algorithm: String
  let kdf: String
  let salt: String
  let iterations: Int
  let nonce: String
  let ciphertext: String
  let tag: String
}
