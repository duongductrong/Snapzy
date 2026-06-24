//
//  SnapzyConfigurationPathsTests.swift
//  SnapzyTests
//
//  Tests for user-managed TOML configuration paths.
//

import Darwin
import XCTest
@testable import Snapzy

@MainActor
final class SnapzyConfigurationPathsTests: XCTestCase {
  func testSuggestedConfigURLUsesProvidedHomeDirectory() {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

    let url = SnapzyConfigurationPaths.suggestedConfigURL(homeDirectory: home)

    XCTAssertEqual(url.path, "/Users/example/.config/snapzy/config.toml")
  }

  func testSuggestedConfigDirectoryURLUsesProvidedHomeDirectory() {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

    let url = SnapzyConfigurationPaths.suggestedConfigDirectoryURL(homeDirectory: home)

    XCTAssertEqual(url.path, "/Users/example/.config/snapzy")
  }

  func testCollapsingHomePathConvertsAbsolutePathToTilde() {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

    XCTAssertEqual(
      SnapzyConfigurationPaths.collapsingHomePath("/Users/example/Desktop", homeDirectory: home),
      "~/Desktop"
    )
    XCTAssertEqual(
      SnapzyConfigurationPaths.collapsingHomePath("/Users/example", homeDirectory: home),
      "~"
    )
    XCTAssertEqual(
      SnapzyConfigurationPaths.collapsingHomePath("/tmp/snapzy", homeDirectory: home),
      "/tmp/snapzy"
    )
  }

  func testExpandedUserPathUsesProvidedHomeDirectory() {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

    XCTAssertEqual(
      SnapzyConfigurationPaths.expandedUserPath("~/Desktop", homeDirectory: home),
      "/Users/example/Desktop"
    )
    XCTAssertEqual(
      SnapzyConfigurationPaths.expandedUserPath("/tmp/snapzy", homeDirectory: home),
      "/tmp/snapzy"
    )
  }

  func testSuggestedConfigURLUsesAccountHomeDirectory() throws {
    guard
      let passwd = getpwuid(getuid()),
      let home = passwd.pointee.pw_dir
    else {
      throw XCTSkip("No POSIX home directory is available for the current user.")
    }

    let expectedHome = URL(fileURLWithPath: String(cString: home), isDirectory: true)
    let expectedURL = SnapzyConfigurationPaths.suggestedConfigURL(homeDirectory: expectedHome)

    XCTAssertEqual(SnapzyConfigurationService.shared.suggestedConfigURL.path, expectedURL.path)
  }
}
