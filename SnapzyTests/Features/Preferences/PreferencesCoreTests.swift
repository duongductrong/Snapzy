//
//  PreferencesCoreTests.swift
//  SnapzyTests
//
//  Unit tests for persisted preferences value models.
//

import XCTest
@testable import Snapzy

final class PreferencesCoreTests: XCTestCase {

  func testCloudUploadFloatingPositionStored_readsValidValueAndFallsBackToDefault() throws {
    let defaults = try makeDefaults()
    XCTAssertEqual(CloudUploadFloatingPosition.stored(userDefaults: defaults), .center)

    defaults.set(CloudUploadFloatingPosition.top.rawValue, forKey: PreferencesKeys.cloudUploadsFloatingPosition)
    XCTAssertEqual(CloudUploadFloatingPosition.stored(userDefaults: defaults), .top)

    defaults.set("invalid", forKey: PreferencesKeys.cloudUploadsFloatingPosition)
    XCTAssertEqual(CloudUploadFloatingPosition.stored(userDefaults: defaults), .center)
  }

  func testHistoryBackgroundStyleStored_readsValidValueAndFallsBackToDefault() throws {
    let defaults = try makeDefaults()
    XCTAssertEqual(HistoryBackgroundStyle.currentStoredStyle(userDefaults: defaults), .hud)

    defaults.set(HistoryBackgroundStyle.solid.rawValue, forKey: PreferencesKeys.historyBackgroundStyle)
    XCTAssertEqual(HistoryBackgroundStyle.currentStoredStyle(userDefaults: defaults), .solid)

    defaults.set("invalid", forKey: PreferencesKeys.historyBackgroundStyle)
    XCTAssertEqual(HistoryBackgroundStyle.currentStoredStyle(userDefaults: defaults), .hud)
  }

  func testAnnotateClipboardImageBehaviorStored_readsValidValueAndFallsBackToAsk() throws {
    let defaults = try makeDefaults()
    XCTAssertEqual(AnnotateClipboardImageBehavior.stored(userDefaults: defaults), .ask)

    defaults.set(
      AnnotateClipboardImageBehavior.loadAutomatically.rawValue,
      forKey: PreferencesKeys.annotateClipboardImageOpenBehavior
    )
    XCTAssertEqual(AnnotateClipboardImageBehavior.stored(userDefaults: defaults), .loadAutomatically)

    defaults.set("invalid", forKey: PreferencesKeys.annotateClipboardImageOpenBehavior)
    XCTAssertEqual(AnnotateClipboardImageBehavior.stored(userDefaults: defaults), .ask)
  }

  func testAnnotateQuickPropertiesSyncPreference_defaultsToEnabled() throws {
    let defaults = try makeDefaults()
    XCTAssertTrue(AnnotateQuickPropertiesSyncPreference.isEnabled(userDefaults: defaults))

    defaults.set(false, forKey: PreferencesKeys.annotateQuickPropertiesSyncEnabled)
    XCTAssertFalse(AnnotateQuickPropertiesSyncPreference.isEnabled(userDefaults: defaults))

    defaults.set(true, forKey: PreferencesKeys.annotateQuickPropertiesSyncEnabled)
    XCTAssertTrue(AnnotateQuickPropertiesSyncPreference.isEnabled(userDefaults: defaults))
  }

  func testAnnotateToolPreference_usesDefaultAndOptionalLastTool() throws {
    let defaults = try makeDefaults()
    XCTAssertEqual(AnnotateToolPreference.defaultTool(userDefaults: defaults), .selection)
    XCTAssertEqual(AnnotateToolPreference.initialTool(userDefaults: defaults), .selection)

    defaults.set(AnnotationToolType.arrow.rawValue, forKey: PreferencesKeys.annotateDefaultTool)
    XCTAssertEqual(AnnotateToolPreference.initialTool(userDefaults: defaults), .arrow)

    defaults.set(true, forKey: PreferencesKeys.annotateRememberLastTool)
    XCTAssertEqual(AnnotateToolPreference.initialTool(userDefaults: defaults), .arrow)

    AnnotateToolPreference.remember(.text, userDefaults: defaults)
    XCTAssertEqual(AnnotateToolPreference.initialTool(userDefaults: defaults), .text)
  }

  func testAnnotateToolPreference_rejectsUnsupportedAndInvalidValues() throws {
    let defaults = try makeDefaults()
    defaults.set(AnnotationToolType.crop.rawValue, forKey: PreferencesKeys.annotateDefaultTool)
    XCTAssertEqual(AnnotateToolPreference.defaultTool(userDefaults: defaults), .selection)

    defaults.set(AnnotationToolType.arrow.rawValue, forKey: PreferencesKeys.annotateDefaultTool)
    defaults.set(true, forKey: PreferencesKeys.annotateRememberLastTool)
    defaults.set("invalid", forKey: PreferencesKeys.annotateLastUsedTool)
    XCTAssertEqual(AnnotateToolPreference.initialTool(userDefaults: defaults), .arrow)

    AnnotateToolPreference.remember(.crop, userDefaults: defaults)
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.annotateLastUsedTool), "invalid")
  }

  func testCombineSaveAsEditPreference_defaultsToEnabled() throws {
    let defaults = try makeDefaults()
    XCTAssertTrue(CombineSaveAsEditPreference.isEnabled(userDefaults: defaults))

    defaults.set(false, forKey: PreferencesKeys.annotateCombineSaveAsEdit)
    XCTAssertFalse(CombineSaveAsEditPreference.isEnabled(userDefaults: defaults))

    defaults.set(true, forKey: PreferencesKeys.annotateCombineSaveAsEdit)
    XCTAssertTrue(CombineSaveAsEditPreference.isEnabled(userDefaults: defaults))
  }

  func testPreferencesTabsRemainUniqueAndHashable() {
    let tabs: Set<PreferencesTab> = [
      .general,
      .capture,
      .annotate,
      .quickAccess,
      .history,
      .shortcuts,
      .permissions,
      .cloud,
      .advanced,
      .about,
    ]

    XCTAssertEqual(tabs.count, 10)
  }

  private func makeDefaults(
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws -> UserDefaults {
    let suiteName = "SnapzyTests.PreferencesCoreTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName), file: file, line: line)
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }
}
