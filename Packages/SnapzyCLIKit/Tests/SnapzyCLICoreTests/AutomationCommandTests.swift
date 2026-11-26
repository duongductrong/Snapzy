//
//  AutomationCommandTests.swift
//  SnapzyCLICoreTests
//
//  `snapzy automation list|run`: parsing, --file resolution, exit codes and
//  terminal output.
//

import ArgumentParser
@testable import SnapzyCLICore
@testable import SnapzyCLIProtocol
import XCTest

final class AutomationCommandTests: XCTestCase {
  private func parse<Command: ParsableCommand>(_: Command.Type, _ arguments: [String]) throws -> Command {
    let command = try SnapzyCommand.parseAsRoot(arguments)
    return try XCTUnwrap(command as? Command, "parsed \(Swift.type(of: command))")
  }

  private func assertUsageError(_ arguments: [String], file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertThrowsError(try SnapzyCommand.parseAsRoot(arguments), file: file, line: line) { error in
      XCTAssertEqual(SnapzyCommand.exitCode(for: error), .validationFailure, file: file, line: line)
    }
  }

  // MARK: - Parsing

  func testList_parses() throws {
    let command = try parse(AutomationCommand.List.self, ["automation", "list", "--json"])
    XCTAssertTrue(command.global.json)
    XCTAssertEqual(command.global.sessionOptions.requestTimeout, 30)
  }

  func testRun_defaults() throws {
    let command = try parse(AutomationCommand.Run.self, ["automation", "run", "Quick Copy"])

    XCTAssertEqual(command.automation, "Quick Copy")
    XCTAssertEqual(command.files, [])
    XCTAssertEqual(command.requestTimeout, 300)
    XCTAssertNil(command.global.timeoutOverride)
  }

  func testRun_filesAndTimeout() throws {
    let command = try parse(
      AutomationCommand.Run.self,
      ["automation", "run", "3F2A", "--file", "a.png", "--file", "/tmp/b.mov", "--timeout", "12", "--json"]
    )

    XCTAssertEqual(command.files, ["a.png", "/tmp/b.mov"])
    XCTAssertEqual(command.requestTimeout, 12)
    XCTAssertEqual(command.global.sessionOptions.requestTimeout, 12)
  }

  func testRun_rejectsBadArguments() {
    assertUsageError(["automation", "run"])
    assertUsageError(["automation", "run", "  "])
    assertUsageError(["automation", "run", "x", "--file", ""])
    assertUsageError(["automation", "run", "x", "--timeout", "0"])
  }

  // MARK: - Files

  func testResolveFiles_absoluteRelativeAndMissing() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("snapzy-automation-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("shot.png")
    FileManager.default.createFile(atPath: file.path, contents: Data([1]))

    let resolved = try AutomationCommand.resolveFiles(
      ["shot.png", "./sub/../shot.png", file.path],
      currentDirectory: directory
    )
    XCTAssertEqual(resolved, Array(repeating: file.standardizedFileURL.path, count: 3))

    XCTAssertThrowsError(try AutomationCommand.resolveFiles(["missing.png"], currentDirectory: directory)) { error in
      XCTAssertEqual((error as? CLIError)?.code, .targetNotFound)
    }
    XCTAssertThrowsError(try AutomationCommand.resolveFiles(["."], currentDirectory: directory)) { error in
      XCTAssertEqual((error as? CLIError)?.code, .invalidArguments)
    }
  }

  // MARK: - Exit codes

  func testExitCodes() {
    let finished = CLIAutomationRunResult(runId: "R", automationId: "A", state: .finished)
    let failed = CLIAutomationRunResult(runId: "R", automationId: "A", state: .finished, isError: true)
    let cancelled = CLIAutomationRunResult(runId: "R", automationId: "A", state: .cancelled)

    XCTAssertEqual(AutomationCommand.exitCode(for: finished), 0)
    XCTAssertEqual(AutomationCommand.exitCode(for: failed), 1)
    XCTAssertEqual(AutomationCommand.exitCode(for: cancelled), 6)
  }

  func testUnknownMethodBecomesUpdateHint() {
    let translated = AutomationCommand.translate(CLIError(.unknownMethod, "Snapzy does not support automation.run"),
                                                 appVersion: "2.2.0")
    XCTAssertEqual(translated.code, .unknownMethod)
    XCTAssertEqual(translated.message, "Update Snapzy to use automations")
    XCTAssertTrue(translated.hint?.contains("2.2.0") == true)

    let other = CLIError(.targetNotFound, "No automation named x")
    XCTAssertEqual(AutomationCommand.translate(other, appVersion: "2.2.0"), other)
  }

  // MARK: - Output

  func testHumanOutput_list() {
    let list = CLIAutomationList(automations: [
      CLIAutomationSummary(id: "A", name: "Cloud Share", source: "area",
                           steps: ["copyImage", "uploadAndCopyLink"], enabled: true, external: true),
      CLIAutomationSummary(id: "B", name: "Annotate", source: "input", steps: ["openAnnotate"],
                           enabled: false, external: false),
    ])

    XCTAssertEqual(list.humanDescription, """
    A  Cloud Share  area → copyImage, uploadAndCopyLink
    B  Annotate  input → openAnnotate  disabled  not allowed from the command line
    """)
    XCTAssertEqual(CLIAutomationList(automations: []).humanDescription, "No automations.")
  }

  func testHumanOutput_run() {
    let linked = CLIAutomationRunResult(runId: "R", automationId: "A", state: .finished, files: ["/tmp/a.png"],
                                        link: "https://x.test/a", message: "Link copied")
    XCTAssertEqual(linked.humanDescription, "Link copied: https://x.test/a\n/tmp/a.png")

    let copied = CLIAutomationRunResult(runId: "R", automationId: "A", state: .finished, files: ["/tmp/a.png"],
                                        message: "Image copied")
    XCTAssertEqual(copied.humanDescription, "Image copied\n/tmp/a.png")

    XCTAssertEqual(CLIAutomationRunResult(runId: "R", automationId: "A", state: .cancelled).humanDescription,
                   "Cancelled.")
  }
}
