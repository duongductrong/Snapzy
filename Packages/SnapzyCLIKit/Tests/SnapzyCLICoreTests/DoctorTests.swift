//
//  DoctorTests.swift
//  SnapzyCLICoreTests
//

import Foundation
@testable import SnapzyCLICore
@testable import SnapzyCLIProtocol
import XCTest

final class DoctorTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("DoctorTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private func makeExecutable(_ relativePath: String) throws -> URL {
    let url = directory.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: [.posixPermissions: 0o755])
    return url.resolvingSymlinksInPath()
  }

  // MARK: - PATH

  func testPathPassesWhenLinkResolvesToThisBinary() throws {
    let helper = try makeExecutable("Snapzy.app/Contents/Helpers/snapzy")
    let bin = directory.appendingPathComponent("bin", isDirectory: true)
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("snapzy"), withDestinationURL: helper)

    let check = Doctor.pathCheck(path: "/nonexistent:\(bin.path)", executable: helper)

    XCTAssertTrue(check.ok, check.detail)
  }

  func testPathFlagsAnotherCopyWithoutFailingTheRun() throws {
    let helper = try makeExecutable("Snapzy.app/Contents/Helpers/snapzy")
    let other = try makeExecutable("bin/snapzy")

    let check = Doctor.pathCheck(path: other.deletingLastPathComponent().path, executable: helper)

    XCTAssertFalse(check.ok)
    XCTAssertNil(check.failureCode, "PATH is advisory")
  }

  func testPathMissing() {
    let check = Doctor.pathCheck(path: directory.path, executable: nil)

    XCTAssertFalse(check.ok)
    XCTAssertNotNil(check.hint)
  }

  func testPathMissingForCaskInstallPointsAtHomebrew() {
    let check = Doctor.pathCheck(path: directory.path, executable: nil, caskInstalled: true)

    XCTAssertFalse(check.ok)
    XCTAssertEqual(check.hint, Doctor.homebrewHint)
  }

  func testCaskInstallDetection() throws {
    let caskroom = directory.appendingPathComponent("Caskroom/snapzy")
    let helper = URL(fileURLWithPath: "/Applications/Snapzy.app/Contents/Helpers/snapzy")
    let debugHelper = URL(fileURLWithPath: "/tmp/Snapzy Debug.app/Contents/Helpers/snapzy")

    XCTAssertFalse(Doctor.isCaskInstall(executable: helper, caskroomPaths: [caskroom.path]))

    try FileManager.default.createDirectory(at: caskroom, withIntermediateDirectories: true)
    XCTAssertTrue(Doctor.isCaskInstall(executable: helper, caskroomPaths: [caskroom.path]))
    XCTAssertFalse(Doctor.isCaskInstall(executable: debugHelper, caskroomPaths: [caskroom.path]))
    XCTAssertFalse(Doctor.isCaskInstall(executable: nil, caskroomPaths: [caskroom.path]))
  }

  func testInstallHintQuotesThisBinary() {
    XCTAssertEqual(
      Doctor.installHint(for: URL(fileURLWithPath: "/tmp/Snapzy Debug.app/Contents/Helpers/snapzy")),
      "sudo mkdir -p /usr/local/bin && sudo ln -sfn '/tmp/Snapzy Debug.app/Contents/Helpers/snapzy' /usr/local/bin/snapzy"
    )
  }

  // MARK: - Status and exit code

  func testStatusChecksAndExitCode() {
    let checks = Doctor.statusChecks(CLIStatus(
      appVersion: "2.1.0",
      cliEnabled: true,
      onboardingCompleted: true,
      screenRecordingPermission: .denied,
      authorization: .undetermined
    ))

    XCTAssertEqual(checks.map(\.name), ["command line access", "onboarding", "screen recording", "authorization"])
    XCTAssertEqual(checks.map(\.ok), [true, true, false, true])
    XCTAssertEqual(DoctorReport(checks: checks).failureCode, .permissionDenied)
  }

  func testFirstCodedFailureWins() {
    let report = DoctorReport(checks: [
      .pass("cli", "ok"),
      .fail("path", "missing", hint: nil, code: nil),
      .fail("command line access", "disabled", hint: nil, code: .disabled),
      .fail("onboarding", "not completed", hint: nil, code: .onboardingIncomplete),
    ])

    XCTAssertEqual(report.failureCode, .disabled)
    XCTAssertNil(DoctorReport(checks: [.pass("cli", "ok"), .fail("path", "x", hint: nil, code: nil)]).failureCode)
  }

  func testHumanOutput() {
    let report = DoctorReport(checks: [
      .pass("app", "/Applications/Snapzy.app (com.trongduong.snapzy)"),
      .fail("screen recording", "not granted", hint: "Enable it", code: .permissionDenied),
    ])

    XCTAssertEqual(
      report.humanDescription,
      "✓ app: /Applications/Snapzy.app (com.trongduong.snapzy)\n✗ screen recording: not granted\n    hint: Enable it"
    )
  }
}
