//
//  CLICaptureBridgeTests.swift
//  SnapzyTests
//
//  Wire ↔ headless-capture mapping, and that headless captures stay out of
//  the interactive post-capture pipeline.
//

import Combine
@testable import Snapzy
import SnapzyCLIProtocol
import XCTest

@MainActor
final class CLICaptureBridgeTests: XCTestCase {
  func testOptionsMapping() throws {
    let jpeg = try CLICaptureBridge.headlessOptions(
      CaptureOptions(format: .jpeg, quality: nil, maxDimension: 1568, showCursor: true, windowShadow: false)
    )

    guard case .jpeg(let quality) = jpeg.format else { return XCTFail("expected jpeg") }
    XCTAssertEqual(quality, 0.9, accuracy: 0.001)
    XCTAssertEqual(jpeg.maxDimension, 1568)
    XCTAssertTrue(jpeg.showCursor)
    XCTAssertFalse(jpeg.includeWindowShadow)
  }

  func testOptionsRejectOutOfRangeValues() {
    XCTAssertThrowsError(try CLICaptureBridge.headlessOptions(CaptureOptions(format: .jpeg, quality: 1.5))) { error in
      XCTAssertEqual((error as? CLIError)?.code, .invalidArguments)
    }
    XCTAssertThrowsError(try CLICaptureBridge.headlessOptions(CaptureOptions(maxDimension: 0))) { error in
      XCTAssertEqual((error as? CLIError)?.code, .invalidArguments)
    }
  }

  func testErrorMappingToExitCodes() {
    let cases: [(HeadlessCaptureError, CLIErrorCode)] = [
      (.permissionDenied, .permissionDenied),
      (.permissionUnavailable("relaunch"), .permissionDenied),
      (.onboardingIncomplete, .onboardingIncomplete),
      (.targetNotFound("x"), .targetNotFound),
      (.invalidRequest("x"), .invalidArguments),
      (.busy, .busy),
      (.screenLocked, .appUnavailable),
      (.captureFailed("x"), .internal),
    ]
    for (error, code) in cases {
      XCTAssertEqual(CLICaptureBridge.cliError(error).code, code, "\(error)")
    }
  }

  func testResultMappingFlipsWindowFrame() {
    let target = WindowCaptureTarget(
      windowID: 42,
      frame: CGRect(x: 10, y: 182, width: 1200, height: 800),
      displayID: 1,
      title: "README.md",
      bundleIdentifier: "com.microsoft.VSCode",
      ownerPID: 7
    )
    let result = HeadlessCaptureResult(
      files: [
        HeadlessCaptureResult.File(
          url: URL(fileURLWithPath: "/tmp/a.png"),
          pixelWidth: 2400,
          pixelHeight: 1600,
          scale: 2,
          byteCount: 10,
          displayID: 1,
          window: HeadlessCaptureResult.CapturedWindow(
            target: target,
            ownerName: "Code",
            isActive: true,
            matchedCandidates: 3
          )
        ),
      ],
      durationMs: 80
    )

    let mapped = CLICaptureBridge.cliResult(result, format: .png, mainDisplayHeight: 982)

    XCTAssertEqual(mapped.durationMs, 80)
    XCTAssertEqual(mapped.files.first?.path, "/tmp/a.png")
    XCTAssertEqual(mapped.files.first?.matchedCandidates, 3)
    XCTAssertEqual(mapped.files.first?.window?.frame, CLIRect(x: 10, y: 0, width: 1200, height: 800))
    XCTAssertEqual(
      mapped.files.first?.window?.app,
      CLIWindowOwner(name: "Code", bundleID: "com.microsoft.VSCode", pid: 7)
    )
    XCTAssertEqual(mapped.files.first?.window?.isActive, true)
  }

  func testInvocationFlags() {
    XCTAssertTrue(CaptureInvocation.interactive.emitsCompletion)
    XCTAssertTrue(CaptureInvocation.interactive.promptsForPermission)
    XCTAssertNil(CaptureInvocation.interactive.windowShadowOverride)

    let headless = CaptureInvocation.headless(includeWindowShadow: false)
    XCTAssertFalse(headless.emitsCompletion)
    XCTAssertFalse(headless.promptsForPermission)
    XCTAssertEqual(headless.windowShadowOverride, false)
  }

  /// Needs Screen Recording for the test host; skipped otherwise.
  func testHeadlessFullscreenCaptureDoesNotEmitCompletion() async throws {
    try XCTSkipUnless(CGPreflightScreenCaptureAccess(), "Screen Recording is not granted to the test host")
    try XCTSkipIf(HeadlessCaptureService.isScreenLocked, "No displays to capture while the screen is locked")
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("HeadlessCaptureIntegration-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    var emitted: [URL] = []
    let subscription = ScreenCaptureManager.shared.captureCompletedPublisher.sink { emitted.append($0) }
    defer { subscription.cancel() }

    let result = await ScreenCaptureManager.shared.captureFullscreen(
      saveDirectory: directory,
      fileName: "headless",
      displayID: CGMainDisplayID(),
      excludeOwnApplication: true,
      invocation: .headless(includeWindowShadow: true)
    )

    guard case .success(let url) = result else { return XCTFail("capture failed: \(result)") }
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    XCTAssertEqual(emitted, [])
  }
}
