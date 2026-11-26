//
//  CustomHTTPCloudProvider.swift
//  Snapzy
//
//  Cloud provider backed by a user-defined custom uploader (`cloud.customUploaderID`).
//  The history key is the public URL itself, so `generatePublicURL(for:)` turns it back.
//  There is no delete API or lifecycle rule; the deletion link (if any) rides on the result.
//

import Foundation

final class CustomHTTPCloudProvider: CloudProvider {
  let providerType: CloudProviderType = .customHTTP

  let uploaderID: UUID?
  private let lookup: (UUID) -> CustomUploader?
  private let secrets: () -> CustomUploaderSecretResolving?
  private let engine: CustomUploaderEngine

  init(
    uploaderID: UUID?,
    lookup: ((UUID) -> CustomUploader?)? = nil,
    secrets: (() -> CustomUploaderSecretResolving?)? = nil,
    engine: CustomUploaderEngine? = nil
  ) {
    self.uploaderID = uploaderID
    self.lookup = lookup ?? { CustomUploaderStore.shared.uploader(id: $0) }
    self.secrets = secrets ?? { CustomUploaderSecrets.provider }
    self.engine = engine ?? CustomUploaderEngine()
  }

  /// The uploader id saved in `cloud.customUploaderID`, if any.
  static func storedUploaderID(defaults: UserDefaults = .standard) -> UUID? {
    defaults.string(forKey: PreferencesKeys.cloudCustomUploaderID).flatMap(UUID.init(uuidString:))
  }

  // MARK: - CloudProvider

  /// Custom uploaders can't overwrite, so `existingKey` is ignored and every call makes a new link.
  func upload(
    fileURL: URL,
    contentType: String,
    expireTime: CloudExpireTime,
    existingKey: String?,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> CloudUploadResult {
    let uploader = try resolveUploader()
    return try await engine.upload(
      fileURL: fileURL,
      using: uploader,
      secrets: secrets(),
      contentType: contentType,
      progress: progress
    )
  }

  /// The key is the public URL string (see `CustomUploaderEngine.result`).
  func generatePublicURL(for key: String) -> URL {
    CustomUploaderURLValidator.validatedWebURL(key) ?? URL(string: key) ?? URL(string: "about:blank")!
  }

  /// No delete API: the deletion link, when the uploader returns one, is opened from history instead.
  func delete(key: String) async throws {}

  func setExpiration(days: Int) async throws {}

  func removeExpiration() async throws {}

  /// Checks the selected uploader still exists. Nothing is sent; the editor's Test button does that.
  func validate() async throws {
    _ = try resolveUploader()
  }

  private func resolveUploader() throws -> CustomUploader {
    guard let uploaderID, let uploader = lookup(uploaderID) else {
      throw CustomUploaderError.uploaderNotFound
    }
    return uploader
  }
}
