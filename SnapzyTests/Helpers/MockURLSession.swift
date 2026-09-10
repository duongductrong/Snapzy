//
//  MockURLSession.swift
//  SnapzyTests
//
//  Programmable URLSession fake for network tests.
//

import Foundation
@testable import Snapzy

final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
  private let stateQueue = DispatchQueue(label: "com.snapzy.tests.mock-url-session")
  private var _requests: [URLRequest] = []
  private let responder: @Sendable (URLRequest) async throws -> (Data, URLResponse)

  init(responder: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { _ in throw URLError(.unsupportedURL) }) {
    self.responder = responder
  }

  // Work around the Xcode 26.2 XCTest/MainActor deallocation bug.
  nonisolated deinit {}

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    record(request)
    return try await responder(request)
  }

  private func record(_ request: URLRequest) {
    stateQueue.sync { _requests.append(request) }
  }

  var requests: [URLRequest] {
    stateQueue.sync { _requests }
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
