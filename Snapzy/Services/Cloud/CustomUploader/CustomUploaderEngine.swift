//
//  CustomUploaderEngine.swift
//  Snapzy
//
//  Sends a file to a custom HTTP uploader and reads the link from the response.
//  Multipart bodies are written to a temp file and uploaded from disk.
//  Secret values and header values are never logged.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "CustomUploaderEngine")

final class CustomUploaderEngine {

  private let sessionConfiguration: URLSessionConfiguration
  private let temporaryDirectory: URL

  init(
    sessionConfiguration: URLSessionConfiguration = .default,
    temporaryDirectory: URL = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyCustomUploader", isDirectory: true)
  ) {
    self.sessionConfiguration = sessionConfiguration
    self.temporaryDirectory = temporaryDirectory
  }

  /// Uploads `fileURL` and returns the extracted link.
  /// - Throws: `CloudError.uploadFailed` for non-2xx responses, `CustomUploaderError` for
  ///   template, secret and extraction problems, `CloudError.networkError` for transport errors.
  func upload(
    fileURL: URL,
    using uploader: CustomUploader,
    secrets: CustomUploaderSecretResolving?,
    contentType: String? = nil,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> CloudUploadResult {
    let fileSize = try Self.fileSize(of: fileURL)
    let response = try await send(
      fileURL: fileURL,
      using: uploader,
      secrets: secrets,
      contentType: contentType,
      progress: progress
    )
    return try Self.result(from: response, uploader: uploader, fileName: fileURL.lastPathComponent, fileSize: fileSize)
  }

  /// Sends the request and returns the raw response without judging the status code.
  /// Used by `upload` and by the settings Test button.
  func send(
    fileURL: URL,
    using uploader: CustomUploader,
    secrets: CustomUploaderSecretResolving?,
    contentType: String? = nil,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> CustomUploaderResponse {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw CloudError.fileNotFound(fileURL)
    }
    let fileName = fileURL.lastPathComponent
    let resolved = try CustomUploaderRequestBuilder.resolve(uploader, fileName: fileName, secrets: secrets)
    let mimeType = contentType ?? CustomUploaderRequestBuilder.mimeType(for: fileURL)

    var request = URLRequest(url: resolved.url)
    request.httpMethod = resolved.method
    request.timeoutInterval = resolved.timeout
    for header in resolved.headers {
      // A file name or secret with a line break must not start a new header.
      let name = header.key.trimmingCharacters(in: .whitespaces)
      guard CustomUploaderRequestBuilder.isValidHeaderName(name) else { continue }
      let value = header.value.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
      request.setValue(value, forHTTPHeaderField: name)
    }

    // Removed on every exit path, including a failed body write.
    var temporaryBody: URL?
    defer {
      if let temporaryBody { try? FileManager.default.removeItem(at: temporaryBody) }
    }

    let uploadSource: URL
    switch resolved.body {
    case .multipart(let fileField, let fields):
      let boundary = CustomUploaderMultipartBody.makeBoundary()
      request.setValue(CustomUploaderMultipartBody.contentTypeHeader(boundary: boundary), forHTTPHeaderField: "Content-Type")
      let destination = temporaryDirectory.appendingPathComponent("\(UUID().uuidString).multipart")
      temporaryBody = destination
      // Copying a large video into the body file must not block the main actor.
      try await Task.detached(priority: .userInitiated) {
        try CustomUploaderMultipartBody.write(
          fields: fields,
          fileField: fileField,
          fileURL: fileURL,
          fileName: fileName,
          contentType: mimeType,
          boundary: boundary,
          to: destination
        )
      }.value
      uploadSource = destination
    case .binary:
      if request.value(forHTTPHeaderField: "Content-Type") == nil {
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
      }
      uploadSource = fileURL
    case .formURLEncoded(let fields):
      request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
      let destination = temporaryDirectory.appendingPathComponent("\(UUID().uuidString).form")
      temporaryBody = destination
      try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
      try CustomUploaderRequestBuilder.formURLEncoded(fields).write(to: destination)
      uploadSource = destination
    }

    logger.info(
      "Custom upload starting (\(uploader.method.rawValue, privacy: .public), body \(uploader.body.kind.rawValue, privacy: .public))"
    )
    let (data, urlResponse) = try await perform(request: request, fromFile: uploadSource, progress: progress)
    guard let http = urlResponse as? HTTPURLResponse else {
      throw CloudError.invalidResponse
    }
    logger.info("Custom upload finished with HTTP \(http.statusCode, privacy: .public)")
    return CustomUploaderResponse(http: http, body: data)
  }

  /// Interprets a response: non-2xx → `CloudError.uploadFailed`; else extract and validate links.
  /// The history key is the public URL, so it can be turned back into the link.
  nonisolated static func result(
    from response: CustomUploaderResponse,
    uploader: CustomUploader,
    fileName: String,
    fileSize: Int64,
    uploadedAt: Date = Date()
  ) throws -> CloudUploadResult {
    guard response.isSuccess else {
      throw CloudError.uploadFailed(
        statusCode: response.statusCode,
        message: CustomUploaderResponseParser.errorMessage(for: response, uploader: uploader)
      )
    }
    let extraction = try CustomUploaderResponseParser.extraction(from: response, uploader: uploader, fileName: fileName)
    return CloudUploadResult(
      publicURL: extraction.url,
      key: extraction.url.absoluteString,
      fileSize: fileSize,
      uploadedAt: uploadedAt,
      deleteURL: extraction.deletionURL
    )
  }

  nonisolated static func fileSize(of fileURL: URL) throws -> Int64 {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw CloudError.fileNotFound(fileURL)
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    return (attributes[.size] as? NSNumber)?.int64Value ?? 0
  }

  // MARK: - Transport

  private func perform(
    request: URLRequest,
    fromFile source: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> (Data, URLResponse) {
    let taskBox = CustomUploadTaskBox()
    let configuration = sessionConfiguration
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let delegate = CustomUploadDelegate(progress: progress) { result in
          continuation.resume(with: result)
        }
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.uploadTask(with: request, fromFile: source)
        taskBox.set(task)
        task.resume()
      }
    } onCancel: {
      taskBox.cancel()
    }
  }
}

// MARK: - Redirects

nonisolated enum CustomUploaderRedirectPolicy {
  static func allows(from original: URL?, to target: URL?) -> Bool {
    guard let original, let target,
          let fromHost = original.host?.lowercased(), let toHost = target.host?.lowercased(),
          fromHost == toHost
    else { return false }
    let fromScheme = original.scheme?.lowercased()
    let toScheme = target.scheme?.lowercased()
    // Never downgrade https → http.
    if fromScheme == "https" { return toScheme == "https" }
    return toScheme == "http" || toScheme == "https"
  }
}

// MARK: - Task Box

/// Holds the running upload so cancellation can reach it, even if it arrives before the task starts.
private nonisolated final class CustomUploadTaskBox: @unchecked Sendable {
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

// MARK: - Delegate

private nonisolated final class CustomUploadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
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

  /// Headers (often rendered from secrets) and the body would follow a redirect,
  /// so only same-host redirects that keep https are followed; any other ends
  /// the request with the 3xx response.
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(CustomUploaderRedirectPolicy.allows(from: task.originalRequest?.url, to: request.url) ? request : nil)
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
