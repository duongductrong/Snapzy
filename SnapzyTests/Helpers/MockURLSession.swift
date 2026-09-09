//
//  MockURLSession.swift
//  SnapzyTests
//
//  Programmable URLSession fake for network tests.
//

import Foundation
import os.lock
@testable import Snapzy

final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
  private struct State {
    var requests: [URLRequest] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())
  private let responder: (URLRequest) async throws -> (Data, URLResponse)

  init(responder: @escaping (URLRequest) async throws -> (Data, URLResponse) = { _ in throw URLError(.unsupportedURL) }) {
    self.responder = responder
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    record(request)
    return try await responder(request)
  }

  private func record(_ request: URLRequest) {
    state.withLock { $0.requests.append(request) }
  }

  var requests: [URLRequest] {
    state.withLock { $0.requests }
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
