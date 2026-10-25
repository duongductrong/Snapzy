//
//  ProtocolModelTests.swift
//  SnapzyCLIProtocolTests
//

@testable import SnapzyCLIProtocol
import XCTest

final class ProtocolModelTests: XCTestCase {
  // MARK: - ProtocolVersion

  func testProtocolVersion_parsesAndCompares() {
    XCTAssertEqual(ProtocolVersion(string: "1.2"), ProtocolVersion(major: 1, minor: 2))
    XCTAssertNil(ProtocolVersion(string: "1"))
    XCTAssertNil(ProtocolVersion(string: "1.2.3"))
    XCTAssertNil(ProtocolVersion(string: "a.b"))
    XCTAssertNil(ProtocolVersion(string: "-1.0"))

    XCTAssertTrue(ProtocolVersion(major: 1, minor: 0).isCompatible(with: ProtocolVersion(major: 1, minor: 9)))
    XCTAssertFalse(ProtocolVersion(major: 1, minor: 0).isCompatible(with: ProtocolVersion(major: 2, minor: 0)))
    XCTAssertLessThan(ProtocolVersion(major: 1, minor: 9), ProtocolVersion(major: 2, minor: 0))
  }

  func testProtocolVersion_rejectsMalformedJSON() {
    XCTAssertThrowsError(try CLIJSON.makeDecoder().decode(ProtocolVersion.self, from: Data(#""v1""#.utf8)))
  }

  // MARK: - CLIRect

  func testRect_parsesArgument() {
    XCTAssertEqual(CLIRect(argument: "10,20,300,200"), CLIRect(x: 10, y: 20, width: 300, height: 200))
    XCTAssertEqual(CLIRect(argument: "-1440, -900, 100.5, 50"), CLIRect(x: -1440, y: -900, width: 100.5, height: 50))
  }

  func testRect_rejectsInvalidArgument() {
    XCTAssertNil(CLIRect(argument: "1,2,3"))
    XCTAssertNil(CLIRect(argument: "1,2,3,4,5"))
    XCTAssertNil(CLIRect(argument: "0,0,0,10"))
    XCTAssertNil(CLIRect(argument: "0,0,10,-1"))
    XCTAssertNil(CLIRect(argument: "0,0,inf,10"))
    XCTAssertNil(CLIRect(argument: "a,b,c,d"))
  }

  func testRect_descriptionRoundTrips() {
    XCTAssertEqual(CLIRect(x: -1440, y: 0, width: 100.5, height: 50).description, "-1440,0,100.5,50")
  }

  // MARK: - Selectors and formats

  func testDisplaySelector_parsesArgument() {
    XCTAssertEqual(DisplaySelector(argument: "main"), .main)
    XCTAssertEqual(DisplaySelector(argument: "ALL"), .all)
    XCTAssertEqual(DisplaySelector(argument: "69733382"), .id(69_733_382))
    XCTAssertNil(DisplaySelector(argument: "primary"))
    XCTAssertNil(DisplaySelector(argument: "-1"))
  }

  func testImageFormat_fileExtensions() {
    XCTAssertEqual(CLIImageFormat(fileExtension: "JPG"), .jpeg)
    XCTAssertEqual(CLIImageFormat(fileExtension: "jpeg"), .jpeg)
    XCTAssertEqual(CLIImageFormat(fileExtension: "webp"), .webp)
    XCTAssertNil(CLIImageFormat(fileExtension: "gif"))
    XCTAssertEqual(CLIImageFormat.jpeg.fileExtension, "jpg")
  }

  // MARK: - Exit codes

  func testErrorCodes_mapToDocumentedExitCodes() {
    let expected: [CLIErrorCode: Int32] = [
      .internal: 1,
      .invalidArguments: 2,
      .permissionDenied: 3,
      .onboardingIncomplete: 3,
      .targetNotFound: 4,
      .appUnavailable: 5,
      .launchTimeout: 5,
      .disabled: 5,
      .busy: 5,
      .versionMismatch: 5,
      .unknownMethod: 5,
      .notAuthorized: 7,
    ]

    XCTAssertEqual(Set(expected.keys), Set(CLIErrorCode.allCases))
    for code in CLIErrorCode.allCases {
      XCTAssertEqual(code.exitCode, expected[code], "\(code)")
    }
  }

  // MARK: - SocketLocation

  func testSocketLocation_prefersApplicationSupport() {
    let path = SocketLocation.path(
      forAppBundleID: "com.trongduong.snapzy",
      environment: [:],
      homeDirectory: URL(fileURLWithPath: "/Users/dev", isDirectory: true),
      userTemporaryDirectory: URL(fileURLWithPath: "/var/folders/xy/T", isDirectory: true)
    )

    XCTAssertEqual(path, "/Users/dev/Library/Application Support/Snapzy/CLI/com.trongduong.snapzy.sock")
  }

  func testSocketLocation_fallsBackForLongHomePaths() {
    let longHome = URL(fileURLWithPath: "/Users/" + String(repeating: "a", count: 60), isDirectory: true)

    let path = SocketLocation.path(
      forAppBundleID: "com.trongduong.snapzy.debug",
      environment: [:],
      homeDirectory: longHome,
      userTemporaryDirectory: URL(fileURLWithPath: "/var/folders/xy/T", isDirectory: true)
    )

    XCTAssertEqual(path, "/var/folders/xy/T/snapzy-cli/com.trongduong.snapzy.debug.sock")
    XCTAssertLessThanOrEqual(path.utf8.count, SocketLocation.maxPathByteCount)
  }

  func testSocketLocation_environmentOverrideWins() {
    let path = SocketLocation.path(
      forAppBundleID: "com.trongduong.snapzy",
      environment: [SocketLocation.environmentOverrideKey: "/tmp/s.sock"],
      homeDirectory: URL(fileURLWithPath: "/Users/dev", isDirectory: true),
      userTemporaryDirectory: nil
    )

    XCTAssertEqual(path, "/tmp/s.sock")
  }

  func testDarwinUserTemporaryDirectory_resolves() throws {
    let directory = try XCTUnwrap(SocketLocation.darwinUserTemporaryDirectory())
    XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
  }
}
