import XCTest
@testable import Snapzy

@MainActor
final class AppBundleIdentityTests: XCTestCase {
  func testDevelopmentBuildAcceptsNormalIdentityUsedByInstalledApp() async {
    XCTAssertTrue(AppBundleIdentity.matches("com.trongduong.snapzy", debugBuild: true))
  }

  func testDevelopmentBuildAcceptsSeparateDebugIdentity() async {
    XCTAssertTrue(AppBundleIdentity.matches("com.trongduong.snapzy.debug", debugBuild: true))
  }

  func testReleaseBuildRequiresReleaseIdentity() async {
    XCTAssertTrue(AppBundleIdentity.matches("com.trongduong.snapzy", debugBuild: false))
    XCTAssertFalse(AppBundleIdentity.matches("com.trongduong.snapzy.debug", debugBuild: false))
  }

  func testNeitherBuildAcceptsMissingOrUnrelatedIdentity() async {
    for debugBuild in [true, false] {
      for identifier in [nil, "", "com.example.snapzy", "com.trongduong.snapzy.debug.other"] as [String?] {
        XCTAssertFalse(AppBundleIdentity.matches(identifier, debugBuild: debugBuild))
      }
    }
  }

  func testCurrentBuildUsesItsConfiguredDefault() async {
    XCTAssertTrue(AppBundleIdentity.matches(AppBundleIdentity.expected))
  }
}
