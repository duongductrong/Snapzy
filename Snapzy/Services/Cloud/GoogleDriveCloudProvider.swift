//
//  GoogleDriveCloudProvider.swift
//  Snapzy
//
//  Created by DeepMind on 2026-07-12.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "GoogleDriveCloudProvider")

/// Google Drive cloud provider implementation using Drive v3 API.
final class GoogleDriveCloudProvider: CloudProvider {
  let providerType: CloudProviderType = .googleDrive

  private let clientId: String
  private let clientSecret: String
  private let refreshToken: String
  private let folderName: String

  private var cachedAccessToken: String?
  private var tokenExpiresAt: Date?
  private let session: URLSession

  init(
    clientId: String,
    clientSecret: String,
    refreshToken: String,
    folderName: String,
    session: URLSession = .shared
  ) {
    self.clientId = clientId
    self.clientSecret = clientSecret
    self.refreshToken = refreshToken
    self.folderName = folderName.isEmpty ? "Snapzy" : folderName
    self.session = session
  }

  // MARK: - CloudProvider Protocol

  func upload(
    fileURL: URL,
    contentType: String,
    expireTime: CloudExpireTime,
    existingKey: String? = nil,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> CloudUploadResult {
    logger.info("Google Drive upload starting: \(fileURL.lastPathComponent)")

    // 1. Ensure access token is valid
    let accessToken = try await ensureValidAccessToken()

    // 2. Ensure parent folder exists
    let folderId = try await ensureFolder(accessToken: accessToken)

    // 3. Determine file size to choose upload strategy
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    guard let fileSize = attributes[.size] as? Int64 else {
      throw CloudError.fileNotFound(fileURL)
    }

    let fileId: String
    // Use simple multipart upload for <= 5MB, resumable for larger files
    if fileSize <= 5 * 1024 * 1024 {
      fileId = try await performMultipartUpload(
        fileURL: fileURL,
        fileSize: fileSize,
        contentType: contentType,
        folderId: folderId,
        accessToken: accessToken,
        existingKey: existingKey,
        progress: progress
      )
    } else {
      fileId = try await performResumableUpload(
        fileURL: fileURL,
        fileSize: fileSize,
        contentType: contentType,
        folderId: folderId,
        accessToken: accessToken,
        existingKey: existingKey,
        progress: progress
      )
    }

    // 4. Set permissions to anyone/reader for sharing
    try await setFilePublicPermission(fileId: fileId, accessToken: accessToken)

    let publicURL = generatePublicURL(for: fileId)
    return CloudUploadResult(
      publicURL: publicURL,
      key: fileId,
      fileSize: fileSize,
      uploadedAt: Date()
    )
  }

  func generatePublicURL(for key: String) -> URL {
    // Formats sharing view URL
    return URL(string: "https://drive.google.com/file/d/\(key)/view")!
  }

  func delete(key: String) async throws {
    logger.info("Google Drive deleting file: \(key)")
    let accessToken = try await ensureValidAccessToken()

    var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(key)")!)
    request.httpMethod = "DELETE"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let (_, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw CloudError.invalidResponse
    }

    // Google API returns 204 No Content on success
    guard httpResponse.statusCode == 204 || httpResponse.statusCode == 404 else {
      throw CloudError.uploadFailed(statusCode: httpResponse.statusCode, message: "Failed to delete file from Google Drive")
    }
  }

  func setExpiration(days: Int) async throws {
    // Google Drive does not support lifecycle expiration rules. Graceful no-op.
    logger.info("Google Drive setExpiration called (\(days) days). Custom lifecycle rules are unsupported, skipping.")
  }

  func removeExpiration() async throws {
    // Google Drive does not support lifecycle expiration rules. Graceful no-op.
    logger.info("Google Drive removeExpiration called. Custom lifecycle rules are unsupported, skipping.")
  }

  func validate() async throws {
    logger.info("Google Drive validating configuration")
    let accessToken = try await ensureValidAccessToken()

    // Test API access by listing files with a limit of 1
    var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
    components.queryItems = [URLQueryItem(name: "pageSize", value: "1")]

    var request = URLRequest(url: components.url!)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw CloudError.invalidResponse
    }

    guard httpResponse.statusCode == 200 else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw CloudError.uploadFailed(statusCode: httpResponse.statusCode, message: "Validation failed: \(body)")
    }
  }

  // MARK: - Token Management

  private func ensureValidAccessToken() async throws -> String {
    if let cached = cachedAccessToken, let expires = tokenExpiresAt, expires > Date().addingTimeInterval(60) {
      return cached
    }

    logger.info("Refreshing Google Drive access token")
    guard !refreshToken.isEmpty else {
      throw CloudError.googleDriveAuthExpired
    }

    do {
      let tokens = try await GoogleDriveOAuthService.shared.refreshAccessToken(
        refreshToken: refreshToken,
        clientId: clientId,
        clientSecret: clientSecret
      )
      
      // Save refresh token back in case Google rotated it
      if tokens.refreshToken != refreshToken {
        try? CloudManager.shared.saveGoogleRefreshToken(tokens.refreshToken)
      }

      self.cachedAccessToken = tokens.accessToken
      self.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
      return tokens.accessToken
    } catch {
      logger.error("Failed to refresh access token: \(error.localizedDescription)")
      throw Self.tokenRefreshFailure(error)
    }
  }

  /// Google answers 400 (`invalid_grant`, `invalid_client`) or 401 when the saved sign-in is no
  /// longer usable; only a reconnect fixes that. Anything else (offline, 5xx) is passed through
  /// so the user is not told to reconnect when the network is the problem.
  static func tokenRefreshFailure(_ error: Error) -> Error {
    if case CloudError.uploadFailed(let statusCode, _) = error, statusCode == 400 || statusCode == 401 {
      return CloudError.googleDriveAuthExpired
    }
    return error
  }

  // MARK: - Folder Management

  private func ensureFolder(accessToken: String) async throws -> String {
    // 1. Check cached folder ID in defaults
    let cacheKey = "cloud.google.folderId.\(folderName.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"
    if let cachedId = UserDefaults.standard.string(forKey: cacheKey) {
      // Validate cached folder still exists
      if try await folderExists(folderId: cachedId, accessToken: accessToken) {
        return cachedId
      }
    }

    // 2. Query Google Drive for folder with folderName
    var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
    let query = "name='\(folderName)' and mimeType='application/vnd.google-apps.folder' and trashed=false"
    components.queryItems = [
      URLQueryItem(name: "q", value: query),
      URLQueryItem(name: "fields", value: "files(id)"),
      URLQueryItem(name: "pageSize", value: "1")
    ]

    var request = URLRequest(url: components.url!)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      throw CloudError.invalidResponse
    }

    struct FolderListResponse: Codable {
      struct Folder: Codable {
        let id: String
      }
      let files: [Folder]
    }

    let list = try JSONDecoder().decode(FolderListResponse.self, from: data)
    if let existingFolder = list.files.first {
      UserDefaults.standard.set(existingFolder.id, forKey: cacheKey)
      return existingFolder.id
    }

    // 3. Create new folder
    logger.info("Creating folder '\(self.folderName)' in Google Drive")
    var createRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files")!)
    createRequest.httpMethod = "POST"
    createRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let metadata: [String: Any] = [
      "name": folderName,
      "mimeType": "application/vnd.google-apps.folder"
    ]
    createRequest.httpBody = try JSONSerialization.data(withJSONObject: metadata)

    let (createData, createResponse) = try await session.data(for: createRequest)
    guard let createHttpResponse = createResponse as? HTTPURLResponse,
          (createHttpResponse.statusCode == 200 || createHttpResponse.statusCode == 201) else {
      throw CloudError.invalidResponse
    }

    struct FolderCreateResponse: Codable {
      let id: String
    }
    let folder = try JSONDecoder().decode(FolderCreateResponse.self, from: createData)
    UserDefaults.standard.set(folder.id, forKey: cacheKey)
    return folder.id
  }

  private func folderExists(folderId: String, accessToken: String) async throws -> Bool {
    var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(folderId)")!)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let (_, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      return false
    }
    return httpResponse.statusCode == 200
  }

  // MARK: - Upload Helpers

  private func performMultipartUpload(
    fileURL: URL,
    fileSize: Int64,
    contentType: String,
    folderId: String,
    accessToken: String,
    existingKey: String?,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> String {
    let boundary = "Boundary-\(UUID().uuidString)"
    let fileData = try Data(contentsOf: fileURL)

    let urlString: String
    let httpMethod: String

    if let fileId = existingKey {
      urlString = "https://www.googleapis.com/upload/drive/v3/files/\(fileId)?uploadType=multipart"
      httpMethod = "PATCH"
    } else {
      urlString = "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart"
      httpMethod = "POST"
    }

    var request = URLRequest(url: URL(string: urlString)!)
    request.httpMethod = httpMethod
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    var metadata: [String: Any] = [
      "name": fileURL.lastPathComponent
    ]
    if existingKey == nil {
      metadata["parents"] = [folderId]
    }

    let requestBody = try createMultipartBody(
      boundary: boundary,
      metadata: metadata,
      fileData: fileData,
      contentType: contentType
    )

    progress(0.1) // Start progress

    let (data, response) = try await session.upload(for: request, from: requestBody)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw CloudError.invalidResponse
    }

    guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw CloudError.uploadFailed(statusCode: httpResponse.statusCode, message: "Multipart upload failed: \(body)")
    }

    struct UploadResponse: Codable {
      let id: String
    }
    let uploadResult = try JSONDecoder().decode(UploadResponse.self, from: data)
    progress(1.0) // Upload complete

    return uploadResult.id
  }

  private func performResumableUpload(
    fileURL: URL,
    fileSize: Int64,
    contentType: String,
    folderId: String,
    accessToken: String,
    existingKey: String?,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> String {
    // Step 1: Initiate session
    let urlString: String
    let httpMethod: String

    if let fileId = existingKey {
      urlString = "https://www.googleapis.com/upload/drive/v3/files/\(fileId)?uploadType=resumable"
      httpMethod = "PATCH"
    } else {
      urlString = "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable"
      httpMethod = "POST"
    }

    var initRequest = URLRequest(url: URL(string: urlString)!)
    initRequest.httpMethod = httpMethod
    initRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    initRequest.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
    initRequest.setValue(contentType, forHTTPHeaderField: "X-Upload-Content-Type")
    initRequest.setValue("\(fileSize)", forHTTPHeaderField: "X-Upload-Content-Length")

    var metadata: [String: Any] = [
      "name": fileURL.lastPathComponent
    ]
    if existingKey == nil {
      metadata["parents"] = [folderId]
    }
    initRequest.httpBody = try JSONSerialization.data(withJSONObject: metadata)

    let (_, initResponse) = try await session.data(for: initRequest)
    guard let initHttpResponse = initResponse as? HTTPURLResponse,
          (initHttpResponse.statusCode == 200 || initHttpResponse.statusCode == 201),
          let sessionURLString = initHttpResponse.value(forHTTPHeaderField: "Location"),
          let sessionURL = URL(string: sessionURLString) else {
      throw CloudError.invalidResponse
    }

    // Step 2: Upload chunks
    let fileHandle = try FileHandle(forReadingFrom: fileURL)
    defer { try? fileHandle.close() }

    let chunkSize = 1 * 1024 * 1024 // 1 MB chunks
    var bytesUploaded: Int64 = 0

    while bytesUploaded < fileSize {
      let bytesRemaining = fileSize - bytesUploaded
      let currentChunkSize = Int(min(Int64(chunkSize), bytesRemaining))

      try fileHandle.seek(toOffset: UInt64(bytesUploaded))
      guard let chunkData = try fileHandle.read(upToCount: currentChunkSize) else {
        throw CloudError.fileNotFound(fileURL)
      }

      var uploadRequest = URLRequest(url: sessionURL)
      uploadRequest.httpMethod = "PUT"
      uploadRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
      uploadRequest.setValue("\(currentChunkSize)", forHTTPHeaderField: "Content-Length")
      uploadRequest.setValue(
        "bytes \(bytesUploaded)-\(bytesUploaded + Int64(currentChunkSize) - 1)/\(fileSize)",
        forHTTPHeaderField: "Content-Range"
      )

      let (data, response) = try await session.upload(for: uploadRequest, from: chunkData)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw CloudError.invalidResponse
      }

      bytesUploaded += Int64(currentChunkSize)
      progress(Double(bytesUploaded) / Double(fileSize))

      if bytesUploaded == fileSize {
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
          let body = String(data: data, encoding: .utf8) ?? ""
          throw CloudError.uploadFailed(statusCode: httpResponse.statusCode, message: "Resumable upload final chunk failed: \(body)")
        }

        struct UploadResponse: Codable {
          let id: String
        }
        let uploadResult = try JSONDecoder().decode(UploadResponse.self, from: data)
        return uploadResult.id
      } else {
        // HTTP 308 Resume Incomplete is expected for intermediate chunks
        guard httpResponse.statusCode == 308 else {
          let body = String(data: data, encoding: .utf8) ?? ""
          throw CloudError.uploadFailed(statusCode: httpResponse.statusCode, message: "Resumable upload chunk failed: \(body)")
        }
      }
    }

    throw CloudError.invalidResponse
  }

  private func createMultipartBody(
    boundary: String,
    metadata: [String: Any],
    fileData: Data,
    contentType: String
  ) throws -> Data {
    var body = Data()
    let metadataData = try JSONSerialization.data(withJSONObject: metadata)

    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
    body.append(metadataData)
    body.append("\r\n".data(using: .utf8)!)

    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
    body.append(fileData)
    body.append("\r\n".data(using: .utf8)!)

    body.append("--\(boundary)--\r\n".data(using: .utf8)!)
    return body
  }

  private func setFilePublicPermission(fileId: String, accessToken: String) async throws {
    var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)/permissions")!)
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
      "role": "reader",
      "type": "anyone"
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw CloudError.invalidResponse
    }

    guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
      let bodyStr = String(data: data, encoding: .utf8) ?? ""
      logger.error("Failed to set public permissions: \(httpResponse.statusCode), \(bodyStr)")
      throw CloudError.uploadFailed(statusCode: httpResponse.statusCode, message: "Failed to share file on Google Drive")
    }
  }
}
