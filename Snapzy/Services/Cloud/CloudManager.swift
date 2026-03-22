//
//  CloudManager.swift
//  Snapzy
//
//  Singleton facade managing cloud configuration, Keychain credentials, and upload orchestration
//

import AppKit
import Combine
import Foundation
import os.log
import Security

private let logger = Logger(subsystem: "Snapzy", category: "CloudManager")

/// Central manager for cloud storage operations.
/// Acts as an Adapter/Facade — consumers don't need to know which provider is active.
@MainActor
final class CloudManager: ObservableObject {

  static let shared = CloudManager()

  // MARK: - Published State

  @Published private(set) var isConfigured: Bool = false
  @Published private(set) var providerType: CloudProviderType?
  @Published var isUploading: Bool = false
  @Published var uploadProgress: Double = 0

  // MARK: - Keychain Keys

  private enum KeychainKeys {
    static let accessKey = "com.snapzy.cloud.accessKey"
    static let secretKey = "com.snapzy.cloud.secretKey"
  }

  // MARK: - Init

  private init() {
    loadState()
  }

  private func loadState() {
    isConfigured = UserDefaults.standard.bool(forKey: PreferencesKeys.cloudConfigured)
    if let typeRaw = UserDefaults.standard.string(forKey: PreferencesKeys.cloudProviderType),
      let type = CloudProviderType(rawValue: typeRaw)
    {
      providerType = type
    }
  }

  // MARK: - Configuration

  /// Save cloud configuration and credentials.
  /// Non-sensitive config goes to UserDefaults, secrets go to Keychain.
  func saveConfiguration(
    _ config: CloudConfiguration,
    accessKey: String,
    secretKey: String
  ) throws {
    // Save secrets to Keychain
    try saveToKeychain(key: KeychainKeys.accessKey, value: accessKey)
    try saveToKeychain(key: KeychainKeys.secretKey, value: secretKey)

    // Save non-sensitive config to UserDefaults
    let defaults = UserDefaults.standard
    defaults.set(config.providerType.rawValue, forKey: PreferencesKeys.cloudProviderType)
    defaults.set(config.bucket, forKey: PreferencesKeys.cloudBucket)
    defaults.set(config.region, forKey: PreferencesKeys.cloudRegion)
    defaults.set(config.endpoint ?? "", forKey: PreferencesKeys.cloudEndpoint)
    defaults.set(config.customDomain ?? "", forKey: PreferencesKeys.cloudCustomDomain)
    defaults.set(config.expireTime.rawValue, forKey: PreferencesKeys.cloudExpireTime)
    defaults.set(true, forKey: PreferencesKeys.cloudConfigured)

    // Update state
    isConfigured = true
    providerType = config.providerType

    logger.info("Cloud configuration saved: \(config.providerType.displayName)")
  }

  /// Apply lifecycle expiration rule to the bucket based on current config.
  /// Call after saveConfiguration + validateCredentials.
  func applyLifecycleRule() async throws {
    guard let provider = createProvider(),
      let config = loadConfiguration()
    else {
      throw CloudError.notConfigured
    }

    if let days = config.expireTime.days {
      try await provider.setExpiration(days: days)
      logger.info("Lifecycle rule applied: \(days) days")
    } else {
      try await provider.removeExpiration()
      logger.info("Lifecycle rule removed (permanent)")
    }
  }

  /// Load the current cloud configuration (non-sensitive parts from UserDefaults).
  func loadConfiguration() -> CloudConfiguration? {
    guard isConfigured else { return nil }
    let defaults = UserDefaults.standard

    guard
      let typeRaw = defaults.string(forKey: PreferencesKeys.cloudProviderType),
      let type = CloudProviderType(rawValue: typeRaw)
    else { return nil }

    let bucket = defaults.string(forKey: PreferencesKeys.cloudBucket) ?? ""
    let region = defaults.string(forKey: PreferencesKeys.cloudRegion) ?? ""
    let endpoint = defaults.string(forKey: PreferencesKeys.cloudEndpoint)
    let customDomain = defaults.string(forKey: PreferencesKeys.cloudCustomDomain)
    let expireRaw = defaults.string(forKey: PreferencesKeys.cloudExpireTime) ?? CloudExpireTime.day7.rawValue
    // Use standard init first, fallback to legacy migration for old hour/minute values
    let expireTime = CloudExpireTime(rawValue: expireRaw) ?? CloudExpireTime(legacyRawValue: expireRaw)

    return CloudConfiguration(
      providerType: type,
      bucket: bucket,
      region: region,
      endpoint: (endpoint?.isEmpty ?? true) ? nil : endpoint,
      customDomain: (customDomain?.isEmpty ?? true) ? nil : customDomain,
      expireTime: expireTime
    )
  }

  /// Load masked access key for display (e.g. "AKIA••••WXYZ")
  func maskedAccessKey() -> String {
    guard let key = loadFromKeychain(key: KeychainKeys.accessKey), key.count > 8 else {
      return "••••••••"
    }
    let prefix = String(key.prefix(4))
    let suffix = String(key.suffix(4))
    return "\(prefix)••••\(suffix)"
  }

  /// Load the full access key (for edit mode)
  func loadAccessKey() -> String {
    loadFromKeychain(key: KeychainKeys.accessKey) ?? ""
  }

  /// Load the full secret key (for edit mode)
  func loadSecretKey() -> String {
    loadFromKeychain(key: KeychainKeys.secretKey) ?? ""
  }

  /// Clear all cloud configuration and credentials
  func clearConfiguration() {
    deleteFromKeychain(key: KeychainKeys.accessKey)
    deleteFromKeychain(key: KeychainKeys.secretKey)

    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: PreferencesKeys.cloudProviderType)
    defaults.removeObject(forKey: PreferencesKeys.cloudBucket)
    defaults.removeObject(forKey: PreferencesKeys.cloudRegion)
    defaults.removeObject(forKey: PreferencesKeys.cloudEndpoint)
    defaults.removeObject(forKey: PreferencesKeys.cloudCustomDomain)
    defaults.removeObject(forKey: PreferencesKeys.cloudExpireTime)
    defaults.set(false, forKey: PreferencesKeys.cloudConfigured)

    isConfigured = false
    providerType = nil

    logger.info("Cloud configuration cleared")
  }

  // MARK: - Provider Factory

  /// Create the active cloud provider from saved configuration.
  func createProvider() -> CloudProvider? {
    guard let config = loadConfiguration() else { return nil }
    guard let accessKey = loadFromKeychain(key: KeychainKeys.accessKey),
      let secretKey = loadFromKeychain(key: KeychainKeys.secretKey)
    else { return nil }

    switch config.providerType {
    case .awsS3:
      return S3CloudProvider(config: config, accessKey: accessKey, secretKey: secretKey)
    case .cloudflareR2:
      return R2CloudProvider(config: config, accessKey: accessKey, secretKey: secretKey)
    }
  }

  // MARK: - Upload

  /// Upload a file to the configured cloud provider.
  /// Updates `isUploading` and `uploadProgress` for UI binding.
  /// - Parameter existingKey: If provided, overwrites existing cloud object with same key
  func upload(fileURL: URL, existingKey: String? = nil) async throws -> CloudUploadResult {
    guard let provider = createProvider(),
      let config = loadConfiguration()
    else {
      throw CloudError.notConfigured
    }

    let contentType = mimeType(for: fileURL)

    isUploading = true
    uploadProgress = 0
    defer {
      isUploading = false
    }

    do {
      let result = try await provider.upload(
        fileURL: fileURL,
        contentType: contentType,
        expireTime: config.expireTime,
        existingKey: existingKey,
        progress: { [weak self] progress in
          Task { @MainActor in
            self?.uploadProgress = progress
          }
        }
      )

      // Record in history
      let recordId = UUID()
      let record = CloudUploadRecord(
        id: recordId,
        fileName: fileURL.lastPathComponent,
        publicURL: result.publicURL,
        key: result.key,
        fileSize: result.fileSize,
        uploadedAt: result.uploadedAt,
        providerType: provider.providerType,
        expireTime: config.expireTime,
        contentType: contentType
      )
      CloudUploadHistoryStore.shared.add(record)

      // Generate thumbnail for image uploads
      if contentType.hasPrefix("image/") {
        saveThumbnail(from: fileURL, recordId: recordId)
      }

      logger.info("Upload completed: \(result.publicURL.absoluteString)")
      return result
    } catch {
      logger.error("Upload failed: \(error.localizedDescription)")
      throw error
    }
  }

  /// Validate credentials by testing connection to the cloud provider.
  func validateCredentials() async throws {
    guard let provider = createProvider() else {
      throw CloudError.notConfigured
    }
    try await provider.validate()
  }

  // MARK: - Delete

  /// Delete a single object from cloud storage and remove local record.
  func deleteFromCloud(record: CloudUploadRecord) async throws {
    guard let provider = createProvider() else {
      throw CloudError.notConfigured
    }

    try await provider.delete(key: record.key)
    CloudUploadHistoryStore.shared.remove(id: record.id)
    cleanupThumbnail(recordId: record.id)
    logger.info("Deleted from cloud: \(record.key)")
  }

  /// Delete a cloud object by key only.
  /// Also removes the matching record from upload history.
  /// Used for background cleanup when re-uploading with a new key.
  func deleteByKey(key: String) async throws {
    guard let provider = createProvider() else {
      throw CloudError.notConfigured
    }
    try await provider.delete(key: key)
    CloudUploadHistoryStore.shared.removeByKey(key)
    logger.info("Deleted old cloud object: \(key)")
  }

  /// Delete all objects from cloud storage and clear local records.
  /// Continues on individual failures to delete as many as possible.
  func deleteAllFromCloud(records: [CloudUploadRecord]) async throws {
    guard let provider = createProvider() else {
      throw CloudError.notConfigured
    }

    var lastError: Error?
    for record in records {
      do {
        try await provider.delete(key: record.key)
      } catch {
        logger.error("Failed to delete \(record.key): \(error.localizedDescription)")
        lastError = error
      }
    }
    for record in records {
      cleanupThumbnail(recordId: record.id)
    }
    CloudUploadHistoryStore.shared.removeAll()
    logger.info("Bulk delete completed: \(records.count) records")

    if let lastError = lastError {
      throw lastError
    }
  }

  // MARK: - MIME Type

  private func mimeType(for url: URL) -> String {
    let ext = url.pathExtension.lowercased()
    switch ext {
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "webp": return "image/webp"
    case "gif": return "image/gif"
    case "tiff", "tif": return "image/tiff"
    case "bmp": return "image/bmp"
    case "mov": return "video/quicktime"
    case "mp4": return "video/mp4"
    default: return "application/octet-stream"
    }
  }

  // MARK: - Thumbnail

  private var thumbnailsDirectory: URL {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    return appSupport
      .appendingPathComponent("Snapzy", isDirectory: true)
      .appendingPathComponent("thumbnails", isDirectory: true)
  }

  /// Generate a 200px max-dimension JPEG thumbnail for image uploads
  private func saveThumbnail(from fileURL: URL, recordId: UUID) {
    guard let image = NSImage(contentsOf: fileURL) else { return }
    let maxDimension: CGFloat = 200
    let size = image.size
    let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
    let newSize = NSSize(width: size.width * scale, height: size.height * scale)

    let thumbImage = NSImage(size: newSize)
    thumbImage.lockFocus()
    image.draw(
      in: NSRect(origin: .zero, size: newSize),
      from: NSRect(origin: .zero, size: size),
      operation: .copy,
      fraction: 1.0
    )
    thumbImage.unlockFocus()

    guard let tiffData = thumbImage.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    else { return }

    let dir = thumbnailsDirectory
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let thumbURL = dir.appendingPathComponent("\(recordId.uuidString).jpg")
    try? jpegData.write(to: thumbURL, options: .atomic)
  }

  /// Remove thumbnail file when a record is deleted
  private func cleanupThumbnail(recordId: UUID) {
    let thumbURL = thumbnailsDirectory.appendingPathComponent("\(recordId.uuidString).jpg")
    try? FileManager.default.removeItem(at: thumbURL)
  }

  // MARK: - Keychain Operations

  private func saveToKeychain(key: String, value: String) throws {
    guard let data = value.data(using: .utf8) else {
      throw CloudError.keychainError("Failed to encode value")
    }

    // Delete existing item first
    deleteFromKeychain(key: key)

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key,
      kSecAttrService as String: "com.snapzy.cloud",
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
    ]

    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw CloudError.keychainError("SecItemAdd failed: \(status)")
    }
  }

  private func loadFromKeychain(key: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key,
      kSecAttrService as String: "com.snapzy.cloud",
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess, let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private func deleteFromKeychain(key: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key,
      kSecAttrService as String: "com.snapzy.cloud",
    ]
    SecItemDelete(query as CFDictionary)
  }
}
