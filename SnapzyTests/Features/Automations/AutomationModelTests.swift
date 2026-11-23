//
//  AutomationModelTests.swift
//  SnapzyTests
//
//  Coding, forward compatibility and normalization of the automation model.
//

import Carbon.HIToolbox
import XCTest
@testable import Snapzy

@MainActor
final class AutomationModelTests: XCTestCase {
  private func roundTrip(_ automation: Automation) throws -> Automation {
    let data = try JSONEncoder().encode(automation)
    return try JSONDecoder().decode(Automation.self, from: data)
  }

  func testRoundTripKeepsEveryField() throws {
    var automation = AutomationPreset.cloudShare.makeAutomation()
    automation.hotkey = ShortcutConfig(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(controlKey | shiftKey))
    automation.steps[1].onFailure = .continue
    automation.steps[2].content = .action(.copyLink(AutomationLinkTemplate(style: .markdown)))

    XCTAssertEqual(try roundTrip(automation), automation)
  }

  func testUnknownPartsSurviveRoundTrip() throws {
    let json = """
    {
      "id": "6B1E8A40-2C4B-4C59-9A0E-1A2B3C4D5E6F",
      "name": "Future",
      "isEnabled": true,
      "triggers": [{"kind": "menuBar"}, {"kind": "hotkey", "shortcut": {"keyCode": 21, "modifiers": 4608}}],
      "source": {"kind": "capture", "mode": "area", "saveToExportDirectory": true},
      "steps": [
        {"id": "11111111-1111-1111-1111-111111111111", "kind": "copyImage", "isEnabled": true, "onFailure": "stop"},
        {"id": "22222222-2222-2222-2222-222222222222", "kind": "webhook", "url": "https://example.com/hook", "isEnabled": true}
      ],
      "externalInvocation": false,
      "schemaVersion": 2
    }
    """
    let automation = try JSONDecoder().decode(Automation.self, from: Data(json.utf8))

    XCTAssertEqual(automation.steps.count, 2)
    XCTAssertEqual(automation.activeActions, [.copyImage])
    guard case .unsupported(let raw) = automation.steps[1].content else {
      return XCTFail("Unknown step kind must be kept as unsupported")
    }
    XCTAssertEqual(raw.kind, "webhook")
    XCTAssertEqual(automation.hotkey, ShortcutConfig(keyCode: 21, modifiers: 4608))
    XCTAssertEqual(automation.triggers.count, 2)

    let reencoded = try roundTrip(automation)
    XCTAssertEqual(reencoded, automation)
  }

  func testUnknownSourceIsKeptAndMarkedUnsupported() throws {
    let json = """
    {"id": "6B1E8A40-2C4B-4C59-9A0E-1A2B3C4D5E6F", "name": "Rec", "source": {"kind": "recording", "fps": 60}, "steps": []}
    """
    let automation = try JSONDecoder().decode(Automation.self, from: Data(json.utf8))

    XCTAssertTrue(automation.hasUnsupportedSource)
    XCTAssertEqual(try roundTrip(automation).source, automation.source)
  }

  func testNormalizedKeepsOrderAndDuplicatesAndMigratesLegacyUpload() {
    let automation = Automation(
      name: "  ",
      source: .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false)),
      steps: [
        AutomationStep(.uploadAndCopyLink(.url)),
        AutomationStep(.notify),
        AutomationStep(.copyImage),
        AutomationStep(.notify),
      ]
    ).normalized()

    XCTAssertEqual(
      automation.activeActions,
      [.upload, .copyLink(AutomationLinkTemplate(style: .url)), .notify, .copyImage, .notify]
    )
    XCTAssertEqual(automation.schemaVersion, Automation.currentSchemaVersion)
    XCTAssertEqual(automation.name, L10n.Automations.defaultName)
  }

  func testNormalizedCapsStepCount() {
    let automation = Automation(
      name: "Many",
      source: .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false)),
      steps: (0..<30).map { _ in AutomationStep(.notify) }
    ).normalized()

    XCTAssertEqual(automation.steps.count, Automation.maxSteps)
  }

  func testNormalizedAddsCopyImageWhenNoStep() {
    let automation = Automation(
      name: "Empty",
      source: .capture(AutomationCaptureSpec(mode: .fullscreen, saveToExportDirectory: true)),
      steps: []
    ).normalized()

    XCTAssertEqual(automation.activeActions, [.copyImage])
  }

  func testNormalizedTruncatesLongNamesAndKeepsOneHotkey() {
    var automation = Automation(
      name: String(repeating: "a", count: 100),
      source: .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false)),
      steps: [AutomationStep(.copyImage)]
    )
    automation.triggers = [
      .hotkey(ShortcutConfig(keyCode: 1, modifiers: UInt32(cmdKey))),
      .hotkey(ShortcutConfig(keyCode: 2, modifiers: UInt32(cmdKey))),
    ]

    let normalized = automation.normalized()

    XCTAssertEqual(normalized.name.count, Automation.maxNameLength)
    XCTAssertEqual(normalized.triggers.count, 1)
    XCTAssertEqual(normalized.hotkey?.keyCode, 1)
  }

  func testHotkeySetterReplacesAndClears() {
    var automation = AutomationPreset.quickCopy.makeAutomation()
    XCTAssertNil(automation.hotkey)

    automation.hotkey = ShortcutConfig(keyCode: 1, modifiers: UInt32(cmdKey))
    automation.hotkey = ShortcutConfig(keyCode: 2, modifiers: UInt32(cmdKey))
    XCTAssertEqual(automation.triggers.filter { if case .hotkey = $0 { true } else { false } }.count, 1)
    XCTAssertEqual(automation.hotkey?.keyCode, 2)

    automation.hotkey = nil
    XCTAssertEqual(automation.triggers, [.quickAccessAction, .historyAction], "Other triggers are kept")
  }

  func testPresetDisplayNameFollowsLanguageUntilRenamed() {
    var automation = AutomationPreset.quickCopy.makeAutomation()
    XCTAssertEqual(automation.displayName, AutomationPreset.quickCopy.localizedName)

    automation.name = "My copy"
    XCTAssertEqual(automation.displayName, "My copy")
  }

  func testPresetsShipWithoutShortcuts() {
    for preset in AutomationPreset.allCases {
      let automation = preset.makeAutomation()
      XCTAssertNil(automation.hotkey)
      XCTAssertEqual(automation.presetID, preset.rawValue)
      XCTAssertTrue(automation.startsCapture)
      XCTAssertEqual(automation.activeActions.last, .notify)
    }
    XCTAssertEqual(AutomationPreset.quickCopy.makeAutomation().activeActions.first, .copyImage)
  }

  // MARK: - Milestone 2

  func testInputSourceAndListTriggersRoundTrip() throws {
    var automation = Automation(name: "On file", source: .input, steps: [AutomationStep(.copyImage)])
    automation.showsInQuickAccess = true
    automation.showsInHistory = true

    let decoded = try roundTrip(automation)

    XCTAssertEqual(decoded, automation)
    XCTAssertEqual(decoded.source, .input)
    XCTAssertFalse(decoded.hasUnsupportedSource)
    XCTAssertFalse(decoded.startsCapture)
    XCTAssertTrue(decoded.showsInQuickAccess)
    XCTAssertTrue(decoded.showsInHistory)
    XCTAssertFalse(decoded.showsInMenuBar)
  }

  func testNormalizedDropsHotkeyAndMenuBarForInputSource() {
    var automation = Automation(name: "On file", source: .input, steps: [AutomationStep(.copyImage)])
    automation.hotkey = ShortcutConfig(keyCode: 1, modifiers: UInt32(cmdKey))
    automation.showsInMenuBar = true
    automation.showsInHistory = true
    automation.triggers.append(.historyAction)

    let normalized = automation.normalized()

    XCTAssertNil(normalized.hotkey)
    XCTAssertFalse(normalized.showsInMenuBar)
    XCTAssertEqual(normalized.triggers, [.historyAction], "Duplicate list triggers collapse")
  }

  func testNewPresetsAreOfferedOnQuickAccessAndHistory() {
    for preset in AutomationPreset.allCases {
      let automation = preset.makeAutomation()
      XCTAssertTrue(automation.showsInQuickAccess)
      XCTAssertTrue(automation.showsInHistory)
      XCTAssertFalse(automation.showsInMenuBar)
      XCTAssertFalse(automation.externalInvocation, "Other apps stay opt-in")
    }
  }

  func testFileKindsAndStepAcceptance() {
    XCTAssertEqual(AutomationFileKind.of(URL(fileURLWithPath: "/a/b.PNG")), .image)
    XCTAssertEqual(AutomationFileKind.of(URL(fileURLWithPath: "/a/b.gif")), .gif)
    XCTAssertEqual(AutomationFileKind.of(URL(fileURLWithPath: "/a/b.mov")), .video)
    XCTAssertEqual(AutomationFileKind.of(URL(fileURLWithPath: "/a/b.mp4")), .video)
    XCTAssertNil(AutomationFileKind.of(URL(fileURLWithPath: "/a/b.txt")))

    let annotateOnly = Automation(name: "A", source: .input, steps: [AutomationStep(.openAnnotate)])
    XCTAssertTrue(annotateOnly.acceptsFile(of: .image))
    XCTAssertFalse(annotateOnly.acceptsFile(of: .video))
    XCTAssertFalse(annotateOnly.acceptsFile(of: .gif))
  }

  func testAutomationRefParsesUUIDOrName() {
    let id = UUID()
    XCTAssertEqual(AutomationRef(" \(id.uuidString) "), .id(id))
    XCTAssertEqual(AutomationRef("  Cloud Share "), .name("Cloud Share"))
  }
}
