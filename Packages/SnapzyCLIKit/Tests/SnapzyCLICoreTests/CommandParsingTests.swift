//
//  CommandParsingTests.swift
//  SnapzyCLICoreTests
//

import ArgumentParser
@testable import SnapzyCLICore
@testable import SnapzyCLIProtocol
import XCTest

final class CommandParsingTests: XCTestCase {
  private func parse<Command: ParsableCommand>(_: Command.Type, _ arguments: [String]) throws -> Command {
    let command = try SnapzyCommand.parseAsRoot(arguments)
    return try XCTUnwrap(command as? Command, "parsed \(Swift.type(of: command))")
  }

  private func assertUsageError(_ arguments: [String], file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertThrowsError(try SnapzyCommand.parseAsRoot(arguments), file: file, line: line) { error in
      XCTAssertEqual(SnapzyCommand.exitCode(for: error), .validationFailure, file: file, line: line)
    }
  }

  // MARK: - capture window

  func testWindow_appWithFilters() throws {
    let command = try parse(
      WindowCommand.self,
      ["capture", "window", "--app", "Safari", "--title", "^Docs", "--index", "1"]
    )

    XCTAssertEqual(try command.selector(), .app(AppWindowQuery(app: "Safari", titlePattern: "^Docs", index: 1)))
  }

  func testWindow_idAndActive() throws {
    XCTAssertEqual(try parse(WindowCommand.self, ["capture", "window", "--id", "42"]).selector(), .id(42))
    XCTAssertEqual(try parse(WindowCommand.self, ["capture", "window", "--active"]).selector(), .active)
  }

  func testWindow_requiresExactlyOneSelector() {
    assertUsageError(["capture", "window"])
    assertUsageError(["capture", "window", "--id", "1", "--app", "Safari"])
    assertUsageError(["capture", "window", "--app", "Safari", "--active"])
  }

  func testWindow_filtersOnlyWithApp() {
    assertUsageError(["capture", "window", "--id", "1", "--title", "x"])
    assertUsageError(["capture", "window", "--active", "--index", "0"])
  }

  func testWindow_rejectsBadFilters() {
    assertUsageError(["capture", "window", "--app", "Safari", "--title", "("])
    assertUsageError(["capture", "window", "--app", "Safari", "--index", "-1"])
  }

  func testWindow_noShadowFlowsIntoOptions() throws {
    let command = try parse(WindowCommand.self, ["capture", "window", "--active", "--no-shadow"])

    XCTAssertFalse(try command.output.captureOptions(windowShadow: !command.noShadow).windowShadow)
  }

  // MARK: - capture screen / area

  func testScreen_displaySelector() throws {
    XCTAssertEqual(try parse(ScreenCommand.self, ["capture", "screen"]).display, .main)
    XCTAssertEqual(try parse(ScreenCommand.self, ["capture", "screen", "--display", "all"]).display, .all)
    XCTAssertEqual(try parse(ScreenCommand.self, ["capture", "screen", "--display", "7"]).display, .id(7))
    assertUsageError(["capture", "screen", "--display", "left"])
  }

  func testArea_rect() throws {
    let command = try parse(AreaCommand.self, ["capture", "area", "--rect", "-1440,0,800,600"])
    let withEquals = try parse(AreaCommand.self, ["capture", "area", "--rect=-1440,-900,10,10"])

    XCTAssertEqual(command.rect, CLIRect(x: -1440, y: 0, width: 800, height: 600))
    XCTAssertEqual(withEquals.rect, CLIRect(x: -1440, y: -900, width: 10, height: 10))
    assertUsageError(["capture", "area"])
    assertUsageError(["capture", "area", "--rect", "0,0,0,0"])
  }

  // MARK: - Output options

  func testFormat_inferredFromOutputExtension() throws {
    let jpg = try parse(ScreenCommand.self, ["capture", "screen", "-o", "shot.JPG"])
    let directory = try parse(ScreenCommand.self, ["capture", "screen", "-o", "out.d/"])
    let stdout = try parse(ScreenCommand.self, ["capture", "screen", "-o", "-"])
    let explicit = try parse(ScreenCommand.self, ["capture", "screen", "--format", "webp"])

    XCTAssertEqual(try jpg.output.resolvedFormat(), .jpeg)
    XCTAssertEqual(try directory.output.resolvedFormat(), .png)
    XCTAssertEqual(try stdout.output.resolvedFormat(), .png)
    XCTAssertEqual(try explicit.output.resolvedFormat(), .webp)
  }

  func testFormat_conflictWithExtensionIsRejected() {
    assertUsageError(["capture", "screen", "-o", "shot.png", "--format", "jpg"])
  }

  func testQualityAndMaxDimensionValidation() throws {
    let command = try parse(
      ScreenCommand.self,
      ["capture", "screen", "--format", "jpg", "--quality", "0.7", "--max-dimension", "1568", "--cursor"]
    )
    XCTAssertEqual(
      try command.output.captureOptions(),
      CaptureOptions(format: .jpeg, quality: 0.7, maxDimension: 1568, showCursor: true)
    )

    assertUsageError(["capture", "screen", "--quality", "0.7"])
    assertUsageError(["capture", "screen", "--format", "jpg", "--quality", "1.5"])
    assertUsageError(["capture", "screen", "--max-dimension", "0"])
  }

  // MARK: - Global options

  func testGlobalOptions() throws {
    let command = try parse(
      ListCommand.Windows.self,
      ["list", "windows", "--app", "Code", "--all", "--json", "--timeout", "5", "--no-launch"]
    )

    XCTAssertEqual(command.app, "Code")
    XCTAssertTrue(command.all)
    XCTAssertEqual(command.global.sessionOptions.requestTimeout, 5)
    XCTAssertFalse(command.global.sessionOptions.allowsLaunch)
    assertUsageError(["status", "--timeout", "0"])
  }
}
