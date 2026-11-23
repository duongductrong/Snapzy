//
//  RecordCommandTests.swift
//  SnapzyCLICoreTests
//
//  `snapzy record`: argument parsing, the attached wait loop, and delivering
//  the staged video to the starter's or the stopper's --output.
//

import ArgumentParser
@testable import SnapzyCLICore
@testable import SnapzyCLIProtocol
import XCTest

final class RecordCommandParsingTests: XCTestCase {
  private func parse<Command: ParsableCommand>(_: Command.Type, _ arguments: [String]) throws -> Command {
    let command = try SnapzyCommand.parseAsRoot(arguments)
    return try XCTUnwrap(command as? Command, "parsed \(Swift.type(of: command))")
  }

  private func assertUsageError(_ arguments: [String], file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertThrowsError(try SnapzyCommand.parseAsRoot(arguments), file: file, line: line) { error in
      XCTAssertEqual(SnapzyCommand.exitCode(for: error), .validationFailure, file: file, line: line)
    }
  }

  func testScreen_defaults() throws {
    let command = try parse(RecordScreenCommand.self, ["record", "screen"])

    XCTAssertEqual(command.display, .main)
    XCTAssertEqual(try command.output.recordingOptions(), RecordingOptions())
    XCTAssertFalse(command.output.detach)
    XCTAssertNil(command.output.duration)
  }

  func testScreen_allOptions() throws {
    let command = try parse(RecordScreenCommand.self, [
      "record", "screen", "--display", "3", "-o", "demo.mp4", "--quality", "low", "--fps", "60",
      "--no-cursor", "--system-audio", "--mic", "--duration", "2.5",
    ])

    XCTAssertEqual(command.display, .id(3))
    XCTAssertEqual(command.output.duration, 2.5)
    XCTAssertEqual(
      try command.output.recordingOptions(),
      RecordingOptions(format: .mp4, quality: .low, fps: 60, showCursor: false, systemAudio: true, microphone: true)
    )
  }

  func testScreen_rejectsAllDisplays() {
    assertUsageError(["record", "screen", "--display", "all"])
  }

  func testFormat_fromExtensionOrFlag() throws {
    XCTAssertEqual(try parse(RecordScreenCommand.self, ["record", "screen", "-o", "a.MOV"]).output.resolvedFormat(), .mov)
    XCTAssertEqual(try parse(RecordScreenCommand.self, ["record", "screen", "-o", "out/"]).output.resolvedFormat(), .mov)
    XCTAssertEqual(
      try parse(RecordScreenCommand.self, ["record", "screen", "-o", "out/", "--format", "mp4"]).output.resolvedFormat(),
      .mp4
    )
    XCTAssertEqual(
      try parse(RecordScreenCommand.self, ["record", "screen", "-o", NSTemporaryDirectory()]).output.resolvedFormat(),
      .mov,
      "an existing directory without a trailing slash"
    )
  }

  func testOutput_invalidPathsAreUsageErrors() {
    assertUsageError(["record", "screen", "-o", "shot.png"])
    assertUsageError(["record", "screen", "-o", "no-extension-\(UUID().uuidString)"])
    assertUsageError(["record", "screen", "-o", "-"])
    assertUsageError(["record", "screen", "-o", "a.mov", "--format", "mp4"])
    assertUsageError(["record", "stop", "-o", "-"])
  }

  func testOptions_validation() {
    assertUsageError(["record", "screen", "--fps", "24"])
    assertUsageError(["record", "screen", "--duration", "0"])
    assertUsageError(["record", "screen", "--duration", "5", "--detach"])
    assertUsageError(["record", "screen", "--quality", "ultra"])
  }

  func testWindowAndArea_reuseCaptureSelectors() throws {
    let window = try parse(RecordWindowCommand.self, ["record", "window", "--app", "Safari", "--index", "1"])
    let area = try parse(RecordAreaCommand.self, ["record", "area", "--rect", "-1440,0,800,600", "--detach"])

    XCTAssertEqual(try window.selection.selector(), .app(AppWindowQuery(app: "Safari", index: 1)))
    XCTAssertEqual(area.selection.rect, CLIRect(x: -1440, y: 0, width: 800, height: 600))
    XCTAssertTrue(area.output.detach)
    assertUsageError(["record", "window"])
    assertUsageError(["record", "area"])
  }

  func testStopAndStatus() throws {
    let stop = try parse(RecordStopCommand.self, ["record", "stop", "--id", "abc", "-o", "x.mov", "--force"])

    XCTAssertEqual(stop.id, "abc")
    XCTAssertEqual(stop.output, "x.mov")
    XCTAssertTrue(stop.force)
    XCTAssertNoThrow(try parse(RecordStatusCommand.self, ["record", "status", "--json"]))
  }

  func testHelpHintPathIncludesRecordSubcommand() {
    XCTAssertEqual(SnapzyCommand.subcommandPath(in: ["record", "screen", "-o", "x"]), ["record", "screen"])
  }
}

final class RecordingWaiterTests: XCTestCase {
  private final class Clock {
    var now = Date(timeIntervalSince1970: 0)
  }

  private func waiter(
    duration: TimeInterval? = nil,
    stopRequest: StopRequest = StopRequest(),
    clock: Clock,
    onSleep: @escaping (Int) -> Void = { _ in },
    status: @escaping () throws -> CLIRecordingStatus
  ) -> RecordingWaiter {
    var waiter = RecordingWaiter(id: "rec", duration: duration, stopRequest: stopRequest, status: status)
    var ticks = 0
    waiter.now = { clock.now }
    waiter.sleep = { interval in
      ticks += 1
      clock.now += interval
      onSleep(ticks)
    }
    return waiter
  }

  private static let running = CLIRecordingStatus(
    recording: CLIRecordingInfo(id: "rec", state: .recording, format: .mov, rect: CLIRect(x: 0, y: 0, width: 1, height: 1))
  )

  func testDurationEndsTheWait() throws {
    let clock = Clock()
    var polls = 0
    let reason = try waiter(duration: 3, clock: clock) {
      polls += 1
      return Self.running
    }.wait()

    XCTAssertEqual(reason, .duration)
    XCTAssertEqual(clock.now.timeIntervalSince1970, 3, accuracy: 0.1)
    XCTAssertEqual(polls, 2, "polled about once a second")
  }

  func testStopRequestEndsTheWait() throws {
    let clock = Clock()
    let stop = StopRequest()
    let reason = try waiter(stopRequest: stop, clock: clock, onSleep: { if $0 == 10 { stop.request() } }) {
      Self.running
    }.wait()

    XCTAssertEqual(reason, .signal)
  }

  func testRecordingEndingElsewhereEndsTheWait() throws {
    let clock = Clock()
    var polls = 0
    let reason = try waiter(clock: clock) {
      polls += 1
      return polls < 3 ? Self.running : CLIRecordingStatus(recording: nil)
    }.wait()

    XCTAssertEqual(reason, .stoppedElsewhere)
    XCTAssertEqual(polls, 3)
  }

  func testStatusFailurePropagates() {
    let clock = Clock()
    XCTAssertThrowsError(try waiter(clock: clock) { throw CLIError(.appUnavailable, "gone") }.wait()) { error in
      XCTAssertEqual((error as? CLIError)?.code, .appUnavailable)
    }
  }
}

final class RecordDeliveryTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyRecordTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private func staged(output: CLIRecordingOutput?) throws -> CLIRecordingResult {
    let staging = directory.appendingPathComponent("staging", isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    let url = staging.appendingPathComponent("snapzy-cli-rec.mov")
    try Data("video".utf8).write(to: url)
    let file = CLIRecordedFile(path: url.path, format: .mov, width: 20, height: 10, durationSeconds: 1.5, bytes: 5)
    return CLIRecordingResult(id: "snapzy-cli-rec", file: file, output: output)
  }

  private func deliver(_ result: CLIRecordingResult, override: CLIRecordingOutput? = nil) throws -> CLIRecordingResult {
    try RecordCommand.deliver(result, override: override, writer: OutputWriter(), currentDirectory: directory)
  }

  func testStartersOutputFile() throws {
    let target = directory.appendingPathComponent("nested/demo.mov")
    let delivered = try deliver(staged(output: CLIRecordingOutput(path: target.path)))

    XCTAssertEqual(delivered.file.path, target.path)
    XCTAssertNil(delivered.output)
    XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "video")
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("staging/snapzy-cli-rec.mov").path))
  }

  func testDirectoryKeepsStagingName() throws {
    let output = OutputDestination.resolve("clips/", currentDirectory: directory).recordingOutput(force: false)
    XCTAssertEqual(output?.path, directory.appendingPathComponent("clips").path + "/")

    let delivered = try deliver(staged(output: output))
    XCTAssertEqual(delivered.file.path, directory.appendingPathComponent("clips/snapzy-cli-rec.mov").path)
  }

  func testStopOverrideWinsOverStartersOutput() throws {
    let starter = directory.appendingPathComponent("starter.mov")
    let stopper = directory.appendingPathComponent("stopper.mov")
    let delivered = try deliver(
      staged(output: CLIRecordingOutput(path: starter.path)),
      override: CLIRecordingOutput(path: stopper.path)
    )

    XCTAssertEqual(delivered.file.path, stopper.path)
    XCTAssertFalse(FileManager.default.fileExists(atPath: starter.path))
  }

  func testNoOutputLeavesFileInStaging() throws {
    let result = try staged(output: nil)
    XCTAssertEqual(try deliver(result).file.path, result.file.path)
  }

  func testExistingTargetNeedsForceAndNamesStagedFile() throws {
    let target = directory.appendingPathComponent("demo.mov")
    try Data("old".utf8).write(to: target)
    let result = try staged(output: CLIRecordingOutput(path: target.path))

    XCTAssertThrowsError(try deliver(result)) { error in
      let error = error as? CLIError
      XCTAssertEqual(error?.code, .invalidArguments)
      XCTAssertTrue(error?.hint?.contains(result.file.path) ?? false)
    }
    let forced = try deliver(staged(output: CLIRecordingOutput(path: target.path, force: true)))
    XCTAssertEqual(forced.file.path, target.path)
    XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "video")
  }

  func testHumanReadable() throws {
    let result = CLIRecordingResult(
      id: "r",
      file: CLIRecordedFile(path: "/tmp/demo.mov", format: .mov, width: 2880, height: 1800,
                            durationSeconds: 75.2, bytes: 1_000_000)
    )
    XCTAssertTrue(try OutputRenderer(mode: .human).render(result).hasPrefix("/tmp/demo.mov  2880x1800  1m 15s  "))

    let status = CLIRecordingStatus(recording: nil, interactiveRecordingActive: true)
    XCTAssertEqual(
      try OutputRenderer(mode: .human).render(status),
      "No snapzy recording. Snapzy is recording from its own toolbar.\n"
    )
  }
}
