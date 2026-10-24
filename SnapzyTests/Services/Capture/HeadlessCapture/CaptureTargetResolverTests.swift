//
//  CaptureTargetResolverTests.swift
//  SnapzyTests
//
//  Window, display and area selection rules for headless capture.
//

@testable import Snapzy
import XCTest

final class CaptureTargetResolverTests: XCTestCase {
  /// Front to back.
  private let candidates = [
    candidate(1, "Code", "com.microsoft.VSCode", title: "README.md — Snapzy"),
    candidate(2, "Safari", "com.apple.Safari", title: "Docs"),
    candidate(3, "Code", "com.microsoft.VSCode", title: "plan.md — Snapzy"),
    candidate(4, "Codex", "com.openai.codex", title: nil),
  ]

  private static func candidate(
    _ id: CGWindowID,
    _ owner: String,
    _ bundleID: String,
    title: String?
  ) -> WindowSelectionCandidate {
    WindowSelectionCandidate(
      target: WindowCaptureTarget(
        windowID: id,
        frame: CGRect(x: 0, y: 0, width: 800, height: 600),
        displayID: 1,
        title: title,
        bundleIdentifier: bundleID,
        ownerPID: Int32(id)
      ),
      ownerName: owner,
      windowLayer: 0
    )
  }

  private func resolve(_ selection: HeadlessCaptureRequest.WindowSelection) throws -> CaptureTargetResolver
    .ResolvedWindow {
    try CaptureTargetResolver.window(selection, in: candidates)
  }

  private func assertNotFound(
    _ selection: HeadlessCaptureRequest.WindowSelection,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(try resolve(selection), file: file, line: line) { error in
      guard case .targetNotFound = error as? HeadlessCaptureError else {
        return XCTFail("expected targetNotFound, got \(error)", file: file, line: line)
      }
    }
  }

  // MARK: - Windows

  func testWindowByID() throws {
    let resolved = try resolve(.id(2))

    XCTAssertEqual(resolved.candidate.target.windowID, 2)
    XCTAssertNil(resolved.matchedCandidates)
    assertNotFound(.id(99))
  }

  func testAppPicksFrontmostAndReportsMatchCount() throws {
    let resolved = try resolve(.app("code", titlePattern: nil, index: nil))

    XCTAssertEqual(resolved.candidate.target.windowID, 1)
    XCTAssertEqual(resolved.matchedCandidates, 2, "Codex is a prefix match and must not mix in")
  }

  func testAppByBundleIDAndIndex() throws {
    XCTAssertEqual(try resolve(.app("com.microsoft.VSCode", titlePattern: nil, index: 1)).candidate.target.windowID, 3)
    assertNotFound(.app("Code", titlePattern: nil, index: 2))
  }

  func testTitlePatternNarrowsBeforeIndex() throws {
    let resolved = try resolve(.app("Code", titlePattern: "^plan", index: nil))

    XCTAssertEqual(resolved.candidate.target.windowID, 3)
    XCTAssertEqual(resolved.matchedCandidates, 1)
    assertNotFound(.app("Code", titlePattern: "nothing", index: nil))
  }

  func testTitlePatternMatchesMissingTitleAsEmpty() throws {
    XCTAssertEqual(try resolve(.app("Codex", titlePattern: "^$", index: nil)).candidate.target.windowID, 4)
  }

  func testInvalidTitlePattern() {
    XCTAssertThrowsError(try resolve(.app("Code", titlePattern: "(", index: nil))) { error in
      guard case .invalidRequest = error as? HeadlessCaptureError else { return XCTFail("\(error)") }
    }
  }

  func testUnknownApp() {
    assertNotFound(.app("Xcode", titlePattern: nil, index: nil))
  }

  // MARK: - Displays

  func testDisplays() throws {
    XCTAssertEqual(try CaptureTargetResolver.displays(.main, available: [7, 9], mainDisplayID: 9), [9])
    XCTAssertEqual(try CaptureTargetResolver.displays(.all, available: [7, 9], mainDisplayID: 9), [7, 9])
    XCTAssertEqual(try CaptureTargetResolver.displays(.id(7), available: [7, 9], mainDisplayID: 9), [7])
    XCTAssertThrowsError(try CaptureTargetResolver.displays(.id(8), available: [7, 9], mainDisplayID: 9))
    XCTAssertThrowsError(try CaptureTargetResolver.displays(.all, available: [], mainDisplayID: 9))
  }

  // MARK: - Area

  func testAreaMustTouchADisplay() {
    let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: -1440, y: 0, width: 1440, height: 900)]

    XCTAssertNoThrow(try CaptureTargetResolver.validateArea(
      CGRect(x: -100, y: 10, width: 200, height: 200),
      screenFrames: screens
    ))
    XCTAssertThrowsError(try CaptureTargetResolver.validateArea(
      CGRect(x: 5000, y: 0, width: 10, height: 10),
      screenFrames: screens
    ))
    XCTAssertThrowsError(try CaptureTargetResolver.validateArea(
      CGRect(x: 0, y: 0, width: 0.5, height: 10),
      screenFrames: screens
    ))
  }

  func testAreaMustBeFullyOnScreen() {
    let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: -1440, y: 0, width: 1440, height: 900)]

    // Runs past the right edge of the main display.
    XCTAssertThrowsError(try CaptureTargetResolver.validateArea(
      CGRect(x: 1400, y: 0, width: 400, height: 300),
      screenFrames: screens
    )) { error in
      guard case .invalidRequest = error as? HeadlessCaptureError else { return XCTFail("\(error)") }
    }
    // Spans both displays but dips below the shorter left one.
    XCTAssertThrowsError(try CaptureTargetResolver.validateArea(
      CGRect(x: -100, y: 850, width: 200, height: 100),
      screenFrames: screens
    ))
    // Negative sizes are not standardized into a valid rect.
    XCTAssertThrowsError(try CaptureTargetResolver.validateArea(
      CGRect(x: 100, y: 100, width: -50, height: 50),
      screenFrames: screens
    ))
  }
}
