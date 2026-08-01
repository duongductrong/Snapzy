//
//  FileDownloadDelegateTests.swift
//  SnapzyTests
//
//  Real-URLSession download bridge coverage via a stubbing URLProtocol (no
//  network): HTTP status validation, success path, and cancellation mapping.
//

import XCTest
@testable import Snapzy

/// Intercepts URLSession requests in-process; never touches the network.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  enum Behavior {
    case respond(statusCode: Int, body: Data)
    /// Never calls back; the task only ends via cancellation (`stopLoading`).
    case hang
  }

  private static let lock = NSLock()
  private static var _behavior: Behavior = .respond(statusCode: 200, body: Data())
  private static var _onStartLoading: (() -> Void)?

  static var behavior: Behavior {
    get { lock.lock(); defer { lock.unlock() }; return _behavior }
    set { lock.lock(); defer { lock.unlock() }; _behavior = newValue }
  }

  static var onStartLoading: (() -> Void)? {
    get { lock.lock(); defer { lock.unlock() }; return _onStartLoading }
    set { lock.lock(); defer { lock.unlock() }; _onStartLoading = newValue }
  }

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let onStart = Self.onStartLoading
    let behavior = Self.behavior
    onStart?()
    guard let url = request.url else { return }
    switch behavior {
    case .respond(let statusCode, let body):
      let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    case .hang:
      break
    }
  }

  override func stopLoading() {}
}

final class FileDownloadDelegateTests: XCTestCase {
  private var workRoot: URL!
  private var installDir: URL!

  override func setUp() {
    super.setUp()
    workRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("FileDownloadDelegateTests-\(UUID().uuidString)", isDirectory: true)
    installDir = workRoot.appendingPathComponent("install", isDirectory: true)
  }

  override func tearDown() {
    StubURLProtocol.onStartLoading = nil
    try? FileManager.default.removeItem(at: workRoot)
    super.tearDown()
  }

  // MARK: - Status validation

  func testValidateResponseAccepts2xx() {
    XCTAssertNoThrow(try FileDownloadDelegate.validate(response: makeHTTPResponse(statusCode: 200)))
  }

  func testValidateResponseRejectsNon2xxWithTypedError() {
    for statusCode in [404, 500] {
      XCTAssertThrowsError(try FileDownloadDelegate.validate(response: makeHTTPResponse(statusCode: statusCode))) { error in
        XCTAssertEqual(error as? URLSessionDownloadError, .httpStatus(statusCode))
      }
    }
  }

  func testValidateResponseAcceptsNonHTTPResponses() {
    let fileResponse = URLResponse(
      url: URL(fileURLWithPath: "/tmp/model.onnx"),
      mimeType: nil,
      expectedContentLength: 0,
      textEncodingName: nil
    )
    XCTAssertNoThrow(try FileDownloadDelegate.validate(response: fileResponse))
    XCTAssertNoThrow(try FileDownloadDelegate.validate(response: nil))
  }

  // MARK: - Real URLSession path (stubbed, no network)

  /// A 2xx download flows through the real delegate bridge into the install dir.
  func testSuccessfulDownloadThroughRealSession() async throws {
    let body = Data("onnx-bytes".utf8)
    StubURLProtocol.behavior = .respond(statusCode: 200, body: body)
    let session = makeStubbedSession()
    defer { session.invalidateAndCancel() }
    let service = OCRModelDownloadService(session: session, stagingRoot: workRoot)

    try await service.download(makeDefinition(), to: installDir) { _ in }

    XCTAssertEqual(try Data(contentsOf: installDir.appendingPathComponent("det.onnx")), body)
  }

  /// A 404 must fail the download, not stage the error page as payload bytes.
  func testHTTPErrorStatusFailsDownloadThroughRealSession() async {
    StubURLProtocol.behavior = .respond(statusCode: 404, body: Data("not found".utf8))
    let session = makeStubbedSession()
    defer { session.invalidateAndCancel() }
    let service = OCRModelDownloadService(session: session, stagingRoot: workRoot)

    do {
      try await service.download(makeDefinition(), to: installDir) { _ in }
      XCTFail("expected network error")
    } catch let error as OCRModelDownloadError {
      guard case .network(let message) = error else {
        return XCTFail("expected .network, got \(error)")
      }
      XCTAssertTrue(message.contains("404"), message)
    } catch {
      XCTFail("unexpected error: \(error)")
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: installDir.path))
  }

  /// Cancelling the Swift task cancels the URLSession task and surfaces a
  /// cancelled error through the real delegate bridge.
  func testCancellationThroughRealSessionThrowsCancelled() async throws {
    StubURLProtocol.behavior = .hang
    let started = expectation(description: "download started")
    StubURLProtocol.onStartLoading = { started.fulfill() }
    let session = makeStubbedSession()
    defer { session.invalidateAndCancel() }
    let service = OCRModelDownloadService(session: session, stagingRoot: workRoot)

    let task = Task {
      try await service.download(makeDefinition(), to: installDir) { _ in }
    }
    await fulfillment(of: [started], timeout: 5)
    task.cancel()

    do {
      try await task.value
      XCTFail("expected cancelled error")
    } catch let error as OCRModelDownloadError {
      XCTAssertEqual(error, .cancelled)
    } catch {
      XCTFail("unexpected error: \(error)")
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: installDir.path))
  }

  // MARK: - Helpers

  private func makeStubbedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
  }

  private func makeHTTPResponse(statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
      url: URL(string: "https://models.example.com/det.onnx")!,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: nil
    )!
  }

  private func makeDefinition() -> OCRModelDefinition {
    OCRModelDefinition(
      id: "test-model",
      displayName: "Test Model",
      parameterCountLabel: "1M",
      fp32SizeLabel: "1 MB",
      int8SizeLabel: "1 MB",
      files: [
        OCRModelFile(
          name: "det.onnx",
          url: URL(string: "https://models.example.com/det.onnx")!,
          expectedBytes: nil,
          sha256: nil
        ),
      ]
    )
  }
}
