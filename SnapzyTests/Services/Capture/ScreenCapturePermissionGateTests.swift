//
//  ScreenCapturePermissionGateTests.swift
//  SnapzyTests
//
//  The capture hot path may only skip a full permission re-check when the cached
//  grant is still confirmed by the system (issue #509).
//

import XCTest
@testable import Snapzy

nonisolated final class ScreenCapturePermissionGateTests: XCTestCase {
  func testGrantedStatusIsTrustedOnlyWhileTheSystemStillGrantsAccess() {
    XCTAssertTrue(ScreenCaptureManager.canTrustGrantedStatus(.granted, systemGranted: true))
    XCTAssertFalse(
      ScreenCaptureManager.canTrustGrantedStatus(.granted, systemGranted: false),
      "revoked access must fall back to the full permission flow"
    )
  }

  func testNonGrantedStatusesAlwaysTakeTheFullCheck() {
    for status in [
      ScreenRecordingPermissionStatus.notGranted,
      .grantedButUnavailableDueToAppIdentity("quarantined"),
    ] {
      XCTAssertFalse(
        ScreenCaptureManager.canTrustGrantedStatus(status, systemGranted: true),
        "\(status) must fall back to the full permission flow"
      )
    }
  }

  func testOnlyIdentityBlockedStatusForcesAFreshIdentityCheck() {
    XCTAssertTrue(
      ScreenCaptureManager.needsFreshIdentityCheck(.grantedButUnavailableDueToAppIdentity("quarantined")),
      "a user who fixed the identity issue must not be blocked by a cached result"
    )
    XCTAssertFalse(ScreenCaptureManager.needsFreshIdentityCheck(.granted))
    XCTAssertFalse(ScreenCaptureManager.needsFreshIdentityCheck(.notGranted))
  }
}
