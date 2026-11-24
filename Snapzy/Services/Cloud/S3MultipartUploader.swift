//
//  S3MultipartUploader.swift
//  Snapzy
//
//  AWS S3 Multipart Upload implementation using pure Foundation + AWS Signature V4
//

import Foundation
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "S3MultipartUploader")

/// Performs chunked multipart upload for large files to AWS S3 / Cloudflare R2
final class S3MultipartUploader {
  private let accessKey: String
  private let secretKey: String
  private let region: String
  private let endpoint: URL
  private let bucket: String
  private let session: URLSessionProtocol
  private let partSize: Int

  // 10MB parts (S3 minimum is 5MB, except the last part)
  static let defaultPartSize = 10 * 1024 * 1024
  // Threshold to route to multipart upload
  static let multipartThreshold = 50 * 1024 * 1024

  init(
    accessKey: String,
    secretKey: String,
    region: String,
    endpoint: URL,
    bucket: String,
    session: URLSessionProtocol = URLSession.shared,
    partSize: Int = defaultPartSize
  ) {
    self.accessKey = accessKey
    self.secretKey = secretKey
    self.region = region
    self.endpoint = URL(string: S3CloudProvider.trimmingTrailingSlashes(endpoint.absoluteString)) ?? endpoint
    self.bucket = bucket
    self.session = session
    self.partSize = partSize
  }

  /// Upload a large file in parts
  func upload(
    fileURL: URL,
    key: String,
    contentType: String,
    expireTime: CloudExpireTime,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> CloudUploadResult {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw CloudError.fileNotFound(fileURL)
    }

    let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let fileSize = fileAttributes[.size] as? Int64 ?? 0
    guard fileSize > 0 else {
      throw CloudError.uploadFailed(statusCode: 400, message: "File is empty")
    }

    logger.info("Initiating S3 multipart upload for \(key) (\(fileSize) bytes)")

    // 1. Initiate Multipart Upload
    let uploadId = try await initiateMultipartUpload(key: key, contentType: contentType, expireTime: expireTime)
    logger.info("Multipart upload initiated with ID: \(uploadId)")

    // Track part progress to report accurate overall progress
    let totalParts = Int(ceil(Double(fileSize) / Double(self.partSize)))
    let partProgresses = ThreadSafeDictionary<Int, Double>()
    for i in 1...totalParts {
      partProgresses[i] = 0.0
    }

    var completedParts: [(partNumber: Int, eTag: String)] = []

    do {
      let fileHandle = try FileHandle(forReadingFrom: fileURL)
      defer { try? fileHandle.close() }

      // 2. Upload Parts Sequentially
      for partNumber in 1...totalParts {
        let offset = UInt64(partNumber - 1) * UInt64(self.partSize)
        try fileHandle.seek(toOffset: offset)
        guard let partData = try fileHandle.read(upToCount: self.partSize), !partData.isEmpty else {
          throw CloudError.uploadFailed(statusCode: 500, message: "Failed to read part data at offset \(offset)")
        }

        var retryCount = 0
        var partETag: String? = nil

        while retryCount < 3 && partETag == nil {
          do {
            partETag = try await uploadPart(
              key: key,
              uploadId: uploadId,
              partNumber: partNumber,
              data: partData
            ) { partProgress in
              partProgresses[partNumber] = partProgress
              let overallProgress = partProgresses.allValues.reduce(0.0, +) / Double(totalParts)
              progress(min(overallProgress, 0.99)) // Cap at 99% until complete succeeds
            }
          } catch {
            retryCount += 1
            logger.warning("Failed to upload part \(partNumber) (attempt \(retryCount)/3): \(error.localizedDescription)")
            if retryCount >= 3 {
              throw error
            }
            // Exponential backoff
            try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
          }
        }

        guard let eTag = partETag else {
          throw CloudError.uploadFailed(statusCode: 500, message: "Part upload failed to return ETag")
        }

        completedParts.append((partNumber: partNumber, eTag: eTag))
      }

      // 3. Complete Multipart Upload
      logger.info("Completing multipart upload with ID: \(uploadId)")
      let publicURL = try await completeMultipartUpload(key: key, uploadId: uploadId, parts: completedParts)
      
      progress(1.0)
      logger.info("Multipart upload completed successfully: \(publicURL.absoluteString)")

      return CloudUploadResult(
        publicURL: publicURL,
        key: key,
        fileSize: fileSize,
        uploadedAt: Date()
      )
    } catch {
      logger.error("Multipart upload failed, aborting upload \(uploadId): \(error.localizedDescription)")
      // 4. Abort Multipart Upload on Failure
      try? await abortMultipartUpload(key: key, uploadId: uploadId)
      throw error
    }
  }

  // MARK: - HTTP API Operations

  private func initiateMultipartUpload(
    key: String,
    contentType: String,
    expireTime: CloudExpireTime
  ) async throws -> String {
    let url = URL(string: "\(endpoint.absoluteString)/\(bucket)/\(key)?uploads")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")

    if let seconds = expireTime.seconds {
      request.setValue("public, max-age=\(seconds)", forHTTPHeaderField: "Cache-Control")
    }

    let payloadHash = AWSV4Signer.sha256Hex("")
    let signedRequest = try AWSV4Signer.sign(
      request: request,
      accessKey: accessKey,
      secretKey: secretKey,
      region: region,
      payloadHash: payloadHash
    )

    let (data, response) = try await session.data(for: signedRequest)
    try validateResponse(response, data: data, operation: "InitiateMultipartUpload")

    guard let uploadId = parseUploadId(from: data) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw CloudError.uploadFailed(statusCode: 500, message: "Failed to parse UploadId from response: \(body)")
    }

    return uploadId
  }

  private func uploadPart(
    key: String,
    uploadId: String,
    partNumber: Int,
    data: Data,
    onProgress: @escaping @Sendable (Double) -> Void
  ) async throws -> String {
    let url = URL(string: "\(endpoint.absoluteString)/\(bucket)/\(key)?partNumber=\(partNumber)&uploadId=\(uploadId)")!
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")

    let payloadHash = AWSV4Signer.sha256Hex(data)
    let signedRequest = try AWSV4Signer.sign(
      request: request,
      accessKey: accessKey,
      secretKey: secretKey,
      region: region,
      payloadHash: payloadHash
    )

    // Upload chunk with progress
    let result = try await uploadChunkWithProgress(request: signedRequest, data: data, progress: onProgress)
    try validateResponse(result.response, data: result.data, operation: "UploadPart \(partNumber)")

    guard let httpResponse = result.response as? HTTPURLResponse,
          let eTag = httpResponse.value(forHTTPHeaderField: "ETag") else {
      throw CloudError.invalidResponse
    }

    // Clean ETag (S3 returns wrapped in quotes, e.g. "etag-value")
    return eTag.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
  }

  private func completeMultipartUpload(
    key: String,
    uploadId: String,
    parts: [(partNumber: Int, eTag: String)]
  ) async throws -> URL {
    let url = URL(string: "\(endpoint.absoluteString)/\(bucket)/\(key)?uploadId=\(uploadId)")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/xml", forHTTPHeaderField: "Content-Type")

    // Sort parts by number as S3 requires
    let sortedParts = parts.sorted(by: { $0.partNumber < $1.partNumber })

    var xml = "<CompleteMultipartUpload>"
    for part in sortedParts {
      xml += "<Part><PartNumber>\(part.partNumber)</PartNumber><ETag>\"\(part.eTag)\"</ETag></Part>"
    }
    xml += "</CompleteMultipartUpload>"

    let bodyData = xml.data(using: .utf8)!
    request.httpBody = bodyData
    request.setValue("\(bodyData.count)", forHTTPHeaderField: "Content-Length")

    let payloadHash = AWSV4Signer.sha256Hex(bodyData)
    let signedRequest = try AWSV4Signer.sign(
      request: request,
      accessKey: accessKey,
      secretKey: secretKey,
      region: region,
      payloadHash: payloadHash
    )

    let (data, response) = try await session.data(for: signedRequest)
    try validateResponse(response, data: data, operation: "CompleteMultipartUpload")

    // Path-style object URL; S3CloudProvider swaps in its custom-domain public URL.
    return URL(string: "\(endpoint.absoluteString)/\(bucket)/\(key)")!
  }

  private func abortMultipartUpload(key: String, uploadId: String) async throws {
    let url = URL(string: "\(endpoint.absoluteString)/\(bucket)/\(key)?uploadId=\(uploadId)")!
    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"

    let payloadHash = AWSV4Signer.sha256Hex("")
    let signedRequest = try AWSV4Signer.sign(
      request: request,
      accessKey: accessKey,
      secretKey: secretKey,
      region: region,
      payloadHash: payloadHash
    )

    let (data, response) = try await session.data(for: signedRequest)
    try validateResponse(response, data: data, operation: "AbortMultipartUpload")
  }

  // MARK: - Helpers

  private func validateResponse(_ response: URLResponse, data: Data, operation: String) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
      throw CloudError.invalidResponse
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? "No response body"
      logger.error("\(operation) failed: HTTP \(httpResponse.statusCode) — \(body)")
      throw CloudError.uploadFailed(statusCode: httpResponse.statusCode, message: body)
    }
  }

  private func parseUploadId(from xmlData: Data) -> String? {
    let xmlString = String(data: xmlData, encoding: .utf8) ?? ""
    guard let startRange = xmlString.range(of: "<UploadId>") else { return nil }
    guard let endRange = xmlString.range(of: "</UploadId>") else { return nil }
    return String(xmlString[startRange.upperBound..<endRange.lowerBound])
  }

  private func uploadChunkWithProgress(
    request: URLRequest,
    data: Data,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> (data: Data, response: URLResponse) {
    if !(session is URLSession) {
      progress(1.0)
      return try await session.data(for: request)
    }

    return try await withCheckedThrowingContinuation { continuation in
      let delegate = MultipartProgressDelegate(progress: progress) { result in
        continuation.resume(with: result)
      }
      let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
      let task = session.uploadTask(with: request, from: data)
      delegate.task = task
      task.resume()
    }
  }
}

// MARK: - Thread Safe Dictionary Helper

private final class ThreadSafeDictionary<Key: Hashable, Value>: @unchecked Sendable {
  private var dictionary: [Key: Value] = [:]
  private let queue = DispatchQueue(label: "com.snapzy.multipart.dictionary", attributes: .concurrent)

  subscript(key: Key) -> Value? {
    get { queue.sync { dictionary[key] } }
    set { queue.async(flags: .barrier) { self.dictionary[key] = newValue } }
  }

  var allValues: [Value] {
    queue.sync { Array(dictionary.values) }
  }
}

// MARK: - Multipart Progress Delegate

private final class MultipartProgressDelegate: NSObject, URLSessionTaskDelegate,
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
