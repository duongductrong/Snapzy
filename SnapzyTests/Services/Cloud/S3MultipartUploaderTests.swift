//
//  S3MultipartUploaderTests.swift
//  SnapzyTests
//

import XCTest
@testable import Snapzy

final class S3MultipartUploaderTests: XCTestCase {

  private var tempFileURL: URL!
  private let testData = Data("abcdefghijklmnopqrstuvwxy".utf8) // 25 bytes

  override func setUp() {
    super.setUp()
    let tempDir = FileManager.default.temporaryDirectory
    tempFileURL = tempDir.appendingPathComponent("s3-multipart-test-\(UUID().uuidString).bin")
    try? testData.write(to: tempFileURL)
  }

  override func tearDown() {
    if let url = tempFileURL {
      try? FileManager.default.removeItem(at: url)
    }
    super.tearDown()
  }

  func testMultipartUpload_success() async throws {
    // 25 bytes total, part size is 10. Expected 3 parts.
    let expectedUploadId = "mock-upload-id-123"
    var partCount = 0

    let session = MockURLSession { request in
      let urlString = request.url?.absoluteString ?? ""

      if request.httpMethod == "POST" && urlString.contains("?uploads") {
        // 1. Initiate multipart upload
        let responseXML = """
        <InitiateMultipartUploadResult>
          <Bucket>test-bucket</Bucket>
          <Key>test-key.bin</Key>
          <UploadId>\(expectedUploadId)</UploadId>
        </InitiateMultipartUploadResult>
        """
        let responseData = Data(responseXML.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (responseData, response)
      } else if request.httpMethod == "PUT" && urlString.contains("partNumber=") {
        // 2. Upload part
        partCount += 1
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["ETag": "\"mock-etag-\(partCount)\""]
        )!
        return (Data(), response)
      } else if request.httpMethod == "POST" && urlString.contains("uploadId=") {
        // 3. Complete upload
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(), response)
      }

      return MockURLSession.makeResponse(statusCode: 400)
    }

    let config = CloudConfiguration(
      providerType: .awsS3,
      bucket: "test-bucket",
      region: "us-east-1",
      endpoint: "https://s3.amazonaws.com",
      customDomain: nil,
      expireTime: .day7
    )

    let uploader = S3MultipartUploader(
      accessKey: "access",
      secretKey: "secret",
      region: "us-east-1",
      endpoint: URL(string: "https://s3.amazonaws.com")!,
      bucket: "test-bucket",
      session: session,
      partSize: 10
    )

    var progressUpdates: [Double] = []
    let result = try await uploader.upload(
      fileURL: tempFileURL,
      key: "test-key.bin",
      contentType: "application/octet-stream",
      expireTime: .day7
    ) { progress in
      progressUpdates.append(progress)
    }

    XCTAssertEqual(result.key, "test-key.bin")
    XCTAssertEqual(result.fileSize, 25)
    XCTAssertEqual(result.publicURL.absoluteString, "https://s3.amazonaws.com/test-bucket/test-key.bin")
    XCTAssertEqual(partCount, 3)

    // Check that we got progress updates
    XCTAssertFalse(progressUpdates.isEmpty)
    XCTAssertEqual(progressUpdates.last, 1.0)

    // Check request structure
    let requests = session.requests
    XCTAssertEqual(requests.count, 5) // Initiate (1) + Upload Parts (3) + Complete (1)

    // Initiate Request
    XCTAssertEqual(requests[0].httpMethod, "POST")
    XCTAssertTrue(requests[0].url?.absoluteString.contains("?uploads") == true)

    // Part Requests
    XCTAssertEqual(requests[1].httpMethod, "PUT")
    XCTAssertTrue(requests[1].url?.absoluteString.contains("partNumber=1") == true)
    XCTAssertEqual(requests[2].httpMethod, "PUT")
    XCTAssertTrue(requests[2].url?.absoluteString.contains("partNumber=2") == true)
    XCTAssertEqual(requests[3].httpMethod, "PUT")
    XCTAssertTrue(requests[3].url?.absoluteString.contains("partNumber=3") == true)

    // Complete Request
    XCTAssertEqual(requests[4].httpMethod, "POST")
    XCTAssertTrue(requests[4].url?.absoluteString.contains("uploadId=\(expectedUploadId)") == true)
  }

  func testMultipartUpload_abortsOnFailure() async throws {
    try skipIfRunningInCI("Retries an async mock upload and is unstable after headless UI tests")
    let expectedUploadId = "mock-upload-id-abort"
    var isAborted = false

    let session = MockURLSession { request in
      let urlString = request.url?.absoluteString ?? ""

      if request.httpMethod == "POST" && urlString.contains("?uploads") {
        let responseXML = "<InitiateMultipartUploadResult><UploadId>\(expectedUploadId)</UploadId></InitiateMultipartUploadResult>"
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(responseXML.utf8), response)
      } else if request.httpMethod == "PUT" && urlString.contains("partNumber=1") {
        // First part succeeds
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "\"etag-1\""])!
        return (Data(), response)
      } else if request.httpMethod == "PUT" && urlString.contains("partNumber=2") {
        // Second part fails
        return MockURLSession.makeResponse(statusCode: 500)
      } else if request.httpMethod == "DELETE" && urlString.contains("uploadId=\(expectedUploadId)") {
        isAborted = true
        let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
        return (Data(), response)
      }

      return MockURLSession.makeResponse(statusCode: 400)
    }

    let uploader = S3MultipartUploader(
      accessKey: "access",
      secretKey: "secret",
      region: "us-east-1",
      endpoint: URL(string: "https://s3.amazonaws.com")!,
      bucket: "test-bucket",
      session: session,
      partSize: 10
    )

    do {
      _ = try await uploader.upload(
        fileURL: tempFileURL,
        key: "test-key.bin",
        contentType: "application/octet-stream",
        expireTime: .day7,
        progress: { _ in }
      )
      XCTFail("Expected upload to fail")
    } catch {
      // Expected error
      XCTAssertTrue(isAborted, "Expected AbortMultipartUpload to be called")
    }
  }
}
