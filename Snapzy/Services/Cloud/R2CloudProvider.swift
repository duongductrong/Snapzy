//
//  R2CloudProvider.swift
//  Snapzy
//
//  Cloudflare R2 cloud provider (S3-compatible with R2-specific defaults)
//

import Foundation
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "R2CloudProvider")

/// Cloudflare R2 provider — thin wrapper around S3CloudProvider with R2 defaults.
/// R2 uses S3-compatible API with region="auto" and custom account endpoint.
final class R2CloudProvider: CloudProvider {
  let providerType: CloudProviderType = .cloudflareR2

  private let s3Provider: S3CloudProvider

  /// Initialize R2 provider.
  /// - Parameters:
  ///   - config: Cloud configuration (endpoint must be R2 account endpoint)
  ///   - accessKey: R2 Access Key ID
  ///   - secretKey: R2 Secret Access Key
  init(config: CloudConfiguration, accessKey: String, secretKey: String) {
    // Force R2 defaults: region = "auto"
    let r2Config = CloudConfiguration(
      providerType: .cloudflareR2,
      bucket: config.bucket,
      region: "auto",
      endpoint: config.endpoint,
      customDomain: config.customDomain,
      expireTime: config.expireTime
    )
    self.s3Provider = S3CloudProvider(
      config: r2Config,
      accessKey: accessKey,
      secretKey: secretKey
    )
  }

  // MARK: - CloudProvider

  func upload(
    fileURL: URL,
    contentType: String,
    expireTime: CloudExpireTime,
    existingKey: String? = nil,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> CloudUploadResult {
    logger.info("R2 upload starting: \(fileURL.lastPathComponent)")
    return try await s3Provider.upload(
      fileURL: fileURL,
      contentType: contentType,
      expireTime: expireTime,
      existingKey: existingKey,
      progress: progress
    )
  }

  func generatePublicURL(for key: String) -> URL {
    s3Provider.generatePublicURL(for: key)
  }

  func validate() async throws {
    try await s3Provider.validate()
    logger.info("R2 credentials validated successfully")
  }

  func delete(key: String) async throws {
    logger.info("R2 delete: \(key)")
    try await s3Provider.delete(key: key)
  }

  func setExpiration(days: Int) async throws {
    logger.info("R2 setExpiration: \(days) days")
    try await s3Provider.setExpiration(days: days)
  }

  func removeExpiration() async throws {
    logger.info("R2 removeExpiration")
    try await s3Provider.removeExpiration()
  }
}
