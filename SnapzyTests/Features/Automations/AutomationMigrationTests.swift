//
//  AutomationMigrationTests.swift
//  SnapzyTests
//
//  Milestone 1/2 JSON loads into schema 2 unchanged in behavior; every M3
//  step config round-trips; configs decode tolerantly.
//

import XCTest
@testable import Snapzy

@MainActor
final class AutomationMigrationTests: XCTestCase {
  /// A Cloud Share automation exactly as milestone 1 stored it.
  private let m1CloudShare = """
  {
    "id": "6B1E8A40-2C4B-4C59-9A0E-1A2B3C4D5E6F",
    "name": "Cloud Share",
    "symbol": "link",
    "isEnabled": true,
    "triggers": [{"kind": "quickAccessAction"}],
    "source": {"kind": "capture", "mode": "area", "saveToExportDirectory": false},
    "steps": [
      {"id": "11111111-1111-1111-1111-111111111111", "kind": "copyImage", "isEnabled": true, "onFailure": "stop"},
      {"id": "22222222-2222-2222-2222-222222222222", "kind": "uploadAndCopyLink", "format": "markdown", "isEnabled": true, "onFailure": "continue"},
      {"id": "33333333-3333-3333-3333-333333333333", "kind": "notify", "isEnabled": false, "onFailure": "stop"}
    ],
    "externalInvocation": false,
    "presetID": "cloud-share",
    "schemaVersion": 1
  }
  """

  func testM1UploadAndCopyLinkMigratesToUploadPlusCopyLink() throws {
    let automation = try JSONDecoder().decode(Automation.self, from: Data(m1CloudShare.utf8))

    XCTAssertEqual(automation.schemaVersion, 2)
    XCTAssertEqual(automation.steps.map(\.action), [
      .copyImage,
      .upload,
      .copyLink(AutomationLinkTemplate(style: .markdown)),
      .notify,
    ])
    let upload = automation.steps[1]
    let copyLink = automation.steps[2]
    XCTAssertEqual(upload.id, UUID(uuidString: "22222222-2222-2222-2222-222222222222"), "Upload keeps the step id")
    XCTAssertNotEqual(copyLink.id, upload.id)
    XCTAssertEqual(copyLink.onFailure, .continue, "Policy is copied to both halves")
    XCTAssertTrue(copyLink.isEnabled)
    XCTAssertFalse(automation.steps[3].isEnabled)
  }

  func testMigrationIsStableAcrossLoads() throws {
    let first = try JSONDecoder().decode(Automation.self, from: Data(m1CloudShare.utf8))
    let second = try JSONDecoder().decode(Automation.self, from: Data(m1CloudShare.utf8))
    XCTAssertEqual(first, second, "Derived ids are deterministic")
  }

  func testEncodeNeverWritesLegacyKind() throws {
    var automation = AutomationPreset.quickCopy.makeAutomation()
    automation.steps = [AutomationStep(.uploadAndCopyLink(.url))]
    let json = String(data: try JSONEncoder().encode(automation), encoding: .utf8) ?? ""

    XCTAssertFalse(json.contains("uploadAndCopyLink"))
    XCTAssertTrue(json.contains("\"upload\""))
    XCTAssertTrue(json.contains("\"copyLink\""))
  }

  func testEveryStepConfigRoundTrips() throws {
    let folder = AutomationFolderRef.bookmark(UUID())
    let actions: [AutomationStepAction] = [
      .applyCanvasPreset(AutomationCanvasPresetConfig(presetID: UUID())),
      .resize(AutomationResizeConfig(mode: .scalePercent, maxDimension: 800, scalePercent: 25)),
      .convert(AutomationConvertConfig(format: .jpeg, quality: 70, maxFileSizeKB: 500, optimizePresetID: UUID())),
      .stripMetadata,
      .ocr(AutomationOCRConfig(languageIdentifier: "vi", includeQR: true)),
      .translate(AutomationTranslateConfig(targetLanguage: "ja")),
      .convertToGIF(AutomationGIFConfig(fps: 24, maxWidth: 640)),
      .upload,
      .copyLink(AutomationLinkTemplate(style: .custom, custom: "<{link}>")),
      .copyText(AutomationTextTemplate(template: "> {text}")),
      .copyFile,
      .saveToFolder(AutomationSaveToFolderConfig(folder: folder, folderPath: "/tmp/x", nameTemplate: "{date}", conflict: .overwrite)),
      .saveToFolder(AutomationSaveToFolderConfig(folder: .exportDirectory)),
      .reveal,
      .pin,
    ]
    var automation = AutomationPreset.quickCopy.makeAutomation()
    automation.steps = actions.map { AutomationStep($0) }
    let decoded = try JSONDecoder().decode(Automation.self, from: JSONEncoder().encode(automation))

    XCTAssertEqual(decoded.steps.map(\.action), actions)
  }

  func testConfigsDecodeTolerantly() throws {
    let json = """
    {"id": "11111111-1111-1111-1111-111111111111", "kind": "resize", "config": {"maxDimension": "big", "mode": "maxDimension"}}
    """
    let step = try JSONDecoder().decode(AutomationStep.self, from: Data(json.utf8))
    XCTAssertEqual(step.action, .resize(AutomationResizeConfig(mode: .maxDimension, maxDimension: 1600)))

    let missingConfig = """
    {"id": "11111111-1111-1111-1111-111111111111", "kind": "convert"}
    """
    let convert = try JSONDecoder().decode(AutomationStep.self, from: Data(missingConfig.utf8))
    XCTAssertEqual(convert.action, .convert(AutomationConvertConfig()))
  }

  func testNewSourcesRoundTrip() throws {
    var automation = AutomationPreset.gifShare.makeAutomation()
    XCTAssertEqual(try roundTrip(automation).source, automation.source)

    automation.source = .clipboardImage
    XCTAssertEqual(try roundTrip(automation).source, .clipboardImage)
    XCTAssertTrue(automation.runsWithoutInput)
    XCTAssertFalse(automation.startsCapture)

    automation.source = .capture(AutomationCaptureSpec(mode: .scrolling, saveToExportDirectory: true))
    XCTAssertEqual(try roundTrip(automation).source, automation.source)
  }

  func testClipboardSourceKeepsHotkeyAndMenuBar() {
    var automation = AutomationPreset.quickCopy.makeAutomation()
    automation.source = .clipboardImage
    automation.hotkey = ShortcutConfig(keyCode: 1, modifiers: 256)
    automation.showsInMenuBar = true

    let normalized = automation.normalized()

    XCTAssertNotNil(normalized.hotkey)
    XCTAssertTrue(normalized.showsInMenuBar)
  }

  private func roundTrip(_ automation: Automation) throws -> Automation {
    try JSONDecoder().decode(Automation.self, from: JSONEncoder().encode(automation))
  }
}
