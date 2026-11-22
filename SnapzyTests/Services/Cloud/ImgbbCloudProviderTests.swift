//
//  ImgbbCloudProviderTests.swift
//  SnapzyTests
//
//  imgbb provider tests. Every request goes to a URLProtocol stub; nothing reaches imgbb.
//

import Foundation
import XCTest
@testable import Snapzy

final class ImgbbCloudProviderTests: XCTestCase {

  private let endpoint = URL(string: "https://imgbb.test/1/upload")!
  private var tempDirectory: URL!

  override func setUpWithError() throws {
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ImgbbCloudProviderTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    ImgbbStubURLProtocol.reset()
  }

  override func tearDownWithError() throws {
    ImgbbStubURLProtocol.reset()
    try? FileManager.default.removeItem(at: tempDirectory)
  }

  // MARK: - Upload

  func testUpload_parsesLinkIdAndDeletePage() async throws {
    ImgbbStubURLProtocol.respond(status: 200, json: """
      {"data":{"id":"2ndCYJK","url":"https://i.ibb.co/w04Prt6/c1f64245afb2.png",
      "url_viewer":"https://ibb.co/2ndCYJK","delete_url":"https://ibb.co/2ndCYJK/670a7e48ddcb85ac340c717a41047e5c",
      "size":42},"success":true,"status":200}
      """)
    let file = try makeFile(named: "shot.png", bytes: 42)

    let result = try await makeProvider().upload(
      fileURL: file,
      contentType: "image/png",
      expireTime: .day1,
      existingKey: nil,
      progress: { _ in }
    )

    XCTAssertEqual(result.publicURL.absoluteString, "https://i.ibb.co/w04Prt6/c1f64245afb2.png")
    XCTAssertEqual(result.key, "2ndCYJK")
    XCTAssertEqual(result.fileSize, 42)
    XCTAssertEqual(
      result.deleteURL?.absoluteString,
      "https://ibb.co/2ndCYJK/670a7e48ddcb85ac340c717a41047e5c"
    )

    let request = try XCTUnwrap(ImgbbStubURLProtocol.requests.first)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.url?.host, "imgbb.test")
    XCTAssertNil(request.url?.query, "The API key must travel in the body, not the URL")
    XCTAssertTrue(
      request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") ?? false
    )
  }

  func testUpload_rejectsVideoWithoutNetwork() async throws {
    let file = try makeFile(named: "clip.mov", bytes: 10)

    do {
      _ = try await makeProvider().upload(
        fileURL: file,
        contentType: "video/quicktime",
        expireTime: .permanent,
        existingKey: nil,
        progress: { _ in }
      )
      XCTFail("Expected video to be rejected")
    } catch CloudError.unsupportedFileType(let provider) {
      XCTAssertEqual(provider, CloudProviderType.imgbb.displayName)
      XCTAssertTrue(CloudError.unsupportedFileType(provider: provider).errorDescription?.isEmpty == false)
    }
    XCTAssertTrue(ImgbbStubURLProtocol.requests.isEmpty)
  }

  func testUpload_rejectsFileOver32MBWithoutNetwork() async throws {
    let file = tempDirectory.appendingPathComponent("huge.png")
    FileManager.default.createFile(atPath: file.path, contents: nil)
    let handle = try FileHandle(forWritingTo: file)
    try handle.truncate(atOffset: UInt64(ImgbbCloudProvider.maxFileSize + 1))
    try handle.close()

    do {
      _ = try await makeProvider().upload(
        fileURL: file,
        contentType: "image/png",
        expireTime: .permanent,
        existingKey: nil,
        progress: { _ in }
      )
      XCTFail("Expected oversized file to be rejected")
    } catch CloudError.fileTooLarge(_, let limit) {
      XCTAssertEqual(limit, 32 * 1024 * 1024)
    }
    XCTAssertTrue(ImgbbStubURLProtocol.requests.isEmpty)
  }

  func testUpload_mapsInvalidKeyError() async throws {
    ImgbbStubURLProtocol.respond(status: 400, json: """
      {"status_code":400,"error":{"message":"Invalid API v1 key.","code":100},"status_txt":"Bad Request"}
      """)
    let file = try makeFile(named: "shot.png", bytes: 8)

    do {
      _ = try await makeProvider().upload(
        fileURL: file, contentType: "image/png", expireTime: .permanent, existingKey: nil, progress: { _ in }
      )
      XCTFail("Expected invalid credentials")
    } catch CloudError.invalidCredentials {
    }
  }

  func testUpload_surfacesOtherAPIErrors() async throws {
    ImgbbStubURLProtocol.respond(status: 400, json: """
      {"status_code":400,"error":{"message":"Invalid image source.","code":310}}
      """)
    let file = try makeFile(named: "shot.png", bytes: 8)

    do {
      _ = try await makeProvider().upload(
        fileURL: file, contentType: "image/png", expireTime: .permanent, existingKey: nil, progress: { _ in }
      )
      XCTFail("Expected upload failure")
    } catch CloudError.uploadFailed(let status, let message) {
      XCTAssertEqual(status, 400)
      XCTAssertEqual(message, "Invalid image source.")
    }
  }

  // MARK: - Request Body

  func testMultipartBody_carriesKeyExpirationAndImage() throws {
    let body = ImgbbCloudProvider.makeMultipartBody(
      fields: [("key", "test-key"), ("expiration", "86400")],
      fileField: "image",
      fileName: "a\"b.png",
      contentType: "image/png",
      fileData: Data("PNGDATA".utf8),
      boundary: "B"
    )
    let text = try XCTUnwrap(String(data: body, encoding: .utf8))

    XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"key\"\r\n\r\ntest-key\r\n"))
    XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"expiration\"\r\n\r\n86400\r\n"))
    XCTAssertTrue(text.contains("name=\"image\"; filename=\"ab.png\"\r\nContent-Type: image/png\r\n\r\nPNGDATA\r\n"))
    XCTAssertTrue(text.hasSuffix("--B--\r\n"))
  }

  func testExpirationSeconds_mapsDaysAndOmitsPermanent() {
    XCTAssertEqual(ImgbbCloudProvider.expirationSeconds(for: .day1), 86_400)
    XCTAssertEqual(ImgbbCloudProvider.expirationSeconds(for: .day90), 7_776_000)
    XCTAssertNil(ImgbbCloudProvider.expirationSeconds(for: .permanent))
    for time in CloudExpireTime.allCases {
      if let seconds = ImgbbCloudProvider.expirationSeconds(for: time) {
        XCTAssertTrue(ImgbbCloudProvider.expirationRange.contains(seconds))
      }
    }
  }

  // MARK: - Validate

  func testValidate_acceptsKeyWhenImgbbOnlyMissesTheImage() async throws {
    ImgbbStubURLProtocol.respond(status: 400, json: """
      {"status_code":400,"error":{"message":"Empty upload source.","code":130}}
      """)

    try await makeProvider().validate()

    let request = try XCTUnwrap(ImgbbStubURLProtocol.requests.first)
    XCTAssertNil(request.url?.query)
    let body = try XCTUnwrap(ImgbbStubURLProtocol.bodies.first.flatMap { String(data: $0, encoding: .utf8) })
    XCTAssertTrue(body.contains("name=\"key\"\r\n\r\ntest-key\r\n"))
    XCTAssertFalse(body.contains("name=\"image\""), "Validation must not upload an image")
  }

  func testValidate_rejectsInvalidKey() async throws {
    ImgbbStubURLProtocol.respond(status: 400, json: """
      {"status_code":400,"error":{"message":"Invalid API v1 key.","code":100}}
      """)

    do {
      try await makeProvider().validate()
      XCTFail("Expected invalid credentials")
    } catch CloudError.invalidCredentials {
    }
  }

  func testValidate_doesNotTreatRateLimitAsValidKey() async throws {
    ImgbbStubURLProtocol.respond(status: 429, json: """
      {"status_code":429,"error":{"message":"Rate limit exceeded.","code":429}}
      """)

    do {
      try await makeProvider().validate()
      XCTFail("Expected rate limit to fail validation")
    } catch CloudError.uploadFailed(let status, let message) {
      XCTAssertEqual(status, 429)
      XCTAssertEqual(message, "Rate limit exceeded.")
    }
  }

  func testValidate_reportsServerErrors() async throws {
    ImgbbStubURLProtocol.respond(status: 503, json: "{}")

    do {
      try await makeProvider().validate()
      XCTFail("Expected server error")
    } catch CloudError.uploadFailed(let status, _) {
      XCTAssertEqual(status, 503)
    }
  }

  // MARK: - Provider Shape

  func testProviderTraits() async throws {
    XCTAssertEqual(CloudProviderType.imgbb.rawValue, "imgbb")
    XCTAssertFalse(CloudProviderType.imgbb.usesObjectStorage)
    XCTAssertTrue(CloudProviderType.awsS3.usesObjectStorage)
    XCTAssertTrue(CloudProviderType.cloudflareR2.usesObjectStorage)
    XCTAssertFalse(CloudProviderType.googleDrive.usesObjectStorage)

    let items = CloudManager.credentialItems(for: .imgbb)
    XCTAssertEqual(items.access.account, "com.trongduong.snapzy.cloud.imgbb.apiKey")
    XCTAssertNil(items.secret)

    // No delete API and no lifecycle rule: these must not touch the network.
    let provider = makeProvider()
    try await provider.delete(key: "abc")
    try await provider.setExpiration(days: 7)
    try await provider.removeExpiration()
    XCTAssertTrue(ImgbbStubURLProtocol.requests.isEmpty)
  }

  func testCredentialTransfer_roundTripsImgbbKeyWithoutSecret() throws {
    let payload = CloudCredentialTransferPayload(
      configuration: CloudConfiguration(
        providerType: .imgbb,
        bucket: "",
        region: "",
        endpoint: nil,
        customDomain: nil,
        expireTime: .day7
      ),
      accessKey: "imgbb-test-key",
      secretKey: ""
    )
    let passphrase = "correct horse battery staple"

    let archive = try CloudCredentialTransferService.exportArchive(payload: payload, passphrase: passphrase)
    XCTAssertFalse(String(data: archive, encoding: .utf8)?.contains("imgbb-test-key") ?? true)
    let imported = try CloudCredentialTransferService.importArchive(from: archive, passphrase: passphrase)
    XCTAssertEqual(imported, payload)
    XCTAssertNil(imported.resolvedShareLinkStyle)
  }

  // MARK: - Helpers

  private func makeProvider() -> ImgbbCloudProvider {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImgbbStubURLProtocol.self]
    return ImgbbCloudProvider(apiKey: "test-key", endpoint: endpoint, sessionConfiguration: configuration)
  }

  private func makeFile(named name: String, bytes: Int) throws -> URL {
    let url = tempDirectory.appendingPathComponent(name)
    try Data(repeating: 0xAB, count: bytes).write(to: url)
    return url
  }
}

// MARK: - URLProtocol Stub

private final class ImgbbStubURLProtocol: URLProtocol {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var _requests: [URLRequest] = []
  nonisolated(unsafe) private static var _bodies: [Data] = []
  nonisolated(unsafe) private static var status = 200
  nonisolated(unsafe) private static var payload = Data()

  static var requests: [URLRequest] { lock.withLock { _requests } }
  static var bodies: [Data] { lock.withLock { _bodies } }

  static func respond(status: Int, json: String) {
    lock.withLock {
      self.status = status
      self.payload = Data(json.utf8)
    }
  }

  static func reset() {
    lock.withLock {
      _requests = []
      _bodies = []
      status = 200
      payload = Data()
    }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let body = request.httpBody ?? Self.readStream(request.httpBodyStream)
    let (status, payload) = Self.lock.withLock { () -> (Int, Data) in
      Self._requests.append(request)
      if let body { Self._bodies.append(body) }
      return (Self.status, Self.payload)
    }
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
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
      guard count > 0 else { break }
      data.append(buffer, count: count)
    }
    return data
  }
}
