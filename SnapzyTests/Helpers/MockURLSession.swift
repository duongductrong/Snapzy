//
//  MockURLSession.swift
//  SnapzyTests
//
//  Programmable URLSession fake for network tests.
//

import Foundation
@testable import Snapzy

final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
  private let lock = NSLock()
  private var _requests: [URLRequest] = []
  private var _downloadedURLs: [URL] = []
  private let responder: (URLRequest) async throws -> (Data, URLResponse)

  /// Optional fake for `download(from:progress:)`; throws when unset.
  var downloadResponder: ((URL, @escaping @Sendable (Double) -> Void) async throws -> URL)?

  init(responder: @escaping (URLRequest) async throws -> (Data, URLResponse) = { _ in throw URLError(.unsupportedURL) }) {
    self.responder = responder
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    lock.lock()
    _requests.append(request)
    lock.unlock()
    return try await responder(request)
  }

  func download(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
    lock.lock()
    _downloadedURLs.append(url)
    lock.unlock()
    guard let downloadResponder else {
      throw URLError(.unsupportedURL)
    }
    return try await downloadResponder(url, progress)
  }

  var requests: [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return _requests
  }

  var downloadedURLs: [URL] {
    lock.lock()
    defer { lock.unlock() }
    return _downloadedURLs
  }

  static func makeResponse(
    statusCode: Int,
    data: Data = Data(),
    url: URL = URL(string: "https://example.com")!
  ) -> (Data, URLResponse) {
    let response = HTTPURLResponse(
      url: url,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: nil
    )!
    return (data, response)
  }
}

extension MockURLSession {
  /// Serves in-memory bytes (keyed by absolute URL string) as downloaded temp
  /// files, emitting monotonic progress for each file.
  func serveDownloads(_ contents: [String: Data], progressSteps: Int = 4) {
    downloadResponder = { url, progress in
      guard let data = contents[url.absoluteString] else {
        throw URLError(.fileDoesNotExist)
      }
      for step in 1...progressSteps {
        progress(Double(step) / Double(progressSteps))
      }
      let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
      try data.write(to: tempURL)
      return tempURL
    }
  }
}
