//
//  CaptureToolbarTests.swift
//  SnapzyTests
//
//  Milestone 6 phase 03 (#498): toolbar configuration, accelerators, item
//  resolution, key handling, positioning and the built-in pipelines.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class CaptureToolbarTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    suiteName = "CaptureToolbarTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    super.tearDown()
  }

  // MARK: - Configuration

  func testDefaultHasEveryBuiltinWithUniqueKeysAndCopyOnDoubleClick() {
    let config = CaptureToolbarConfiguration.default
    XCTAssertEqual(config.entries.map(\.item), CaptureToolbarBuiltin.allCases.map { .builtin($0) })
    let keys = config.entries.compactMap(\.accelerator)
    XCTAssertEqual(keys.count, Set(keys).count)
    XCTAssertEqual(config.entries.first { $0.item == .builtin(.record) }?.accelerator, "R")
    XCTAssertEqual(config.entries.first { $0.item == .builtin(.copy) }?.accelerator, "C")
    XCTAssertEqual(config.doubleClickAction, .builtin(.copy))
    XCTAssertFalse(config.showsForAreaShortcut)
  }

  func testNormalizationRestoresMissingBuiltinsAndClearsDuplicateKeys() {
    var config = CaptureToolbarConfiguration.default
    config.entries = [
      CaptureToolbarEntry(item: .builtin(.record), accelerator: "r"),
      CaptureToolbarEntry(item: .builtin(.copy), accelerator: "R"),
      CaptureToolbarEntry(item: .builtin(.record)),
    ]

    let normalized = config.normalized()

    XCTAssertEqual(normalized.entries.count, CaptureToolbarBuiltin.allCases.count)
    XCTAssertEqual(normalized.entries[0].accelerator, "R")
    XCTAssertNil(normalized.entries[1].accelerator, "A later duplicate loses the key")
  }

  func testAcceleratorAcceptsOneLetterOrDigitOnly() {
    XCTAssertEqual(CaptureToolbarEntry.normalizedAccelerator("c"), "C")
    XCTAssertEqual(CaptureToolbarEntry.normalizedAccelerator("7"), "7")
    XCTAssertNil(CaptureToolbarEntry.normalizedAccelerator("cc"))
    XCTAssertNil(CaptureToolbarEntry.normalizedAccelerator("-"))
    XCTAssertNil(CaptureToolbarEntry.normalizedAccelerator("é"))
    XCTAssertNil(CaptureToolbarEntry.normalizedAccelerator(nil))
  }

  func testVisibleEntriesAppendToolbarAutomationsWithFreeDigits() {
    var config = CaptureToolbarConfiguration.default
    config.entries[config.entries.firstIndex { $0.item == .builtin(.pin) }!].isVisible = false
    config.entries[0].accelerator = "1"
    let first = UUID()
    let second = UUID()
    let hidden = UUID()
    config.automationEntries = [CaptureToolbarEntry(item: .automation(hidden), isVisible: false)]

    let visible = config.normalized().visibleEntries(available: [first, hidden, second])

    XCTAssertFalse(visible.contains { $0.item == .builtin(.pin) })
    XCTAssertFalse(visible.contains { $0.item == .automation(hidden) })
    let automations = visible.filter { if case .automation = $0.item { true } else { false } }
    XCTAssertEqual(automations.map(\.item), [.automation(first), .automation(second)])
    XCTAssertEqual(automations.map(\.accelerator), ["2", "3"], "1 is taken by Screenshot")
  }

  func testVisibleEntriesDropAutomationsNoLongerOffered() {
    var config = CaptureToolbarConfiguration.default
    let gone = UUID()
    config.automationEntries = [CaptureToolbarEntry(item: .automation(gone), accelerator: "9")]
    XCTAssertFalse(config.visibleEntries(available: []).contains { $0.item == .automation(gone) })
  }

  func testConfigurationPersists() {
    let store = CaptureToolbarConfigurationStore(defaults: defaults)
    var config = store.configuration
    config.showsForAreaShortcut = true
    config.doubleClickAction = .builtin(.upload)
    store.update(config)

    let reloaded = CaptureToolbarConfigurationStore(defaults: defaults)
    XCTAssertTrue(reloaded.configuration.showsForAreaShortcut)
    XCTAssertEqual(reloaded.configuration.doubleClickAction, .builtin(.upload))
  }

  func testTOMLRoundTrip() {
    var config = CaptureToolbarConfiguration.default
    let automationID = UUID()
    config.entries.swapAt(0, 1)
    config.entries[2].isVisible = false
    config.automationEntries = [CaptureToolbarEntry(item: .automation(automationID), accelerator: "4")]
    config.doubleClickAction = nil
    config.showsForAreaShortcut = true
    config = config.normalized()
    var warnings: [String] = []

    let parsed = CaptureToolbarConfiguration.fromTOML(
      buttons: config.tomlButtons,
      hidden: config.tomlHidden,
      doubleClick: "none",
      showsForArea: true,
      base: .default,
      warnings: &warnings
    )

    XCTAssertEqual(parsed, config)
    XCTAssertTrue(warnings.isEmpty, "\(warnings)")

    _ = CaptureToolbarConfiguration.fromTOML(
      buttons: ["teleport"], hidden: nil, doubleClick: "dance", showsForArea: nil, base: .default, warnings: &warnings
    )
    XCTAssertEqual(warnings.count, 2)
  }

  // MARK: - Keys

  func testKeyResolver() {
    let entries = CaptureToolbarConfiguration.default.visibleEntries(available: [])

    XCTAssertEqual(CaptureToolbarKeyResolver.resolve(keyCode: 15, characters: "r", hasCommandModifiers: false, entries: entries), .perform(.builtin(.record)))
    XCTAssertEqual(CaptureToolbarKeyResolver.resolve(keyCode: 8, characters: "c", hasCommandModifiers: false, entries: entries), .perform(.builtin(.copy)))
    XCTAssertEqual(CaptureToolbarKeyResolver.resolve(keyCode: 36, characters: "\r", hasCommandModifiers: false, entries: entries), .perform(.builtin(.screenshot)))
    XCTAssertEqual(CaptureToolbarKeyResolver.resolve(keyCode: 53, characters: nil, hasCommandModifiers: false, entries: entries), .cancel)
    XCTAssertEqual(CaptureToolbarKeyResolver.resolve(keyCode: 8, characters: "c", hasCommandModifiers: true, entries: entries), .ignored, "⌘C is not the accelerator")
    XCTAssertEqual(CaptureToolbarKeyResolver.resolve(keyCode: 6, characters: "z", hasCommandModifiers: false, entries: entries), .ignored)
  }

  // MARK: - Positioning

  func testToolbarSitsUnderTheSelectionAndFlipsAboveAtTheBottomEdge() throws {
    let screen = try XCTUnwrap(NSScreen.main)
    let visible = screen.visibleFrame
    let size = NSSize(width: 400, height: 44)

    let middle = CGRect(x: visible.midX - 100, y: visible.midY - 100, width: 200, height: 200)
    let under = CaptureToolbarController.toolbarFrame(size: size, selection: middle, screen: screen)
    XCTAssertLessThan(under.maxY, middle.minY)
    XCTAssertEqual(under.midX, middle.midX, accuracy: 1)

    let bottom = CGRect(x: visible.midX - 100, y: visible.minY + 2, width: 200, height: 100)
    let above = CaptureToolbarController.toolbarFrame(size: size, selection: bottom, screen: screen)
    XCTAssertGreaterThan(above.minY, bottom.maxY)

    let edge = CGRect(x: visible.minX, y: visible.midY, width: 50, height: 50)
    let clamped = CaptureToolbarController.toolbarFrame(size: size, selection: edge, screen: screen)
    XCTAssertGreaterThanOrEqual(clamped.minX, visible.minX)
  }

  // MARK: - Built-ins are automation steps

  func testStillImageBuiltinsRunAutomationSteps() {
    XCTAssertEqual(CaptureToolbarController.pipeline(for: .copy).activeActions, [.copyImage])
    XCTAssertEqual(
      CaptureToolbarController.pipeline(for: .upload).activeActions.map(\.kind),
      [.upload, .copyLink, .notify]
    )
    XCTAssertEqual(CaptureToolbarController.pipeline(for: .ocr).activeActions.map(\.kind), [.ocr, .copyText, .notify])
    for builtin in CaptureToolbarBuiltin.allCases where !builtin.startsNewCapture && builtin != .screenshot {
      let pipeline = CaptureToolbarController.pipeline(for: builtin)
      XCTAssertTrue(AutomationChainValidator.blockingIssues(pipeline).isEmpty, "\(builtin)")
    }
  }

  func testCaptureToolbarTriggerRoundTrips() throws {
    var automation = Automation(name: "Docs", source: .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false)), steps: [AutomationStep(.copyImage)])
    automation.showsInCaptureToolbar = true
    let decoded = try JSONDecoder().decode(Automation.self, from: JSONEncoder().encode(automation))
    XCTAssertTrue(decoded.showsInCaptureToolbar)
    XCTAssertTrue(decoded.normalized().showsInCaptureToolbar)
  }

  func testDeepLinkAndShortcutKind() {
    XCTAssertEqual(SnapzyDeepLinkAction(url: URL(string: "snapzy://capture/toolbar")!), .captureWithToolbar)
    XCTAssertFalse(GlobalShortcutKind.unifiedCapture.displayName.isEmpty)
  }
}
