//
//  URLSessionProtocol.swift
//  Snapzy
//
//  Protocol abstraction for URLSession to enable test injection.
//

import Foundation

protocol URLSessionProtocol: Sendable {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
  /// Downloads `url` into a local temporary file, reporting fraction completed
  /// (0...1) as it progresses. Returns the local file URL; the caller moves it.
  func download(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL
}

/// Typed failures raised by the `URLSessionProtocol.download` bridge.
enum URLSessionDownloadError: LocalizedError, Equatable {
  /// Server answered with a non-2xx HTTP status.
  case httpStatus(Int)

  var errorDescription: String? {
    switch self {
    case .httpStatus(let statusCode):
      return "Download failed with HTTP status \(statusCode)."
    }
  }
}

extension URLSession: URLSessionProtocol {
  func download(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
    let delegate = FileDownloadDelegate(progress: progress)
    let downloadSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    defer { downloadSession.invalidateAndCancel() }
    return try await delegate.download(in: downloadSession, url: url)
  }
}

/// Per-download delegate bridge: URLSession only reports byte progress to its
/// session-level delegate, so each download runs on a short-lived session.
/// Internal (not private) so tests can drive the status validation directly.
final class FileDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  private let progress: @Sendable (Double) -> Void
  private var task: URLSessionDownloadTask?
  private var continuation: CheckedContinuation<URL, Error>?

  init(progress: @escaping @Sendable (Double) -> Void) {
    self.progress = progress
  }

  /// 2xx gate applied before a finished download is accepted: HTTP error
  /// pages must not be staged as payload bytes.
  static func validate(response: URLResponse?) throws {
    guard let httpResponse = response as? HTTPURLResponse,
          !(200...299).contains(httpResponse.statusCode)
    else { return }
    throw URLSessionDownloadError.httpStatus(httpResponse.statusCode)
  }

  func download(in session: URLSession, url: URL) async throws -> URL {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        let task = session.downloadTask(with: url)
        self.task = task
        task.resume()
      }
    } onCancel: {
      task?.cancel()
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesExpectedToWrite > 0 else { return }
    progress(min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 1.0))
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    // `location` is removed once this method returns; move it aside first.
    do {
      try Self.validate(response: downloadTask.response)
      let stagedURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
      try FileManager.default.moveItem(at: location, to: stagedURL)
      resume(returning: stagedURL)
    } catch {
      resume(throwing: error)
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    if let error {
      resume(throwing: error)
    }
  }

  private func resume(returning url: URL) {
    continuation?.resume(returning: url)
    continuation = nil
  }

  private func resume(throwing error: Error) {
    continuation?.resume(throwing: error)
    continuation = nil
  }
}
