//
//  CLIRecordBridgeTests.swift
//  SnapzyTests
//
//  Wire ↔ headless-recording mapping, request validation, and stop errors
//  when nothing is recording.
//

@testable import Snapzy
import SnapzyCLIProtocol
import XCTest

@MainActor
final class CLIRecordBridgeTests: XCTestCase {
  func testOptionsMapping() {
    let request = CLIRecordBridge.request(
      .screen(.main),
      options: RecordingOptions(format: .mp4, quality: .medium, fps: 60, showCursor: false,
                                systemAudio: true, microphone: true)
    )

    XCTAssertEqual(request.target, .screen(.main))
    XCTAssertEqual(request.format, .mp4)
    XCTAssertEqual(request.quality, .medium)
    XCTAssertEqual(request.fps, 60)
    XCTAssertFalse(request.showCursor)
    XCTAssertTrue(request.systemAudio)
    XCTAssertTrue(request.microphone)

    let defaults = CLIRecordBridge.request(.area(.zero), options: RecordingOptions())
    XCTAssertEqual(defaults.format, .mov)
    XCTAssertEqual(defaults.quality, .high)
    XCTAssertTrue(defaults.showCursor)
    XCTAssertFalse(defaults.systemAudio)
    XCTAssertFalse(defaults.microphone)
  }

  func testValidationRejectsAllDisplaysAndOddFrameRates() {
    XCTAssertThrowsError(try HeadlessRecordingService.validate(.init(target: .screen(.all)))) { error in
      XCTAssertEqual(CLICaptureBridge.cliError(error as! HeadlessCaptureError).code, .invalidArguments)
    }
    var request = HeadlessRecordingService.Request(target: .screen(.main))
    request.fps = 24
    XCTAssertThrowsError(try HeadlessRecordingService.validate(request))
    request.fps = 60
    XCTAssertNoThrow(try HeadlessRecordingService.validate(request))
  }

  func testAreaIsClampedToTheDisplayItOverlapsMost() {
    let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let right = CGRect(x: 1512, y: 0, width: 1920, height: 1080)

    XCTAssertEqual(
      HeadlessRecordingService.clampToBestDisplay(CGRect(x: 1400, y: 100, width: 400, height: 300),
                                                  screenFrames: [main, right]),
      CGRect(x: 1512, y: 100, width: 288, height: 300)
    )
    XCTAssertEqual(
      HeadlessRecordingService.clampToBestDisplay(CGRect(x: 10, y: 10, width: 50, height: 50), screenFrames: [main]),
      CGRect(x: 10, y: 10, width: 50, height: 50)
    )
  }

  func testInfoFlipsToTopLeftAndCarriesOutput() {
    let started = HeadlessRecordingService.Started(
      id: "snapzy-cli-1",
      rect: CGRect(x: 0, y: 182, width: 800, height: 600),
      displayID: 1,
      window: nil,
      format: .mp4
    )
    let output = CLIRecordingOutput(path: "/tmp/demo.mp4")

    let info = CLIRecordBridge.info(started, state: .paused, elapsedSeconds: 7, output: output, mainDisplayHeight: 982)

    XCTAssertEqual(info.rect, CLIRect(x: 0, y: 200, width: 800, height: 600))
    XCTAssertEqual(info.format, .mp4)
    XCTAssertEqual(info.state, .paused)
    XCTAssertEqual(info.elapsedSeconds, 7)
    XCTAssertEqual(info.displayID, 1)
    XCTAssertEqual(info.output, output)
  }

  func testStateMapping() {
    XCTAssertEqual(CLIRecordBridge.cliState(.recording), .recording)
    XCTAssertEqual(CLIRecordBridge.cliState(.paused), .paused)
    XCTAssertEqual(CLIRecordBridge.cliState(.stopping), .stopping)
  }

  func testFileMappingRoundsDuration() {
    let finished = HeadlessRecordingService.Finished(
      id: "r",
      url: URL(fileURLWithPath: "/tmp/r.mov"),
      format: .mov,
      pixelWidth: 2880,
      pixelHeight: 1800,
      durationSeconds: 3.333333,
      byteCount: 42
    )

    XCTAssertEqual(
      CLIRecordBridge.cliFile(finished),
      CLIRecordedFile(path: "/tmp/r.mov", format: .mov, width: 2880, height: 1800, durationSeconds: 3.333, bytes: 42)
    )
  }

  func testRecorderErrorsMapToCLICodes() {
    let cases: [(RecordingError, CLIErrorCode)] = [
      (.permissionDenied, .permissionDenied),
      (.microphonePermissionDenied, .permissionDenied),
      (.noDisplayFound, .targetNotFound),
      (.alreadyActive, .busy),
      (.setupFailed("x"), .internal),
      (.writeFailed("x"), .internal),
    ]
    for (error, code) in cases {
      XCTAssertEqual(CLICaptureBridge.cliError(HeadlessRecordingService.captureError(error)).code, code, "\(error)")
    }
  }

  func testStopWithNothingRecordingIsTargetNotFound() async {
    let service = HeadlessRecordingService(recorder: .shared)
    do {
      _ = try await service.stop(id: nil)
      XCTFail("expected an error")
    } catch let error as HeadlessCaptureError {
      let cliError = CLIRecordBridge.stopError(error)
      XCTAssertEqual(cliError.code, .targetNotFound)
      XCTAssertNotNil(cliError.hint)
    } catch {
      XCTFail("unexpected \(error)")
    }

    do {
      _ = try await service.stop(id: "missing")
      XCTFail("expected an error")
    } catch {
      XCTAssertEqual(error as? HeadlessCaptureError, .targetNotFound(
        "Recording missing is not in progress and its file was already collected"
      ))
    }
    XCTAssertFalse(service.isActive)
  }
}
