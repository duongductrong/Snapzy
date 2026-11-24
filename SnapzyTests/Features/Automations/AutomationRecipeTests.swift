//
//  AutomationRecipeTests.swift
//  SnapzyTests
//
//  Milestone 6 phase 05: `.snapzyautomation` export strip rules, import
//  preparation (new ids, re-pointed references, review / setup), limits.
//

import Carbon.HIToolbox
import XCTest
@testable import Snapzy

@MainActor
final class AutomationRecipeTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    suiteName = "AutomationRecipeTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    super.tearDown()
  }

  private func roundTrip(_ automations: [Automation], folderPath: @escaping (AutomationFolderRef) -> String? = { _ in nil }) throws -> [Automation] {
    let data = try AutomationRecipeCodec.encode(automations, folderPath: folderPath)
    return AutomationRecipeCodec.prepareForImport(try AutomationRecipeCodec.decode(data))
  }

  func testExportedDocsShotImportsWithChooseFolderSetupAndNoMachineState() throws {
    let bookmark = UUID()
    var docsShot = AutomationPreset.docsShot.makeAutomation()
    docsShot.isEnabled = true
    docsShot.hotkey = ShortcutConfig(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey | shiftKey))
    docsShot.externalInvocation = true
    docsShot.allowExternalCode = true
    let index = try XCTUnwrap(docsShot.steps.firstIndex { $0.action?.kind == .saveToFolder })
    docsShot.steps[index].content = .action(.saveToFolder(AutomationSaveToFolderConfig(folder: .bookmark(bookmark), nameTemplate: "{date}")))

    let data = try AutomationRecipeCodec.encode([docsShot], folderPath: { $0 == .bookmark(bookmark) ? "/Users/me/repo/docs/img" : nil })
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))
    XCTAssertTrue(json.contains("\"format\" : \"snapzy-automation\""))
    XCTAssertFalse(json.contains(bookmark.uuidString), "Bookmark ids stay on this Mac")
    XCTAssertFalse(json.contains("hotkey"), "Shortcuts are not shared")

    let imported = try XCTUnwrap(AutomationRecipeCodec.prepareForImport(try AutomationRecipeCodec.decode(data)).first)
    XCTAssertNotEqual(imported.id, docsShot.id)
    XCTAssertNil(imported.hotkey)
    XCTAssertFalse(imported.externalInvocation)
    XCTAssertFalse(imported.allowExternalCode)
    XCTAssertNil(imported.presetID)
    XCTAssertEqual(imported.name, "Docs Shot")
    guard case .saveToFolder(let config)? = imported.steps[index].action else { return XCTFail("Save step lost") }
    XCTAssertNil(config.folder)
    XCTAssertEqual(config.folderPath, "/Users/me/repo/docs/img")
    XCTAssertTrue(imported.needsSetup, "Shows Choose folder")
    XCTAssertTrue(Set(imported.steps.map(\.id)).isDisjoint(with: docsShot.steps.map(\.id)))
  }

  func testSecretValuesNeverLeakAndWebhookNeedsReview() throws {
    var webhook = AutomationWebhookConfig()
    webhook.url = "https://hooks.example.com/{secret:HOOK_PATH}"
    webhook.headers = [AutomationKeyValue(name: "Authorization", value: "Bearer {secret:TOKEN}")]
    let automation = Automation(name: "Hook", source: .input, steps: [AutomationStep(.webhook(webhook))])

    let data = try AutomationRecipeCodec.encode([automation])
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))
    XCTAssertTrue(json.contains("{secret:TOKEN}"))
    XCTAssertFalse(json.contains("needsReview"))

    let imported = try XCTUnwrap(AutomationRecipeCodec.prepareForImport(try AutomationRecipeCodec.decode(data)).first)
    XCTAssertTrue(imported.needsReview)
  }

  func testReferencesBetweenTheFilesAutomationsArePointedAtTheNewCopies() throws {
    let target = Automation(name: "Target", source: .input, steps: [AutomationStep(.copyFile)])
    let menu = Automation(
      name: "Menu",
      source: .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false)),
      steps: [AutomationStep(.ask(AutomationAskConfig(choices: [.automation(target.id), .continueRun])))]
    )

    let imported = try roundTrip([target, menu])

    let newTarget = try XCTUnwrap(imported.first { $0.name == "Target" })
    let newMenu = try XCTUnwrap(imported.first { $0.name == "Menu" })
    XCTAssertNotEqual(newTarget.id, target.id)
    XCTAssertEqual(newMenu.steps.first?.action?.referencedAutomationIDs, [newTarget.id])
  }

  func testSystemDefaultsAreNeitherExportedNorImported() throws {
    let system = AutomationSystemDefault.make(for: .screenshot, matrix: AutomationSystemDefault.defaultMatrix(for: .screenshot))
    let user = Automation(name: "Mine", source: .input, steps: [AutomationStep(.copyFile)])

    let imported = try roundTrip([system, user])

    XCTAssertEqual(imported.map(\.name), ["Mine"])
  }

  func testDecodeRejectsForeignNewerAndEmptyFiles() {
    XCTAssertThrowsError(try AutomationRecipeCodec.decode(Data(#"{"hello":1}"#.utf8))) {
      XCTAssertEqual($0 as? AutomationRecipeError, .notARecipe)
    }
    XCTAssertThrowsError(try AutomationRecipeCodec.decode(Data(#"{"format":"snapzy-automation","version":9,"automations":[]}"#.utf8))) {
      XCTAssertEqual($0 as? AutomationRecipeError, .unsupportedVersion(9))
    }
    XCTAssertThrowsError(try AutomationRecipeCodec.decode(Data(#"{"format":"snapzy-automation","version":1,"automations":[{"bad":true}]}"#.utf8))) {
      XCTAssertEqual($0 as? AutomationRecipeError, .empty)
    }
  }

  func testDownloadRefusesPlainHTTP() async {
    do {
      _ = try await AutomationRecipeCodec.download(URL(string: "http://example.com/a.snapzyautomation")!)
      XCTFail("Expected an error")
    } catch {
      XCTAssertEqual(error as? AutomationRecipeError, .insecureURL)
    }
  }

  func testImportDeepLinkNeedsHTTPS() {
    XCTAssertEqual(
      SnapzyDeepLinkAction(url: URL(string: "snapzy://automation/import?url=https%3A%2F%2Fexample.com%2Fr.snapzyautomation")!),
      .importAutomation(URL(string: "https://example.com/r.snapzyautomation")!)
    )
    XCTAssertNil(SnapzyDeepLinkAction(url: URL(string: "snapzy://automation/import?url=http%3A%2F%2Fexample.com%2Fr")!))
    XCTAssertNil(SnapzyDeepLinkAction(url: URL(string: "snapzy://automation/import")!))
  }

  func testImportSelectedAddsOnlySelectedAndTurnsOffWhatNeedsSetup() throws {
    let store = AutomationStore(defaults: defaults)
    let before = store.automations.count
    let ready = Automation(name: "Ready", source: .input, steps: [AutomationStep(.copyFile)])
    let needsFolder = Automation(name: "Folder", source: .input, steps: [AutomationStep(.saveToFolder(AutomationSaveToFolderConfig()))])
    let skipped = Automation(name: "Skipped", source: .input, steps: [AutomationStep(.copyFile)])
    let request = AutomationImportRequest(origin: .file("x.snapzyautomation"), candidates: [
      AutomationImportCandidate(automation: ready),
      AutomationImportCandidate(automation: needsFolder),
      AutomationImportCandidate(automation: skipped, isSelected: false),
    ])

    let added = AutomationImportCoordinator.shared.importSelected(request, into: store)

    XCTAssertEqual(added, 2)
    XCTAssertEqual(store.automations.count, before + 2)
    XCTAssertEqual(store.automations.first { $0.name == "Ready" }?.isEnabled, true)
    XCTAssertEqual(store.automations.first { $0.name == "Folder" }?.isEnabled, false)
    XCTAssertFalse(store.automations.contains { $0.name == "Skipped" })
  }

  func testGalleryCoversEveryPresetOnce() {
    let listed = AutomationRecipePersona.allCases.flatMap(\.presets)
    XCTAssertEqual(Set(listed), Set(AutomationPreset.allCases))
    XCTAssertEqual(listed.count, AutomationPreset.allCases.count)
    for preset in AutomationPreset.allCases {
      XCTAssertFalse(preset.galleryDescription.isEmpty)
    }
  }
}
