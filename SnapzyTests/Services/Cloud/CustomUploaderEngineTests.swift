//
//  CustomUploaderEngineTests.swift
//  SnapzyTests
//
//  Custom uploader engine and CustomHTTPCloudProvider against a URLProtocol stub.
//  Nothing leaves the process.
//

import Foundation
import XCTest
@testable import Snapzy

final class CustomUploaderEngineTests: XCTestCase {

  private var tempDirectory: URL!

  override func setUpWithError() throws {
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("CustomUploaderEngineTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    CustomUploaderStubURLProtocol.reset()
  }

  override func tearDownWithError() throws {
    CustomUploaderStubURLProtocol.reset()
    try? FileManager.default.removeItem(at: tempDirectory)
  }

  // MARK: - Engine

  func testUpload_2xxReturnsExtractedLink() async throws {
    CustomUploaderStubURLProtocol.respond(
      status: 200,
      body: #"{"files":[{"url":"https://zipline.example.com/u/abc.png"}],"del":"https://zipline.example.com/d/abc"}"#
    )
    let file = try makeFile(named: "shot.png", bytes: 32)
    let uploader = CustomUploader(
      name: "Zipline",
      url: "https://zipline.example.com/api/upload",
      headers: [.init("Authorization", "{secret:ZIPLINE}")],
      query: [.init("name", "{filename}")],
      body: .multipart(fileField: "file", extraFields: [.init("album", "7")]),
      responseURL: .jsonPath("files[0].url"),
      deletionURL: .jsonPath("del")
    )

    let result = try await makeEngine().upload(
      fileURL: file,
      using: uploader,
      secrets: StubSecrets(["ZIPLINE": "zpl-secret"]),
      progress: { _ in }
    )

    XCTAssertEqual(result.publicURL.absoluteString, "https://zipline.example.com/u/abc.png")
    XCTAssertEqual(result.key, "https://zipline.example.com/u/abc.png")
    XCTAssertEqual(result.deleteURL?.absoluteString, "https://zipline.example.com/d/abc")
    XCTAssertEqual(result.fileSize, 32)

    let request = try XCTUnwrap(CustomUploaderStubURLProtocol.requests.first)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.url?.absoluteString, "https://zipline.example.com/api/upload?name=shot.png")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "zpl-secret")
    let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
    XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary=SnapzyBoundary-"))

    if let body = CustomUploaderStubURLProtocol.bodies.first {
      let text = String(decoding: body, as: UTF8.self)
      let album = try XCTUnwrap(text.range(of: #"name="album""#))
      let filePart = try XCTUnwrap(text.range(of: #"name="file"; filename="shot.png""#))
      XCTAssertLessThan(album.lowerBound, filePart.lowerBound, "Extra fields come before the file part")
    }

    let leftovers = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.appendingPathComponent("bodies").path)
    XCTAssertTrue(leftovers.isEmpty, "The temp multipart body is removed")
  }

  func testUpload_non2xxThrowsWithExtractedErrorMessage() async throws {
    CustomUploaderStubURLProtocol.respond(status: 401, body: #"{"error":"Invalid authorization token"}"#)
    let file = try makeFile(named: "shot.png", bytes: 8)
    let uploader = CustomUploader(
      name: "Zipline",
      url: "https://zipline.example.com/api/upload",
      responseURL: .jsonPath("files[0].url"),
      errorMessage: .jsonPath("error")
    )

    do {
      _ = try await makeEngine().upload(fileURL: file, using: uploader, secrets: nil, progress: { _ in })
      XCTFail("Expected upload to fail")
    } catch CloudError.uploadFailed(let status, let message) {
      XCTAssertEqual(status, 401)
      XCTAssertEqual(message, "Invalid authorization token")
    }
  }

  func testUpload_unresolvedSecretFailsBeforeAnyRequest() async throws {
    let file = try makeFile(named: "shot.png", bytes: 8)
    let uploader = CustomUploader(
      name: "X",
      url: "https://x.example.com/upload",
      headers: [.init("Authorization", "Bearer {secret:MISSING_TOKEN}")]
    )

    do {
      _ = try await makeEngine().upload(fileURL: file, using: uploader, secrets: StubSecrets([:]), progress: { _ in })
      XCTFail("Expected unresolved secret")
    } catch CustomUploaderError.unresolvedSecret(let name) {
      XCTAssertEqual(name, "MISSING_TOKEN")
    }
    XCTAssertTrue(CustomUploaderStubURLProtocol.requests.isEmpty, "The literal {secret:…} token is never sent")
  }

  func testUpload_2xxWithNonWebLinkIsRejected() async throws {
    CustomUploaderStubURLProtocol.respond(status: 200, body: "javascript:alert(document.cookie)")
    let file = try makeFile(named: "shot.png", bytes: 8)
    let uploader = CustomUploader(name: "Text", url: "https://x.example.com/upload", responseURL: .plainText)

    do {
      _ = try await makeEngine().upload(fileURL: file, using: uploader, secrets: nil, progress: { _ in })
      XCTFail("Expected invalid result URL")
    } catch CustomUploaderError.invalidResultURL(let field) {
      XCTAssertEqual(field, "URL")
    }
  }

  func testSend_binaryBodyAndRawResponse() async throws {
    CustomUploaderStubURLProtocol.respond(status: 201, body: "https://files.example.com/raw.png\n", headers: ["X-Id": "42"])
    let file = try makeFile(named: "raw.png", bytes: 5)
    let uploader = CustomUploader(name: "Raw", method: .put, url: "https://files.example.com/{filename}", body: .binary)

    let response = try await makeEngine().send(
      fileURL: file, using: uploader, secrets: nil, contentType: "image/png", progress: { _ in }
    )

    XCTAssertEqual(response.statusCode, 201)
    XCTAssertEqual(response.headers["x-id"], "42")
    XCTAssertEqual(response.text, "https://files.example.com/raw.png\n")
    let request = try XCTUnwrap(CustomUploaderStubURLProtocol.requests.first)
    XCTAssertEqual(request.httpMethod, "PUT")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/png")
    if let body = CustomUploaderStubURLProtocol.bodies.first {
      XCTAssertEqual(body, Data(repeating: 0xAB, count: 5))
    }
  }

  func testTestRunnerOutcome_summarisesResponse() {
    let uploader = CustomUploader(name: "T", url: "https://x", responseURL: .jsonPath("url"), errorMessage: .jsonPath("error"))
    let ok = CustomUploaderTestRunner.outcome(
      for: CustomUploaderResponse(statusCode: 200, body: Data(#"{"url":"https://x/a.png"}"#.utf8)),
      uploader: uploader,
      fileName: "snapzy-test.png"
    )
    XCTAssertEqual(ok.statusCode, 200)
    XCTAssertEqual(ok.extractedURL, "https://x/a.png")
    XCTAssertNil(ok.error)

    let failed = CustomUploaderTestRunner.outcome(
      for: CustomUploaderResponse(statusCode: 413, body: Data(#"{"error":"Too large"}"#.utf8)),
      uploader: uploader,
      fileName: "snapzy-test.png"
    )
    XCTAssertEqual(failed.error, "Too large")
    XCTAssertNil(failed.extractedURL)

    let long = Data(repeating: 0x61, count: 5000)
    XCTAssertEqual(CustomUploaderTestRunner.preview(of: long).count, 2049)
  }

  // MARK: - Cloud provider

  func testProvider_uploadKeyRoundTripsToURL() async throws {
    CustomUploaderStubURLProtocol.respond(status: 200, body: #"{"link":"https://i.example.com/k/9.png?x=1"}"#)
    let uploader = CustomUploader(name: "P", url: "https://up.example.com", responseURL: .jsonPath("link"))
    let provider = CustomHTTPCloudProvider(
      uploaderID: uploader.id,
      lookup: { $0 == uploader.id ? uploader : nil },
      secrets: { nil },
      engine: makeEngine()
    )
    XCTAssertEqual(provider.providerType, .customHTTP)
    try await provider.validate()

    let result = try await provider.upload(
      fileURL: try makeFile(named: "p.png", bytes: 3),
      contentType: "image/png",
      expireTime: .day7,
      existingKey: "https://i.example.com/old.png",
      progress: { _ in }
    )
    XCTAssertEqual(provider.generatePublicURL(for: result.key), result.publicURL)
    XCTAssertEqual(provider.generatePublicURL(for: "https://i.example.com/k/9.png?x=1").absoluteString, "https://i.example.com/k/9.png?x=1")

    // No delete API, no lifecycle rule: none of these touch the network.
    let requestCount = CustomUploaderStubURLProtocol.requests.count
    try await provider.delete(key: result.key)
    try await provider.setExpiration(days: 7)
    try await provider.removeExpiration()
    XCTAssertEqual(CustomUploaderStubURLProtocol.requests.count, requestCount)
  }

  func testProvider_missingUploaderFails() async throws {
    let provider = CustomHTTPCloudProvider(uploaderID: UUID(), lookup: { _ in nil }, secrets: { nil }, engine: makeEngine())
    do {
      try await provider.validate()
      XCTFail("Expected uploaderNotFound")
    } catch CustomUploaderError.uploaderNotFound {}

    let unset = CustomHTTPCloudProvider(uploaderID: nil, lookup: { _ in nil }, secrets: { nil }, engine: makeEngine())
    do {
      _ = try await unset.upload(
        fileURL: try makeFile(named: "a.png", bytes: 1), contentType: "image/png", expireTime: .permanent,
        existingKey: nil, progress: { _ in }
      )
      XCTFail("Expected uploaderNotFound")
    } catch CustomUploaderError.uploaderNotFound {}
    XCTAssertTrue(CustomUploaderStubURLProtocol.requests.isEmpty)
  }

  func testProviderType_customHTTP() {
    XCTAssertEqual(CloudProviderType.customHTTP.rawValue, "custom_http")
    XCTAssertEqual(CloudProviderType.customHTTP.displayName, "Custom Uploader")
    XCTAssertFalse(CloudProviderType.customHTTP.usesObjectStorage)
    XCTAssertFalse(CloudProviderType.customHTTP.usesCloudCredentials)
    XCTAssertFalse(CloudProviderType.customHTTP.supportsRemoteDelete)
    XCTAssertTrue(CloudProviderType.awsS3.supportsRemoteDelete)
    XCTAssertTrue(
      CloudConfiguration(
        providerType: .customHTTP, bucket: "", region: "", endpoint: nil, customDomain: nil, expireTime: .permanent
      ).isValid
    )
    XCTAssertEqual(CustomUploaderError.limitReached(20).errorDescription?.contains("20"), true)
  }

  // MARK: - Helpers

  private func makeEngine() -> CustomUploaderEngine {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CustomUploaderStubURLProtocol.self]
    return CustomUploaderEngine(
      sessionConfiguration: configuration,
      temporaryDirectory: tempDirectory.appendingPathComponent("bodies", isDirectory: true)
    )
  }

  private func makeFile(named name: String, bytes: Int) throws -> URL {
    let url = tempDirectory.appendingPathComponent(name)
    try Data(repeating: 0xAB, count: bytes).write(to: url)
    return url
  }
}

// MARK: - URLProtocol Stub

private final class CustomUploaderStubURLProtocol: URLProtocol {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var _requests: [URLRequest] = []
  nonisolated(unsafe) private static var _bodies: [Data] = []
  nonisolated(unsafe) private static var status = 200
  nonisolated(unsafe) private static var payload = Data()
  nonisolated(unsafe) private static var headers: [String: String] = [:]

  static var requests: [URLRequest] { lock.withLock { _requests } }
  static var bodies: [Data] { lock.withLock { _bodies } }

  static func respond(status: Int, body: String, headers: [String: String] = [:]) {
    lock.withLock {
      self.status = status
      self.payload = Data(body.utf8)
      self.headers = headers
    }
  }

  static func reset() {
    lock.withLock {
      _requests = []
      _bodies = []
      status = 200
      payload = Data()
      headers = [:]
    }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let body = request.httpBody ?? Self.readStream(request.httpBodyStream)
    let (status, payload, headers) = Self.lock.withLock { () -> (Int, Data, [String: String]) in
      Self._requests.append(request)
      if let body { Self._bodies.append(body) }
      return (Self.status, Self.payload, Self.headers)
    }
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: headers
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: payload)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private static func readStream(_ stream: InputStream?) -> Data? {
    guard let stream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count <= 0 { break }
      data.append(buffer, count: count)
    }
    return data
  }
}
