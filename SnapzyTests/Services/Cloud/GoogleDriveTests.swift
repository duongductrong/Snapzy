//
//  GoogleDriveTests.swift
//  SnapzyTests
//
//  Created by DeepMind on 2026-07-12.
//

import XCTest
import CryptoKit
@testable import Snapzy

final class GoogleDriveTests: XCTestCase {

  func testPKCEVerifierLength() throws {
    try skipIfRunningInCI()
    let service = GoogleDriveOAuthService.shared
    let (verifier, challenge) = service.generatePKCE()
    XCTAssertEqual(verifier.count, 64)
    XCTAssertFalse(challenge.isEmpty)
  }

  func testPKCEChallengeIsSHA256OfVerifier() throws {
    try skipIfRunningInCI()
    let service = GoogleDriveOAuthService.shared
    let (verifier, challenge) = service.generatePKCE()

    guard let data = verifier.data(using: .utf8) else {
      XCTFail("Failed to encode verifier")
      return
    }
    let digest = SHA256.hash(data: data)
    let expectedChallenge = Data(digest)
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")

    XCTAssertEqual(challenge, expectedChallenge)
  }

  func testPublicURLFormat() throws {
    try skipIfRunningInCI()
    let provider = GoogleDriveCloudProvider(
      clientId: "test_client",
      clientSecret: "test_secret",
      refreshToken: "test_refresh",
      folderName: "Snapzy"
    )
    let url = provider.generatePublicURL(for: "fileId12345")
    XCTAssertEqual(url.absoluteString, "https://drive.google.com/file/d/fileId12345/view")
  }

  func testProviderTypeIsGoogleDrive() throws {
    try skipIfRunningInCI()
    XCTAssertEqual(CloudProviderType.googleDrive.rawValue, "google_drive")
    XCTAssertEqual(CloudProviderType.googleDrive.displayName, "Google Drive")
  }

  func testSetExpirationIsNoOp() async throws {
    try skipIfRunningInCI()
    let provider = GoogleDriveCloudProvider(
      clientId: "test_client",
      clientSecret: "test_secret",
      refreshToken: "test_refresh",
      folderName: "Snapzy"
    )
    // Should complete successfully without throwing
    do {
      try await provider.setExpiration(days: 7)
      try await provider.removeExpiration()
    } catch {
      XCTFail("setExpiration/removeExpiration threw unexpected error: \(error)")
    }
  }

  func testGoogleDriveConfigIsAlwaysValid() throws {
    try skipIfRunningInCI()
    let config = CloudConfiguration(
      providerType: .googleDrive,
      bucket: "",
      region: "",
      endpoint: nil,
      customDomain: nil,
      expireTime: .permanent
    )
    XCTAssertTrue(config.isValid)
  }

  // MARK: - Token refresh errors

  func testTokenRefreshFailure_rejectedGrant_asksToReconnect() {
    for statusCode in [400, 401] {
      let error = GoogleDriveCloudProvider.tokenRefreshFailure(
        CloudError.uploadFailed(statusCode: statusCode, message: "Token refresh failed: invalid_grant")
      )
      guard case CloudError.googleDriveAuthExpired = error else {
        return XCTFail("HTTP \(statusCode): expected googleDriveAuthExpired, got \(error)")
      }
    }
  }

  func testTokenRefreshFailure_serverOrNetworkError_passesThrough() {
    let serverError = GoogleDriveCloudProvider.tokenRefreshFailure(
      CloudError.uploadFailed(statusCode: 503, message: "unavailable")
    )
    guard case CloudError.uploadFailed(503, _) = serverError else {
      return XCTFail("Expected the 503 to pass through, got \(serverError)")
    }

    let offline = GoogleDriveCloudProvider.tokenRefreshFailure(URLError(.notConnectedToInternet))
    XCTAssertEqual((offline as? URLError)?.code, .notConnectedToInternet)
  }

  func testGoogleDriveAuthExpired_messageMentionsReconnect() {
    let message = CloudError.googleDriveAuthExpired.errorDescription ?? ""
    XCTAssertTrue(message.contains("Google Drive"))
    XCTAssertFalse(message.contains("Secret Key"))
  }
}
