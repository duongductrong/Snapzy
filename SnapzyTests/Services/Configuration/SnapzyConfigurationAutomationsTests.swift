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
    cloud.steps[2].content = .action(.copyLink(AutomationLinkTemplate(style: .markdown)))
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
    XCTAssertEqual(
      imported[0].activeActions,
      [.copyImage, .upload(AutomationUploadConfig()), .copyLink(AutomationLinkTemplate(style: .markdown)), .notify]
    )
    XCTAssertEqual(imported[0].steps.map(\.id), cloud.steps.map(\.id), "Step ids survive the round trip")
    XCTAssertEqual(imported[1].name, "Window \"docs\"")
    XCTAssertFalse(imported[1].isEnabled)
    XCTAssertTrue(imported[1].externalInvocation)
    XCTAssertEqual(imported[1].captureSpec, AutomationCaptureSpec(mode: .activeWindow, saveToExportDirectory: true))
  }

  /// Milestone 6: a custom default after-capture pipeline survives a round trip
  /// as the default (preset id kept) and doesn't count against the cap.
  func testCustomDefaultAutomationRoundTripsAsSystemDefault() throws {
    var custom = AutomationSystemDefault.make(for: .screenshot, matrix: AutomationSystemDefault.defaultMatrix(for: .screenshot))
    custom.steps.append(AutomationStep(.notify))
    let users = (0..<AutomationStore.maxAutomations).map {
      Automation(name: "User \($0)", source: .input, steps: [AutomationStep(.copyFile)])
    }

    var writer = SimpleTOMLWriter()
    SnapzyConfigurationAutomationsCodec.write(users + [custom], to: &writer)
    let result = SnapzyConfigurationAutomationsCodec.parse(try SimpleTOMLParser.parse(writer.output), storedAutomation: { _ in nil })

    let imported = try XCTUnwrap(result.automations)
    XCTAssertTrue(result.warnings.isEmpty, "\(result.warnings)")
    XCTAssertEqual(imported.filter { !$0.isSystemDefault }.count, AutomationStore.maxAutomations)
    let system = try XCTUnwrap(imported.first(where: \.isSystemDefault))
    XCTAssertEqual(system.systemCaptureType, .screenshot)
    XCTAssertEqual(system.activeActions.map(\.kind), [.copyFile, .showQuickAccess, .notify])
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
    capture = "teleport"
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

  func testEditedStepTableWinsOverData() throws {
    let automation = AutomationPreset.docsShot.makeAutomation()
    var writer = SimpleTOMLWriter()
    SnapzyConfigurationAutomationsCodec.write([automation], to: &writer)
    XCTAssertTrue(writer.output.contains("max_dimension = 1600"))
    let edited = writer.output.replacingOccurrences(of: "max_dimension = 1600", with: "max_dimension = 800")

    let imported = try XCTUnwrap(SnapzyConfigurationAutomationsCodec.parse(try SimpleTOMLParser.parse(edited)).automations)
    XCTAssertEqual(imported.first?.steps[1].action, .resize(AutomationResizeConfig(mode: .maxDimension, maxDimension: 800)))
  }

  func testLegacyStepsArrayIsStillRead() throws {
    let source = """
    [automations.a]
    order = 0
    capture = "area"
    steps = ["copy_image", "upload_copy_link:markdown", "notify"]
    """
    let imported = try XCTUnwrap(SnapzyConfigurationAutomationsCodec.parse(try SimpleTOMLParser.parse(source)).automations)

    XCTAssertEqual(
      imported.first?.activeActions,
      [.copyImage, .upload(AutomationUploadConfig()), .copyLink(AutomationLinkTemplate(style: .markdown)), .notify]
    )
  }

  func testEmptyListRoundTripsAsEmpty() throws {
    var writer = SimpleTOMLWriter()
    SnapzyConfigurationAutomationsCodec.write([], to: &writer)
    let result = SnapzyConfigurationAutomationsCodec.parse(try SimpleTOMLParser.parse(writer.output))
    XCTAssertEqual(result.automations?.count, 0)
  }

  // MARK: - Milestone 2

  func testInputSourceAndListFlagsRoundTrip() throws {
    var automation = Automation(name: "On file", source: .input, steps: [AutomationStep(.copyImage)])
    automation.showsInHistory = true
    automation.externalInvocation = true

    var writer = SimpleTOMLWriter()
    SnapzyConfigurationAutomationsCodec.write([automation], to: &writer)
    XCTAssertTrue(writer.output.contains("capture = \"input\""))
    XCTAssertFalse(writer.output.contains("save_to_export"))
    let result = SnapzyConfigurationAutomationsCodec.parse(try SimpleTOMLParser.parse(writer.output))

    XCTAssertTrue(result.warnings.isEmpty, "\(result.warnings)")
    let imported = try XCTUnwrap(result.automations?.first)
    XCTAssertEqual(imported.source, .input)
    XCTAssertTrue(imported.showsInHistory)
    XCTAssertFalse(imported.showsInQuickAccess)
    XCTAssertTrue(imported.externalInvocation)
  }

  func testFlatListKeysWinOverData() throws {
    let automation = AutomationPreset.quickCopy.makeAutomation()
    var writer = SimpleTOMLWriter()
    SnapzyConfigurationAutomationsCodec.write([automation], to: &writer)
    let edited = writer.output
      .replacingOccurrences(of: "menu_bar = false", with: "menu_bar = true")
      .replacingOccurrences(of: "history = true", with: "history = false")

    let imported = try XCTUnwrap(
      SnapzyConfigurationAutomationsCodec.parse(try SimpleTOMLParser.parse(edited)).automations?.first
    )

    XCTAssertTrue(imported.showsInMenuBar)
    XCTAssertFalse(imported.showsInHistory)
    XCTAssertTrue(imported.showsInQuickAccess, "Absent edits keep the stored value")
  }

  // MARK: - Milestone 3

  private func makeFolderStore() -> AutomationFolderAccessStore {
    let defaults = UserDefaults(suiteName: "SnapzyConfigurationAutomationsTests.\(UUID().uuidString)")!
    return AutomationFolderAccessStore(defaults: defaults, exportDirectory: { nil })
  }

  func testStepTablesRoundTripEveryKind() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("toml-folder-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let folderStore = makeFolderStore()
    let folderID = folderStore.register(folder)

    var automation = Automation(
      name: "Everything",
      source: .capture(AutomationCaptureSpec(mode: .recordingWindow, saveToExportDirectory: false, recordingOutput: .gif)),
      steps: [
        AutomationStep(.convertToGIF(AutomationGIFConfig(fps: 24, maxWidth: 640)), onFailure: .continue),
        AutomationStep(.upload(AutomationUploadConfig())),
        AutomationStep(.copyLink(AutomationLinkTemplate(style: .custom, custom: "<{link}>"))),
        AutomationStep(.ocr(AutomationOCRConfig(languageIdentifier: "vi", includeQR: true)), isEnabled: false),
        AutomationStep(.translate(AutomationTranslateConfig(targetLanguage: "ja"))),
        AutomationStep(.copyText(AutomationTextTemplate(template: "> {text}"))),
        AutomationStep(.convert(AutomationConvertConfig(format: .jpeg, quality: 70, maxFileSizeKB: 500))),
        AutomationStep(.resize(AutomationResizeConfig(mode: .scalePercent, scalePercent: 25))),
        AutomationStep(.applyCanvasPreset(AutomationCanvasPresetConfig())),
        AutomationStep(.stripMetadata),
        AutomationStep(.saveToFolder(AutomationSaveToFolderConfig(
          folder: .bookmark(folderID),
          folderPath: folder.path,
          nameTemplate: "{date}-{appName}",
          conflict: .overwrite
        ))),
        AutomationStep(.saveToFolder(AutomationSaveToFolderConfig(folder: .exportDirectory))),
        AutomationStep(.reveal),
        AutomationStep(.pin),
        AutomationStep(.copyFile),
      ]
    )
    automation.steps.append(AutomationStep(.notify))
    var future = AutomationStep(.notify)
    future.content = .unsupported(.object(["kind": .string("teleport"), "url": .string("https://example.com")]))
    automation.steps.append(future)

    var writer = SimpleTOMLWriter()
    SnapzyConfigurationAutomationsCodec.write([automation], to: &writer)
    XCTAssertTrue(writer.output.contains(".steps.01]"))
    XCTAssertFalse(writer.output.contains("steps = ["), "v2 writes sub-tables only")

    // Drop `data` so only the step tables are read.
    let withoutData = writer.output
      .split(separator: "\n", omittingEmptySubsequences: false)
      .filter { !$0.hasPrefix("data = ") }
      .joined(separator: "\n")
    let result = SnapzyConfigurationAutomationsCodec.parse(try SimpleTOMLParser.parse(withoutData), folderStore: folderStore)

    XCTAssertTrue(result.warnings.isEmpty, "\(result.warnings)")
    let imported = try XCTUnwrap(result.automations?.first)
    XCTAssertEqual(imported.source, automation.source)
    XCTAssertEqual(imported.steps.map(\.action), automation.steps.map(\.action))
    XCTAssertEqual(imported.steps.map(\.isEnabled), automation.steps.map(\.isEnabled))
    XCTAssertEqual(imported.steps.map(\.onFailure), automation.steps.map(\.onFailure))
    XCTAssertEqual(imported.steps.last?.content, future.content, "Newer step kinds survive")
  }

  func testMissingFolderWarnsAndNeedsSetup() throws {
    let source = """
    [automations.a]
    order = 0
    capture = "active_window"

    [automations.a.steps.01]
    kind = "save_to_folder"
    folder = "/definitely/not/here"
    name = "{date}"
    """
    let result = SnapzyConfigurationAutomationsCodec.parse(try SimpleTOMLParser.parse(source), folderStore: makeFolderStore())
    let imported = try XCTUnwrap(result.automations?.first)

    XCTAssertEqual(result.warnings.count, 1)
    guard case .saveToFolder(let config)? = imported.steps.first?.action else { return XCTFail("Expected save_to_folder") }
    XCTAssertNil(config.folder)
    XCTAssertEqual(config.folderPath, "/definitely/not/here")
    XCTAssertTrue(imported.needsSetup)
  }

  func testUnknownStepKeysWarn() throws {
    let source = """
    [automations.a]
    order = 0
    capture = "area"

    [automations.a.steps.01]
    kind = "resize"
    max_dimension = 900
    colour = "red"
    """
    let result = SnapzyConfigurationAutomationsCodec.parse(try SimpleTOMLParser.parse(source))

    XCTAssertEqual(result.warnings.count, 1)
    XCTAssertEqual(result.automations?.first?.activeActions, [.resize(AutomationResizeConfig(maxDimension: 900))])
  }
}
