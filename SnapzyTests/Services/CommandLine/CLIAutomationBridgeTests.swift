//
//  CLIAutomationBridgeTests.swift
//  SnapzyTests
//
//  `automation.list` ordering and fields, `automation.run` input/outcome
//  mapping, and one stable `CLIError` per launch rejection.
//

@testable import Snapzy
import SnapzyCLIProtocol
import XCTest

@MainActor
final class CLIAutomationBridgeTests: XCTestCase {
  private func automation(
    _ name: String,
    source: AutomationSource = .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false)),
    enabled: Bool = true,
    external: Bool = true
  ) -> Automation {
    Automation(
      name: name,
      isEnabled: enabled,
      source: source,
      steps: [AutomationStep(.copyImage), AutomationStep(.notify, isEnabled: false), AutomationStep(.upload), AutomationStep(.copyLink(AutomationLinkTemplate()))],
      externalInvocation: external
    )
  }

  // MARK: - List

  func testList_runnableFirstThenSettingsOrder() {
    let off = automation("Off", external: false)
    let disabled = automation("Disabled", enabled: false)
    let first = automation("First")
    let input = automation("Input", source: .input)

    let list = CLIAutomationBridge.list([off, first, disabled, input])

    XCTAssertEqual(list.automations.map(\.name), ["First", "Input", "Off", "Disabled"])
    XCTAssertEqual(
      list.automations[0],
      CLIAutomationSummary(
        id: first.id.uuidString,
        name: "First",
        source: "area",
        steps: ["copyImage", "upload", "copyLink"],
        enabled: true,
        external: true
      )
    )
    XCTAssertEqual(list.automations[1].source, "input")
    XCTAssertFalse(list.automations[2].external)
    XCTAssertFalse(list.automations[3].enabled)
  }

  // MARK: - Run

  func testInput_nilWithoutFilesAndAbsoluteOnly() throws {
    XCTAssertNil(try CLIAutomationBridge.input(for: nil))
    XCTAssertNil(try CLIAutomationBridge.input(for: []))

    let input = try XCTUnwrap(CLIAutomationBridge.input(for: ["/tmp/a/../shot.png"]))
    XCTAssertEqual(input.files.map(\.path), ["/tmp/shot.png"])
    XCTAssertFalse(input.isAlreadyInHistory)

    XCTAssertThrowsError(try CLIAutomationBridge.input(for: ["shot.png"])) { error in
      XCTAssertEqual((error as? CLIError)?.code, .invalidArguments)
    }
  }

  func testResult_finishedAndCancelled() throws {
    let report = AutomationRunReport(
      runID: UUID(),
      automationID: UUID(),
      files: [URL(fileURLWithPath: "/tmp/shot.png")],
      link: "https://x.test/a",
      message: "Link copied",
      isError: false
    )
    let finished = try CLIAutomationBridge.result(for: .finished(report), ref: "x", automationID: nil)
    XCTAssertEqual(finished, CLIAutomationRunResult(
      runId: report.runID.uuidString,
      automationId: report.automationID.uuidString,
      state: .finished,
      files: ["/tmp/shot.png"],
      link: "https://x.test/a",
      message: "Link copied",
      isError: false
    ))

    let id = UUID()
    let cancelled = try CLIAutomationBridge.result(for: .cancelled, ref: "x", automationID: id)
    XCTAssertEqual(cancelled.state, .cancelled)
    XCTAssertEqual(cancelled.automationId, id.uuidString)

    XCTAssertThrowsError(try CLIAutomationBridge.result(for: .rejected(.notFound), ref: "x", automationID: nil)) { error in
      XCTAssertEqual((error as? CLIError)?.code, .targetNotFound)
    }
  }

  // MARK: - Rejections

  func testRejectionCodes() {
    let ids = [UUID(), UUID()]
    let cases: [(AutomationLaunchRejection, CLIErrorCode)] = [
      (.notFound, .targetNotFound),
      (.ambiguousName(ids), .invalidArguments),
      (.disabled, .disabled),
      (.externalNotAllowed, .notAuthorized),
      (.urlSchemeDisabled, .disabled),
      (.unsupportedSource, .versionMismatch),
      (.needsFile, .invalidArguments),
      (.unsupportedFile("a.txt"), .invalidArguments),
      (.noStepAcceptsFile(.video), .invalidArguments),
      (.fileMissing("a.png"), .targetNotFound),
      (.permissionRequired, .permissionDenied),
      (.captureInProgress, .busy),
    ]
    for (rejection, code) in cases {
      XCTAssertEqual(CLIAutomationBridge.cliError(for: rejection, ref: " Cloud Share ").code, code, rejection.code)
    }
  }

  func testRejectionMessages() {
    let external = CLIAutomationBridge.cliError(for: .externalNotAllowed, ref: "Cloud Share")
    XCTAssertEqual(external.message, "Automation \"Cloud Share\" cannot be run from the command line")
    XCTAssertEqual(
      external.hint,
      "Enable 'Allow URL scheme, command line and Shortcuts' for this automation in Settings → Automations"
    )

    let ids = [UUID(), UUID()]
    let ambiguous = CLIAutomationBridge.cliError(for: .ambiguousName(ids), ref: "Share")
    for id in ids {
      XCTAssertTrue(ambiguous.message.contains(id.uuidString))
    }
  }
}
