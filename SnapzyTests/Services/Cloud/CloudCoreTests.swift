//
//  CloudCoreTests.swift
//  SnapzyTests
//
//  Unit tests for cloud signing, credential transfer, and lifecycle parsing.
//

import Foundation
import XCTest
@testable import Snapzy

final class CloudCoreTests: XCTestCase {

  private let passphrase = "correct horse battery staple"

  func testAWSV4SignerSHA256Hex_knownVector() {
    XCTAssertEqual(
      AWSV4Signer.sha256Hex("abc"),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
  }

  func testAWSV4SignerSign_addsRequiredHeadersAndAuthorizationScope() throws {
    var request = URLRequest(url: URL(string: "https://example-bucket.s3.us-east-1.amazonaws.com/snapzy/test.png?acl=&z=last&a=first")!)
    request.httpMethod = "PUT"
    request.setValue("image/png", forHTTPHeaderField: "Content-Type")

    let payloadHash = AWSV4Signer.sha256Hex(Data("hello".utf8))
    let signed = try AWSV4Signer.sign(
      request: request,
      accessKey: "AKIATEST",
      secretKey: "SECRET",
      region: "us-east-1",
      payloadHash: payloadHash
    )

    XCTAssertEqual(signed.value(forHTTPHeaderField: "Host"), "example-bucket.s3.us-east-1.amazonaws.com")
    XCTAssertEqual(signed.value(forHTTPHeaderField: "x-amz-content-sha256"), payloadHash)

    let amzDate = try XCTUnwrap(signed.value(forHTTPHeaderField: "x-amz-date"))
    XCTAssertNotNil(amzDate.range(of: #"^\d{8}T\d{6}Z$"#, options: .regularExpression))

    let authorization = try XCTUnwrap(signed.value(forHTTPHeaderField: "Authorization"))
    XCTAssertTrue(authorization.hasPrefix("AWS4-HMAC-SHA256 "))
    XCTAssertTrue(authorization.contains("Credential=AKIATEST/\(String(amzDate.prefix(8)))/us-east-1/s3/aws4_request"))
    XCTAssertTrue(authorization.contains("SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date"))
    XCTAssertNotNil(authorization.range(of: #"Signature=[0-9a-f]{64}"#, options: .regularExpression))
  }

  func testAWSV4SignerPresignURL_includesExpectedQueryItems() throws {
    let presignedURL = try AWSV4Signer.presignURL(
      url: URL(string: "https://example-bucket.s3.us-east-1.amazonaws.com/snapzy/test.png")!,
      accessKey: "AKIATEST",
      secretKey: "SECRET",
      region: "us-east-1",
      expireSeconds: 900
    )

    let components = try XCTUnwrap(URLComponents(url: presignedURL, resolvingAgainstBaseURL: false))
    let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
      item.value.map { (item.name, $0) }
    })

    XCTAssertEqual(components.scheme, "https")
    XCTAssertEqual(components.host, "example-bucket.s3.us-east-1.amazonaws.com")
    XCTAssertEqual(components.path, "/snapzy/test.png")
    XCTAssertEqual(items["X-Amz-Algorithm"], "AWS4-HMAC-SHA256")
    XCTAssertEqual(items["X-Amz-Expires"], "900")
    XCTAssertEqual(items["X-Amz-SignedHeaders"], "host")
    XCTAssertTrue(items["X-Amz-Credential"]?.contains("AKIATEST/") == true)
    XCTAssertTrue(items["X-Amz-Credential"]?.contains("/us-east-1/s3/aws4_request") == true)
    XCTAssertNotNil(items["X-Amz-Date"]?.range(of: #"^\d{8}T\d{6}Z$"#, options: .regularExpression))
    XCTAssertNotNil(items["X-Amz-Signature"]?.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression))
  }

  func testAWSV4SignerPresignURL_percentEncodesSpacesInObjectKey() throws {
    // Reproduces the bug where an S3/R2 object key containing a space (e.g. a
    // custom filename template that yields "Snapzy 2024 shot.png") made
    // `presignURL` embed a raw space in the canonical URI and the final URL
    // string, so `URL(string:)` returned nil and the call threw. The canonical
    // URI must be percent-encoded exactly like `sign()` does.
    let inputURL = try XCTUnwrap(
      URL(string: "https://example-bucket.s3.us-east-1.amazonaws.com/snapzy/My%20File.png")
    )

    let presignedURL = try AWSV4Signer.presignURL(
      url: inputURL,
      accessKey: "AKIATEST",
      secretKey: "SECRET",
      region: "us-east-1",
      expireSeconds: 900
    )

    // The returned URL must stay valid and keep the space encoded (no raw
    // whitespace), matching the canonical URI the signature was computed over.
    let components = try XCTUnwrap(URLComponents(url: presignedURL, resolvingAgainstBaseURL: false))
    XCTAssertEqual(components.percentEncodedPath, "/snapzy/My%20File.png")
    XCTAssertFalse(components.percentEncodedPath.contains(" "))

    let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
      item.value.map { (item.name, $0) }
    })
    XCTAssertEqual(items["X-Amz-Algorithm"], "AWS4-HMAC-SHA256")
    XCTAssertEqual(items["X-Amz-Expires"], "900")
    XCTAssertNotNil(items["X-Amz-Signature"]?.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression))
  }

  func testCloudCredentialTransfer_roundTripsEncryptedPayload() throws {
    let payload = makeTransferPayload()

    let archiveData = try CloudCredentialTransferService.exportArchive(
      payload: payload,
      passphrase: passphrase
    )
    let envelope = try JSONDecoder().decode(CloudCredentialTransferEnvelope.self, from: archiveData)
    XCTAssertEqual(envelope.schemaVersion, 1)
    XCTAssertEqual(envelope.algorithm, "AES.GCM.256")
    XCTAssertEqual(envelope.kdf, "PBKDF2-SHA256")
    XCTAssertEqual(envelope.iterations, 300_000)
    XCTAssertFalse(String(data: archiveData, encoding: .utf8)?.contains(payload.secretKey) ?? true)

    let imported = try CloudCredentialTransferService.importArchive(
      from: archiveData,
      passphrase: passphrase
    )
    XCTAssertEqual(imported, payload)
  }

  func testCloudCredentialTransfer_rejectsShortOrWrongPassphrase() throws {
    XCTAssertThrowsError(
      try CloudCredentialTransferService.exportArchive(payload: makeTransferPayload(), passphrase: "too short")
    ) { error in
      guard case CloudCredentialTransferError.passphraseTooShort(let minimumLength) = error else {
        return XCTFail("Expected passphraseTooShort, got \(error)")
      }
      XCTAssertEqual(minimumLength, CloudCredentialTransferService.minimumPassphraseLength)
    }

    let archiveData = try CloudCredentialTransferService.exportArchive(
      payload: makeTransferPayload(),
      passphrase: passphrase
    )

    XCTAssertThrowsError(
      try CloudCredentialTransferService.importArchive(from: archiveData, passphrase: "wrong horse battery")
    ) { error in
      guard case CloudCredentialTransferError.unlockFailed = error else {
        return XCTFail("Expected unlockFailed, got \(error)")
      }
    }
  }

  func testCloudCredentialTransferSuggestedArchiveFileName_sanitizesBucket() {
    let payload = CloudCredentialTransferPayload(
      configuration: CloudConfiguration(
        providerType: .cloudflareR2,
        bucket: "  My_Bucket! 2026  ",
        region: "auto",
        endpoint: "https://account.r2.cloudflarestorage.com",
        customDomain: nil,
        expireTime: .day7
      ),
      accessKey: "access",
      secretKey: "secret"
    )

    XCTAssertEqual(
      CloudCredentialTransferService.suggestedArchiveFileName(for: payload),
      "snapzy-cloud-cloudflare-r2-My-Bucket-2026.snapzycloud"
    )
  }

  func testLifecycleXMLParser_extractsRuleBlocksInOrder() {
    let xml = """
      <LifecycleConfiguration>
        <Rule><ID>snapzy-expire</ID><Status>Enabled</Status></Rule>
        <Rule><ID>other-rule</ID><Status>Disabled</Status></Rule>
      </LifecycleConfiguration>
      """

    let rules = LifecycleXMLParser.parseRules(from: Data(xml.utf8))

    XCTAssertEqual(rules.count, 2)
    XCTAssertTrue(rules[0].contains("<ID>snapzy-expire</ID>"))
    XCTAssertTrue(rules[1].contains("<ID>other-rule</ID>"))
    XCTAssertTrue(rules.allSatisfy { $0.hasPrefix("<Rule>") && $0.hasSuffix("</Rule>") })
  }

  func testCloudExpireTime_legacyValuesMapToDayBasedOptions() {
    XCTAssertEqual(CloudExpireTime(legacyRawValue: "15m"), .day1)
    XCTAssertEqual(CloudExpireTime(legacyRawValue: "5d"), .day7)
    XCTAssertEqual(CloudExpireTime(legacyRawValue: "15d"), .day14)
    XCTAssertEqual(CloudExpireTime(legacyRawValue: "24d"), .day30)
    XCTAssertEqual(CloudExpireTime(legacyRawValue: "permanent"), .permanent)
    XCTAssertEqual(CloudExpireTime(legacyRawValue: "unknown"), .day7)

    XCTAssertEqual(CloudExpireTime.day3.days, 3)
    XCTAssertEqual(CloudExpireTime.day3.seconds, 259_200)
    XCTAssertNil(CloudExpireTime.permanent.days)
    XCTAssertNil(CloudExpireTime.permanent.seconds)
    XCTAssertTrue(CloudExpireTime.permanent.isPermanent)
  }

  func testCloudConfigurationValidation_requiresProviderSpecificFields() {
    XCTAssertTrue(CloudConfiguration(
      providerType: .awsS3,
      bucket: "snapzy",
      region: "us-east-1",
      endpoint: nil,
      customDomain: nil,
      expireTime: .day7
    ).isValid)

    XCTAssertFalse(CloudConfiguration(
      providerType: .awsS3,
      bucket: "snapzy",
      region: "   ",
      endpoint: nil,
      customDomain: nil,
      expireTime: .day7
    ).isValid)

    XCTAssertTrue(CloudConfiguration(
      providerType: .cloudflareR2,
      bucket: "snapzy",
      region: "",
      endpoint: "https://account.r2.cloudflarestorage.com",
      customDomain: nil,
      expireTime: .day7
    ).isValid)

    XCTAssertFalse(CloudConfiguration(
      providerType: .cloudflareR2,
      bucket: "   ",
      region: "auto",
      endpoint: "https://account.r2.cloudflarestorage.com",
      customDomain: nil,
      expireTime: .day7
    ).isValid)
  }

  func testCloudUploadRecordExpirationAndImageType() {
    let expiredRecord = makeUploadRecord(
      uploadedAt: Date().addingTimeInterval(-2 * 86_400),
      expireTime: .day1,
      contentType: "image/png"
    )
    XCTAssertTrue(expiredRecord.isExpired)
    XCTAssertTrue(expiredRecord.isImageType)

    let permanentRecord = makeUploadRecord(
      fileName: "movie.mov",
      uploadedAt: Date().addingTimeInterval(-365 * 86_400),
      expireTime: .permanent,
      contentType: "video/quicktime"
    )
    XCTAssertFalse(permanentRecord.isExpired)
    XCTAssertFalse(permanentRecord.isImageType)

    let legacyImageRecord = makeUploadRecord(
      fileName: "capture.webp",
      uploadedAt: Date(),
      expireTime: .day7,
      contentType: nil
    )
    XCTAssertTrue(legacyImageRecord.isImageType)
  }

  private func makeTransferPayload() -> CloudCredentialTransferPayload {
    CloudCredentialTransferPayload(
      configuration: CloudConfiguration(
        providerType: .awsS3,
        bucket: "snapzy-test",
        region: "us-east-1",
        endpoint: nil,
        customDomain: "cdn.example.com",
        expireTime: .day30
      ),
      accessKey: "AKIATEST",
      secretKey: "SECRETKEY"
    )
  }

  private func makeUploadRecord(
    fileName: String = "capture.png",
    uploadedAt: Date,
    expireTime: CloudExpireTime,
    contentType: String?
  ) -> CloudUploadRecord {
    CloudUploadRecord(
      id: UUID(),
      fileName: fileName,
      publicURL: URL(string: "https://cdn.example.com/\(fileName)")!,
      key: "snapzy/\(fileName)",
      fileSize: 1_024,
      uploadedAt: uploadedAt,
      providerType: .awsS3,
      expireTime: expireTime,
      contentType: contentType
    )
  }

  // MARK: - URLSession Injection

  func testS3CloudProvider_validate_sendsHEADToBucket() async throws {
    let config = CloudConfiguration(
      providerType: .awsS3,
      bucket: "test-bucket",
      region: "us-east-1",
      endpoint: nil,
      customDomain: nil,
      expireTime: .day7
    )
    let mockSession = MockURLSession { request in
      MockURLSession.makeResponse(statusCode: 200)
    }
    let provider = S3CloudProvider(config: config, accessKey: "AKIATEST", secretKey: "SECRET", session: mockSession)

    try await provider.validate()

    XCTAssertEqual(mockSession.requests.count, 1)
    XCTAssertEqual(mockSession.requests.first?.httpMethod, "HEAD")
    XCTAssertTrue(mockSession.requests.first?.url?.absoluteString.contains("test-bucket") == true)
  }

  func testS3CloudProvider_validate_403throwsInvalidCredentials() async throws {
    let config = CloudConfiguration(
      providerType: .awsS3,
      bucket: "test-bucket",
      region: "us-east-1",
      endpoint: nil,
      customDomain: nil,
      expireTime: .day7
    )
    let mockSession = MockURLSession { request in
      MockURLSession.makeResponse(statusCode: 403)
    }
    let provider = S3CloudProvider(config: config, accessKey: "AKIATEST", secretKey: "SECRET", session: mockSession)

    do {
      try await provider.validate()
      XCTFail("Expected invalidCredentials error")
    } catch {
      guard case CloudError.invalidCredentials = error else {
        return XCTFail("Expected invalidCredentials, got \(error)")
      }
    }
  }

  func testS3CloudProvider_delete_sendsDELETEToObjectURL() async throws {
    let config = CloudConfiguration(
      providerType: .awsS3,
      bucket: "test-bucket",
      region: "us-east-1",
      endpoint: nil,
      customDomain: nil,
      expireTime: .day7
    )
    let mockSession = MockURLSession { request in
      MockURLSession.makeResponse(statusCode: 204)
    }
    let provider = S3CloudProvider(config: config, accessKey: "AKIATEST", secretKey: "SECRET", session: mockSession)

    try await provider.delete(key: "snapzy/test.png")

    XCTAssertEqual(mockSession.requests.count, 1)
    XCTAssertEqual(mockSession.requests.first?.httpMethod, "DELETE")
  }

  // MARK: - Lifecycle 403 Graceful Handling

  func testS3CloudProvider_setExpiration_403getAndPut_graceful() async throws {
    let config = CloudConfiguration(
      providerType: .awsS3,
      bucket: "test-bucket",
      region: "us-east-1",
      endpoint: nil,
      customDomain: nil,
      expireTime: .day7
    )
    let mockSession = MockURLSession { request in
      MockURLSession.makeResponse(statusCode: 403, data: Data("AccessDenied".utf8))
    }
    let provider = S3CloudProvider(config: config, accessKey: "AKIATEST", secretKey: "SECRET", session: mockSession)

    // Should not throw despite 403 on both GET and PUT lifecycle
    try await provider.setExpiration(days: 7)

    XCTAssertGreaterThanOrEqual(mockSession.requests.count, 1)
    let lifecycleRequests = mockSession.requests.filter { $0.url?.absoluteString.contains("lifecycle") == true }
    XCTAssertGreaterThanOrEqual(lifecycleRequests.count, 1)
  }

  func testS3CloudProvider_removeExpiration_403getAndDelete_graceful() async throws {
    let config = CloudConfiguration(
      providerType: .awsS3,
      bucket: "test-bucket",
      region: "us-east-1",
      endpoint: nil,
      customDomain: nil,
      expireTime: .day7
    )
    let mockSession = MockURLSession { request in
      MockURLSession.makeResponse(statusCode: 403, data: Data("AccessDenied".utf8))
    }
    let provider = S3CloudProvider(config: config, accessKey: "AKIATEST", secretKey: "SECRET", session: mockSession)

    // Should not throw despite 403 on both GET and DELETE lifecycle
    try await provider.removeExpiration()

    XCTAssertGreaterThanOrEqual(mockSession.requests.count, 1)
    let lifecycleRequests = mockSession.requests.filter { $0.url?.absoluteString.contains("lifecycle") == true }
    XCTAssertGreaterThanOrEqual(lifecycleRequests.count, 1)
  }

  func testS3CloudProvider_setExpiration_403getAnd200put_putsFreshRule() async throws {
    let config = CloudConfiguration(
      providerType: .awsS3,
      bucket: "test-bucket",
      region: "us-east-1",
      endpoint: nil,
      customDomain: nil,
      expireTime: .day7
    )
    let mockSession = MockURLSession { request in
      MockURLSession.makeResponse(statusCode: 200)
    }
    let provider = S3CloudProvider(config: config, accessKey: "AKIATEST", secretKey: "SECRET", session: mockSession)

    try await provider.setExpiration(days: 7)

    let putRequest = mockSession.requests.first { $0.httpMethod == "PUT" }
    XCTAssertNotNil(putRequest)
    XCTAssertTrue(putRequest?.url?.absoluteString.contains("lifecycle") == true)

    // Verify body contains the snapzy expiration rule
    if let bodyData = putRequest?.httpBody,
       let body = String(data: bodyData, encoding: .utf8) {
      XCTAssertTrue(body.contains("snapzy-auto-expire"))
      XCTAssertTrue(body.contains("<Days>7</Days>"))
    } else {
      XCTFail("PUT lifecycle request should have body data")
    }
  }

  func testS3CloudProvider_removeExpiration_403getAnd200delete_deletesConfig() async throws {
    let config = CloudConfiguration(
      providerType: .awsS3,
      bucket: "test-bucket",
      region: "us-east-1",
      endpoint: nil,
      customDomain: nil,
      expireTime: .day7
    )
    let mockSession = MockURLSession { request in
      MockURLSession.makeResponse(statusCode: 200)
    }
    let provider = S3CloudProvider(config: config, accessKey: "AKIATEST", secretKey: "SECRET", session: mockSession)

    try await provider.removeExpiration()

    let deleteRequest = mockSession.requests.first { $0.httpMethod == "DELETE" }
    XCTAssertNotNil(deleteRequest)
    XCTAssertTrue(deleteRequest?.url?.absoluteString.contains("lifecycle") == true)
  }
}
