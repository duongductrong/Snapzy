//
//  SnapzyConfigurationAutomationsTests.swift
//  SnapzyTests
//
//  `[automations.<id>]` export / import round trip and validation.
//

import Carbon.HIToolbox
import XCTest
@testable import Snapzy

@MainActor
final class SnapzyConfigurationAutomationsTests: XCTestCase {
  func testRoundTripPreservesOrderFieldsAndShortcut() throws {
    var cloud = AutomationPreset.cloudShare.makeAutomation()
    cloud.hotkey = ShortcutConfig(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(controlKey | shiftKey))
    cloud.steps[1].content = .action(.uploadAndCopyLink(.markdown))
    var custom = Automation(
      name: "Window \"docs\"",
      isEnabled: false,
      source: .capture(AutomationCaptureSpec(mode: .activeWindow, saveToExportDirectory: true)),
      steps: [AutomationStep(.copyImage), AutomationStep(.showQuickAccess), AutomationStep(.openAnnotate)]
    )
    custom.externalInvocation = true

    var writer = SimpleTOMLWriter()
    SnapzyConfigurationAutomationsCodec.write([cloud, custom], to: &writer)
    let document = try SimpleTOMLParser.parse(writer.output)
    let result = SnapzyConfigurationAutomationsCodec.parse(document)

    XCTAssertTrue(result.warnings.isEmpty, "\(result.warnings)")
    let imported = try XCTUnwrap(result.automations)
    XCTAssertEqual(imported.map(\.id), [cloud.id, custom.id])
    XCTAssertEqual(imported[0].hotkey, cloud.hotkey)
    XCTAssertEqual(imported[0].presetID, AutomationPreset.cloudShare.rawValue)
    XCTAssertEqual(imported[0].activeActions, [.copyImage, .uploadAndCopyLink(.markdown), .notify])
    XCTAssertEqual(imported[1].name, "Window \"docs\"")
    XCTAssertFalse(imported[1].isEnabled)
    XCTAssertTrue(imported[1].externalInvocation)
    XCTAssertEqual(imported[1].captureSpec, AutomationCaptureSpec(mode: .activeWindow, saveToExportDirectory: true))
  }

  func testMissingSectionLeavesAutomationsUntouched() throws {
    let document = try SimpleTOMLParser.parse("schema_version = 1\n")
    XCTAssertNil(SnapzyConfigurationAutomationsCodec.parse(document).automations)
  }

  func testInvalidEntriesWarnAndSkip() throws {
    let source = """
    [automations.first]
    order = 0
    name = "Bad capture"
    capture = "scrolling"
    steps = ["copy_image"]

    [automations.second]
    order = 1
    name = "Unknown step"
    capture = "area"
    steps = ["copy_image", "teleport"]
    shortcut_key = "4"
    shortcut_modifiers = []
    """
    let result = SnapzyConfigurationAutomationsCodec.parse(try SimpleTOMLParser.parse(source))
    let imported = try XCTUnwrap(result.automations)

    XCTAssertEqual(imported.map(\.name), ["Unknown step"])
    XCTAssertEqual(imported[0].activeActions, [.copyImage])
    XCTAssertNil(imported[0].hotkey, "A shortcut without modifiers is left unbound")
    XCTAssertEqual(result.warnings.count, 3)
  }

  func testDuplicateShortcutsAreUnbound() throws {
    let source = """
    [automations.a]
    order = 0
    capture = "area"
    steps = ["copy_image"]
    shortcut_key = "4"
    shortcut_modifiers = ["control", "shift"]

    [automations.b]
    order = 1
    capture = "fullscreen"
    steps = ["copy_image"]
    shortcut_key = "4"
    shortcut_modifiers = ["shift", "control"]
    """
    let result = SnapzyConfigurationAutomationsCodec.parse(try SimpleTOMLParser.parse(source))
    let imported = try XCTUnwrap(result.automations)

    XCTAssertNotNil(imported[0].hotkey)
    XCTAssertNil(imported[1].hotkey)
    XCTAssertEqual(result.warnings.count, 1)
  }

  func testDataFieldKeepsDisabledStepsAndPolicies() throws {
    var automation = AutomationPreset.cloudShare.makeAutomation()
    automation.steps[1].onFailure = .continue
    automation.steps.append(AutomationStep(.openAnnotate, isEnabled: false))

    var writer = SimpleTOMLWriter()
    SnapzyConfigurationAutomationsCodec.write([automation], to: &writer)
    let imported = try XCTUnwrap(SnapzyConfigurationAutomationsCodec.parse(try SimpleTOMLParser.parse(writer.output)).automations)

    XCTAssertEqual(imported.first?.steps, automation.normalized().steps)
  }

  func testEditedStepsInTOMLWinOverData() throws {
    let automation = AutomationPreset.cloudShare.makeAutomation()
    var writer = SimpleTOMLWriter()
    SnapzyConfigurationAutomationsCodec.write([automation], to: &writer)
    let edited = writer.output.replacingOccurrences(
      of: "steps = [\"copy_image\", \"upload_copy_link\", \"notify\"]",
      with: "steps = [\"copy_image\", \"show_quick_access\"]"
    )
    XCTAssertNotEqual(edited, writer.output)

    let imported = try XCTUnwrap(SnapzyConfigurationAutomationsCodec.parse(try SimpleTOMLParser.parse(edited)).automations)
    XCTAssertEqual(imported.first?.activeActions, [.copyImage, .showQuickAccess])
  }

  func testEmptyListRoundTripsAsEmpty() throws {
    var writer = SimpleTOMLWriter()
    SnapzyConfigurationAutomationsCodec.write([], to: &writer)
    let result = SnapzyConfigurationAutomationsCodec.parse(try SimpleTOMLParser.parse(writer.output))
    XCTAssertEqual(result.automations?.count, 0)
  }
}
