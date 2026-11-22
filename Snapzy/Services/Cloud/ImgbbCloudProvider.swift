//
//  ImgbbCloudProvider.swift
//  Snapzy
//
//  imgbb image host provider. Images get a public link; there is no bucket,
//  no lifecycle rule, and no delete API (imgbb returns a delete page instead).
//

import Foundation
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "ImgbbCloudProvider")

final class ImgbbCloudProvider: CloudProvider {
  let providerType: CloudProviderType = .imgbb

  static let defaultEndpoint = URL(string: "https://api.imgbb.com/1/upload")!
  /// imgbb rejects files above 32 MB.
  static let maxFileSize: Int64 = 32 * 1024 * 1024
  /// imgbb accepts `expiration` between 60 seconds and 180 days.
  static let expirationRange: ClosedRange<Int> = 60...15_552_000
  /// Chevereto (imgbb's engine) uses error code 100 for a missing or wrong API key.
  static let invalidKeyErrorCode = 100
  /// Chevereto's "Empty upload source." code, returned when the key is fine but no image was sent.
  static let emptySourceErrorCode = 130

  private let apiKey: String
  private let endpoint: URL
  private let sessionConfiguration: URLSessionConfiguration

  init(
    apiKey: String,
    endpoint: URL = ImgbbCloudProvider.defaultEndpoint,
    sessionConfiguration: URLSessionConfiguration = .default
  ) {
    self.apiKey = apiKey
    self.endpoint = endpoint
    self.sessionConfiguration = sessionConfiguration
  }

  // MARK: - CloudProvider

  /// imgbb can't replace an image, so `existingKey` is ignored and every call makes a new link.
  func upload(
    fileURL: URL,
    contentType: String,
    expireTime: CloudExpireTime,
    existingKey: String?,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> CloudUploadResult {
    guard contentType.hasPrefix("image/") else {
      throw CloudError.unsupportedFileType(provider: providerType.displayName)
    }

    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw CloudError.fileNotFound(fileURL)
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    guard fileSize <= Self.maxFileSize else {
      throw CloudError.fileTooLarge(provider: providerType.displayName, limitBytes: Self.maxFileSize)
    }

    let fileData = try Data(contentsOf: fileURL)
    let boundary = "SnapzyBoundary-\(UUID().uuidString)"
    var fields = [("key", apiKey)]
    if let seconds = Self.expirationSeconds(for: expireTime) {
      fields.append(("expiration", String(seconds)))
    }
    let body = Self.makeMultipartBody(
      fields: fields,
      fileField: "image",
      fileName: fileURL.lastPathComponent,
      contentType: contentType,
      fileData: fileData,
      boundary: boundary
    )
    let request = makeRequest(boundary: boundary)

    logger.info("imgbb upload starting (\(fileSize) bytes)")
    let (data, response) = try await uploadWithProgress(request: request, body: body, progress: progress)
    let payload = try Self.parseResponse(data: data, response: response)

    guard let urlString = payload.data?.url, let publicURL = URL(string: urlString),
      let id = payload.data?.id
    else {
      throw CloudError.invalidResponse
    }

    let deleteURL = payload.data?.deleteURL.flatMap(URL.init(string:))
    let reportedSize = payload.data?.size.flatMap { Int64($0.value) } ?? fileSize
    return CloudUploadResult(
      publicURL: publicURL,
      key: id,
      fileSize: reportedSize,
      uploadedAt: Date(),
      deleteURL: deleteURL
    )
  }

  /// imgbb links can't be rebuilt from the id alone; the record keeps the URL returned on upload.
  func generatePublicURL(for key: String) -> URL {
    URL(string: "https://ibb.co/\(key)")!
  }

  /// imgbb has no delete API. Deleting happens on the delete page returned at upload,
  /// which `CloudManager` opens in the browser.
  func delete(key: String) async throws {
    logger.info("imgbb delete skipped; imgbb has no delete API")
  }

  /// Expiration is sent with each upload, so there is no rule to set.
  func setExpiration(days: Int) async throws {}

  func removeExpiration() async throws {}

  /// Sends the key with no image. imgbb answers a bad key with error code 100 and a good
  /// key with an "empty upload source" error, so the check never creates an image.
  func validate() async throws {
    let boundary = "SnapzyBoundary-\(UUID().uuidString)"
    let body = Self.makeMultipartBody(
      fields: [("key", apiKey)],
      fileField: nil,
      fileName: nil,
      contentType: nil,
      fileData: nil,
      boundary: boundary
    )
    var request = makeRequest(boundary: boundary)
    request.httpBody = body

    let session = URLSession(configuration: sessionConfiguration)
    defer { session.finishTasksAndInvalidate() }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw CloudError.networkError(error)
    }
    try Self.interpretValidationResponse(data: data, response: response)
  }

  // MARK: - Request Building

  private func makeRequest(boundary: String) -> URLRequest {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 120
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }

  static func expirationSeconds(for expireTime: CloudExpireTime) -> Int? {
    guard let seconds = expireTime.seconds else { return nil }
    return min(max(seconds, expirationRange.lowerBound), expirationRange.upperBound)
  }

  static func makeMultipartBody(
    fields: [(String, String)],
    fileField: String?,
    fileName: String?,
    contentType: String?,
    fileData: Data?,
    boundary: String
  ) -> Data {
    var body = Data()
    let lineBreak = "\r\n"

    for (name, value) in fields {
      body.append("--\(boundary)\(lineBreak)")
      body.append("Content-Disposition: form-data; name=\"\(name)\"\(lineBreak)\(lineBreak)")
      body.append("\(value)\(lineBreak)")
    }

    if let fileField, let fileData {
      let safeName = (fileName ?? "image")
        .replacingOccurrences(of: "\"", with: "")
        .replacingOccurrences(of: "\r", with: "")
        .replacingOccurrences(of: "\n", with: "")
      body.append("--\(boundary)\(lineBreak)")
      body.append(
        "Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(safeName)\"\(lineBreak)"
      )
      body.append("Content-Type: \(contentType ?? "application/octet-stream")\(lineBreak)\(lineBreak)")
      body.append(fileData)
      body.append(lineBreak)
    }

    body.append("--\(boundary)--\(lineBreak)")
    return body
  }

  // MARK: - Response Handling

  struct APIResponse: Decodable {
    struct ImageData: Decodable {
      let id: String?
      let url: String?
      let deleteURL: String?
      let size: FlexibleString?

      enum CodingKeys: String, CodingKey {
        case id, url, size
        case deleteURL = "delete_url"
      }
    }

    struct APIError: Decodable {
      let message: String?
      let code: Int?
    }

    let data: ImageData?
    let success: Bool?
    let error: APIError?
  }

  /// imgbb sends `size` as a number on upload; accept a string too.
  struct FlexibleString: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let int = try? container.decode(Int64.self) {
        value = String(int)
      } else {
        value = try container.decode(String.self)
      }
    }
  }

  static func parseResponse(data: Data, response: URLResponse) throws -> APIResponse {
    guard let http = response as? HTTPURLResponse else {
      throw CloudError.invalidResponse
    }
    let decoded = try? JSONDecoder().decode(APIResponse.self, from: data)

    guard (200..<300).contains(http.statusCode), let decoded, decoded.success != false else {
      if decoded?.error?.code == invalidKeyErrorCode || http.statusCode == 401 || http.statusCode == 403 {
        throw CloudError.invalidCredentials
      }
      let message = decoded?.error?.message ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
      throw CloudError.uploadFailed(statusCode: http.statusCode, message: message)
    }
    return decoded
  }

  static func interpretValidationResponse(data: Data, response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else {
      throw CloudError.invalidResponse
    }
    let decoded = try? JSONDecoder().decode(APIResponse.self, from: data)

    if decoded?.error?.code == invalidKeyErrorCode || http.statusCode == 401 || http.statusCode == 403 {
      throw CloudError.invalidCredentials
    }
    guard let decoded else {
      throw CloudError.invalidResponse
    }
    // imgbb accepted the key and only complained about the missing image.
    let message = decoded.error?.message ?? ""
    if decoded.error?.code == emptySourceErrorCode
      || message.range(of: "upload source", options: .caseInsensitive) != nil
    {
      return
    }
    // Anything else (rate limit, outage, proxy page) says nothing about the key.
    throw CloudError.uploadFailed(
      statusCode: http.statusCode,
      message: message.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: http.statusCode) : message
    )
  }

  // MARK: - Upload with Progress

  private func uploadWithProgress(
    request: URLRequest,
    body: Data,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> (Data, URLResponse) {
    let taskBox = UploadTaskBox()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let delegate = ImgbbUploadDelegate(progress: progress) { result in
          continuation.resume(with: result)
        }
        let session = URLSession(configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)
        let task = session.uploadTask(with: request, from: body)
        taskBox.set(task)
        task.resume()
      }
    } onCancel: {
      // Stop a public upload the caller no longer wants; the delegate then fails the continuation.
      taskBox.cancel()
    }
  }
}

/// Holds the running upload so cancellation can reach it, even if it arrives before the task starts.
private nonisolated final class UploadTaskBox: @unchecked Sendable {
  private let lock = NSLock()
  private var task: URLSessionTask?
  private var isCancelled = false

  func set(_ task: URLSessionTask) {
    let cancelNow = lock.withLock { () -> Bool in
      self.task = task
      return isCancelled
    }
    if cancelNow { task.cancel() }
  }

  func cancel() {
    let task = lock.withLock { () -> URLSessionTask? in
      isCancelled = true
      return self.task
    }
    task?.cancel()
  }
}

// MARK: - Upload Delegate

private final class ImgbbUploadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  private let progressHandler: @Sendable (Double) -> Void
  private let completion: (Result<(Data, URLResponse), Error>) -> Void
  private var responseData = Data()

  init(
    progress: @escaping @Sendable (Double) -> Void,
    completion: @escaping (Result<(Data, URLResponse), Error>) -> Void
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
    progressHandler(min(Double(totalBytesSent) / Double(totalBytesExpectedToSend), 1.0))
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    responseData.append(data)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error {
      completion(.failure(CloudError.networkError(error)))
    } else if let response = task.response {
      completion(.success((responseData, response)))
    } else {
      completion(.failure(CloudError.invalidResponse))
    }
    session.finishTasksAndInvalidate()
  }
}

private extension Data {
  mutating func append(_ string: String) {
    append(Data(string.utf8))
  }
}
