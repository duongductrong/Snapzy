//
//  S3CloudProvider.swift
//  Snapzy
//
//  AWS S3 cloud provider using pure Foundation + AWS Signature V4
//

import Foundation
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "S3CloudProvider")

/// AWS S3 cloud storage provider
final class S3CloudProvider: CloudProvider {
  let providerType: CloudProviderType = .awsS3

  private let accessKey: String
  private let secretKey: String
  private let bucket: String
  private let region: String
  private let endpoint: URL
  private let customDomain: String?

  init(config: CloudConfiguration, accessKey: String, secretKey: String) {
    self.accessKey = accessKey
    self.secretKey = secretKey
    self.bucket = config.bucket
    self.region = config.region.isEmpty ? "us-east-1" : config.region
    self.customDomain = config.customDomain

    if let endpointStr = config.endpoint, !endpointStr.isEmpty {
      self.endpoint = URL(string: endpointStr)!
    } else {
      // Default S3 endpoint (path-style)
      self.endpoint = URL(string: "https://s3.\(self.region).amazonaws.com")!
    }
  }

  // MARK: - Upload

  func upload(
    fileURL: URL,
    contentType: String,
    expireTime: CloudExpireTime,
    existingKey: String? = nil,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> CloudUploadResult {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw CloudError.fileNotFound(fileURL)
    }

    let fileData = try Data(contentsOf: fileURL)
    let fileSize = Int64(fileData.count)
    let key = existingKey ?? generateObjectKey(fileName: fileURL.lastPathComponent)

    // Build PUT request
    let objectURL = buildObjectURL(key: key)
    var request = URLRequest(url: objectURL)
    request.httpMethod = "PUT"
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    request.setValue("\(fileSize)", forHTTPHeaderField: "Content-Length")

    // Set cache-control based on expire time for CDN-aware caching
    if let seconds = expireTime.seconds {
      request.setValue("public, max-age=\(seconds)", forHTTPHeaderField: "Cache-Control")
    }

    // Compute payload hash
    let payloadHash = AWSV4Signer.sha256Hex(fileData)

    // Sign the request
    let signedRequest = try AWSV4Signer.sign(
      request: request,
      accessKey: accessKey,
      secretKey: secretKey,
      region: region,
      payloadHash: payloadHash
    )

    // Upload with progress tracking
    let result = try await uploadWithProgress(
      request: signedRequest,
      data: fileData,
      progress: progress
    )

    guard let httpResponse = result.response as? HTTPURLResponse else {
      throw CloudError.invalidResponse
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let body = String(data: result.data, encoding: .utf8) ?? "No response body"
      logger.error("S3 upload failed: HTTP \(httpResponse.statusCode) — \(body)")
      throw CloudError.uploadFailed(statusCode: httpResponse.statusCode, message: body)
    }

    let publicURL = generatePublicURL(for: key)
    logger.info("S3 upload succeeded: \(key) → \(publicURL.absoluteString)")

    return CloudUploadResult(
      publicURL: publicURL,
      key: key,
      fileSize: fileSize,
      uploadedAt: Date()
    )
  }

  // MARK: - Public URL

  func generatePublicURL(for key: String) -> URL {
    if let domain = customDomain, !domain.isEmpty {
      let scheme = domain.hasPrefix("http") ? "" : "https://"
      return URL(string: "\(scheme)\(domain)/\(key)")!
    }
    // Default: presigned URL or path-style
    return buildObjectURL(key: key)
  }

  // MARK: - Validate

  func validate() async throws {
    // HEAD bucket to verify credentials
    let url = URL(string: "\(endpoint.absoluteString)/\(bucket)")!
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"

    let signedRequest = try AWSV4Signer.sign(
      request: request,
      accessKey: accessKey,
      secretKey: secretKey,
      region: region,
      payloadHash: AWSV4Signer.sha256Hex("")
    )

    let (_, response) = try await URLSession.shared.data(for: signedRequest)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw CloudError.invalidResponse
    }

    guard (200...404).contains(httpResponse.statusCode) else {
      if httpResponse.statusCode == 403 {
        throw CloudError.invalidCredentials
      }
      throw CloudError.uploadFailed(
        statusCode: httpResponse.statusCode,
        message: "Bucket validation failed"
      )
    }

    logger.info("S3 credentials validated successfully")
  }

  // MARK: - Delete

  func delete(key: String) async throws {
    let objectURL = buildObjectURL(key: key)
    var request = URLRequest(url: objectURL)
    request.httpMethod = "DELETE"

    let signedRequest = try AWSV4Signer.sign(
      request: request,
      accessKey: accessKey,
      secretKey: secretKey,
      region: region,
      payloadHash: AWSV4Signer.sha256Hex("")
    )

    let (data, response) = try await URLSession.shared.data(for: signedRequest)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw CloudError.invalidResponse
    }

    // S3 returns 204 on successful delete. 404 is also OK (already deleted / expired).
    guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
      let body = String(data: data, encoding: .utf8) ?? "No response body"
      logger.error("S3 delete failed: HTTP \(httpResponse.statusCode) — \(body)")
      throw CloudError.uploadFailed(statusCode: httpResponse.statusCode, message: "Delete failed: \(body)")
    }

    logger.info("S3 delete succeeded: \(key)")
  }

  // MARK: - Lifecycle Rules

  /// Snapzy lifecycle rule identifier
  private static let lifecycleRuleID = "snapzy-auto-expire"
  /// Prefix all Snapzy objects share
  private static let objectPrefix = "snapzy/"

  func setExpiration(days: Int) async throws {
    // 1. Get existing rules (excluding our old rule)
    var existingRules = try await getLifecycleRulesXML()
    existingRules.removeAll { $0.contains("<ID>\(Self.lifecycleRuleID)</ID>") }

    // 2. Build new Snapzy rule
    let snapzyRule = """
      <Rule>
        <ID>\(Self.lifecycleRuleID)</ID>
        <Filter><Prefix>\(Self.objectPrefix)</Prefix></Filter>
        <Status>Enabled</Status>
        <Expiration><Days>\(days)</Days></Expiration>
      </Rule>
      """
    existingRules.append(snapzyRule)

    // 3. PUT merged config
    try await putLifecycleConfiguration(rules: existingRules)
    logger.info("Lifecycle rule set: expire snapzy/ objects after \(days) days")
  }

  func removeExpiration() async throws {
    var existingRules = try await getLifecycleRulesXML()
    let before = existingRules.count
    existingRules.removeAll { $0.contains("<ID>\(Self.lifecycleRuleID)</ID>") }

    if existingRules.isEmpty {
      // Delete entire lifecycle config if no rules remain
      try await deleteLifecycleConfiguration()
    } else if existingRules.count < before {
      try await putLifecycleConfiguration(rules: existingRules)
    }
    logger.info("Lifecycle rule removed for snapzy/ prefix")
  }

  // MARK: - Lifecycle Helpers

  /// Fetch existing lifecycle rules as raw XML strings (one per <Rule>)
  private func getLifecycleRulesXML() async throws -> [String] {
    let url = URL(string: "\(endpoint.absoluteString)/\(bucket)?lifecycle")!
    var request = URLRequest(url: url)
    request.httpMethod = "GET"

    let signedRequest = try AWSV4Signer.sign(
      request: request,
      accessKey: accessKey,
      secretKey: secretKey,
      region: region,
      payloadHash: AWSV4Signer.sha256Hex("")
    )

    let (data, response) = try await URLSession.shared.data(for: signedRequest)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw CloudError.invalidResponse
    }

    // 404 = no lifecycle config exists yet
    if httpResponse.statusCode == 404 {
      return []
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      logger.error("GET lifecycle failed: HTTP \(httpResponse.statusCode) — \(body)")
      throw CloudError.uploadFailed(
        statusCode: httpResponse.statusCode,
        message: "Failed to get lifecycle config: \(body)"
      )
    }

    // Parse XML to extract individual <Rule>...</Rule> blocks
    return LifecycleXMLParser.parseRules(from: data)
  }

  /// PUT a lifecycle configuration with the given rules
  private func putLifecycleConfiguration(rules: [String]) async throws {
    let xmlBody = """
      <?xml version="1.0" encoding="UTF-8"?>
      <LifecycleConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
      \(rules.joined(separator: "\n"))
      </LifecycleConfiguration>
      """

    let bodyData = xmlBody.data(using: .utf8)!
    let url = URL(string: "\(endpoint.absoluteString)/\(bucket)?lifecycle")!
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
    request.setValue("\(bodyData.count)", forHTTPHeaderField: "Content-Length")

    // S3 requires Content-MD5 for lifecycle configuration
    let md5Hash = bodyData.md5Base64()
    request.setValue(md5Hash, forHTTPHeaderField: "Content-MD5")

    let payloadHash = AWSV4Signer.sha256Hex(bodyData)
    let signedRequest = try AWSV4Signer.sign(
      request: request,
      accessKey: accessKey,
      secretKey: secretKey,
      region: region,
      payloadHash: payloadHash
    )

    let (data, response) = try await URLSession.shared.upload(for: signedRequest, from: bodyData)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw CloudError.invalidResponse
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      logger.error("PUT lifecycle failed: HTTP \(httpResponse.statusCode) — \(body)")
      throw CloudError.uploadFailed(
        statusCode: httpResponse.statusCode,
        message: "Failed to set lifecycle config: \(body)"
      )
    }
  }

  /// DELETE entire lifecycle configuration from the bucket
  private func deleteLifecycleConfiguration() async throws {
    let url = URL(string: "\(endpoint.absoluteString)/\(bucket)?lifecycle")!
    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"

    let signedRequest = try AWSV4Signer.sign(
      request: request,
      accessKey: accessKey,
      secretKey: secretKey,
      region: region,
      payloadHash: AWSV4Signer.sha256Hex("")
    )

    let (data, response) = try await URLSession.shared.data(for: signedRequest)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw CloudError.invalidResponse
    }

    guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
      let body = String(data: data, encoding: .utf8) ?? ""
      logger.error("DELETE lifecycle failed: HTTP \(httpResponse.statusCode) — \(body)")
      throw CloudError.uploadFailed(
        statusCode: httpResponse.statusCode,
        message: "Failed to delete lifecycle config: \(body)"
      )
    }
  }

  // MARK: - Helpers

  private func buildObjectURL(key: String) -> URL {
    // Path-style: https://s3.region.amazonaws.com/bucket/key
    URL(string: "\(endpoint.absoluteString)/\(bucket)/\(key)")!
  }

  private func generateObjectKey(fileName: String) -> String {
    let timestamp = Int(Date().timeIntervalSince1970)
    let uuid = UUID().uuidString.prefix(8).lowercased()
    let ext = (fileName as NSString).pathExtension
    let name = (fileName as NSString).deletingPathExtension
      .replacingOccurrences(of: " ", with: "-")
      .lowercased()
    return "snapzy/\(timestamp)-\(uuid)-\(name).\(ext)"
  }

  // MARK: - Upload with Progress

  private func uploadWithProgress(
    request: URLRequest,
    data: Data,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> (data: Data, response: URLResponse) {
    try await withCheckedThrowingContinuation { continuation in
      let delegate = UploadProgressDelegate(progress: progress) { result in
        continuation.resume(with: result)
      }
      let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
      let task = session.uploadTask(with: request, from: data)
      delegate.task = task
      task.resume()
    }
  }
}

// MARK: - Upload Progress Delegate

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate,
  URLSessionDataDelegate, @unchecked Sendable
{
  private let progressHandler: @Sendable (Double) -> Void
  private let completion: (Result<(data: Data, response: URLResponse), Error>) -> Void
  private var responseData = Data()
  weak var task: URLSessionUploadTask?

  init(
    progress: @escaping @Sendable (Double) -> Void,
    completion: @escaping (Result<(data: Data, response: URLResponse), Error>) -> Void
  ) {
    self.progressHandler = progress
    self.completion = completion
    super.init()
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    guard totalBytesExpectedToSend > 0 else { return }
    let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
    progressHandler(min(progress, 1.0))
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    responseData.append(data)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error = error {
      completion(.failure(CloudError.networkError(error)))
    } else if let response = task.response {
      completion(.success((data: responseData, response: response)))
    } else {
      completion(.failure(CloudError.invalidResponse))
    }
    session.invalidateAndCancel()
  }
}
