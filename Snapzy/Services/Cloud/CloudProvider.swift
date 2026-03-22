//
//  CloudProvider.swift
//  Snapzy
//
//  Strategy protocol for cloud storage providers (S3, R2, etc.)
//

import Foundation

// MARK: - Provider Type

/// Supported cloud storage provider types
enum CloudProviderType: String, Codable, CaseIterable {
  case awsS3 = "aws_s3"
  case cloudflareR2 = "cloudflare_r2"

  var displayName: String {
    switch self {
    case .awsS3: return "AWS S3"
    case .cloudflareR2: return "Cloudflare R2"
    }
  }
}

// MARK: - Upload Result

/// Result of a successful cloud upload
struct CloudUploadResult {
  let publicURL: URL
  let key: String
  let fileSize: Int64
  let uploadedAt: Date
}

// MARK: - Cloud Provider Protocol

/// Strategy interface for cloud storage operations.
/// Implement this protocol to add support for new cloud providers.
protocol CloudProvider {
  var providerType: CloudProviderType { get }

  /// Upload a file to cloud storage.
  /// - Parameters:
  ///   - fileURL: Local file URL to upload
  ///   - contentType: MIME type of the file (e.g. "image/png")
  ///   - expireTime: Expiration time for the uploaded file
  ///   - existingKey: If provided, overwrites the existing object with this key
  ///   - progress: Progress callback (0.0 to 1.0)
  /// - Returns: Upload result with public URL and metadata
  func upload(
    fileURL: URL,
    contentType: String,
    expireTime: CloudExpireTime,
    existingKey: String?,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> CloudUploadResult

  /// Generate a public URL for an uploaded object key.
  func generatePublicURL(for key: String) -> URL

  /// Delete an object from cloud storage by its key.
  func delete(key: String) async throws

  /// Set a lifecycle expiration rule on the bucket for objects with `snapzy/` prefix.
  /// - Parameter days: Number of days after which objects expire
  func setExpiration(days: Int) async throws

  /// Remove the Snapzy lifecycle expiration rule from the bucket.
  func removeExpiration() async throws

  /// Validate the provider credentials and configuration.
  func validate() async throws
}

// MARK: - Cloud Errors

/// Errors that can occur during cloud operations
enum CloudError: LocalizedError {
  case notConfigured
  case invalidCredentials
  case uploadFailed(statusCode: Int, message: String)
  case networkError(Error)
  case fileNotFound(URL)
  case signingFailed(String)
  case invalidResponse
  case keychainError(String)

  var errorDescription: String? {
    switch self {
    case .notConfigured:
      return "Cloud storage is not configured. Please set up your credentials in Preferences → Cloud."
    case .invalidCredentials:
      return "Invalid cloud credentials. Please verify your Access Key and Secret Key."
    case .uploadFailed(let code, let message):
      return "Upload failed (HTTP \(code)): \(message)"
    case .networkError(let error):
      return "Network error: \(error.localizedDescription)"
    case .fileNotFound(let url):
      return "File not found: \(url.lastPathComponent)"
    case .signingFailed(let reason):
      return "Request signing failed: \(reason)"
    case .invalidResponse:
      return "Invalid response from cloud provider."
    case .keychainError(let reason):
      return "Keychain error: \(reason)"
    }
  }
}
