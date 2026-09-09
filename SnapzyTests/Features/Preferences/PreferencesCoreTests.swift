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
      .menuBar,
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

    XCTAssertEqual(tabs.count, 11)
    XCTAssertEqual(PreferencesTab.allCases.count, 11)
  }

  func testPreferencesTabGroups_coverAllCasesExactlyOnce() {
    let flattened = PreferencesTab.groups.flatMap { $0 }
    XCTAssertEqual(flattened.count, PreferencesTab.allCases.count)
    XCTAssertEqual(Set(flattened).count, PreferencesTab.allCases.count)
    XCTAssertEqual(PreferencesTab.groups.count, 4)
  }

  func testPreferencesTab_symbolsAndTitlesAreNonEmpty() {
    for tab in PreferencesTab.allCases {
      XCTAssertFalse(tab.title.isEmpty, "Expected title for tab \(tab)")
      XCTAssertFalse(tab.symbol.isEmpty, "Expected symbol for tab \(tab)")
      XCTAssertEqual(tab.id, tab.rawValue)
    }
  }

  @MainActor
  func testPreferencesNavigationState_historyStackAndNavigation() {
    let navigation = PreferencesNavigationState(initialTab: .general)
    XCTAssertEqual(navigation.selectedTab, .general)
    XCTAssertFalse(navigation.canGoBack)
    XCTAssertFalse(navigation.canGoForward)

    // Selecting current tab should not push history
    navigation.select(.general)
    XCTAssertFalse(navigation.canGoBack)

    // Navigate to capture
    navigation.select(.capture)
    XCTAssertEqual(navigation.selectedTab, .capture)
    XCTAssertTrue(navigation.canGoBack)
    XCTAssertFalse(navigation.canGoForward)
    XCTAssertEqual(navigation.backStack, [.general])

    // Navigate to annotate
    navigation.select(.annotate)
    XCTAssertEqual(navigation.selectedTab, .annotate)
    XCTAssertEqual(navigation.backStack, [.general, .capture])

    // Go back to capture
    navigation.goBack()
    XCTAssertEqual(navigation.selectedTab, .capture)
    XCTAssertTrue(navigation.canGoBack)
    XCTAssertTrue(navigation.canGoForward)
    XCTAssertEqual(navigation.forwardStack, [.annotate])

    // Go back to general
    navigation.goBack()
    XCTAssertEqual(navigation.selectedTab, .general)
    XCTAssertFalse(navigation.canGoBack)
    XCTAssertTrue(navigation.canGoForward)
    XCTAssertEqual(navigation.forwardStack, [.annotate, .capture])

    // Go forward to capture
    navigation.goForward()
    XCTAssertEqual(navigation.selectedTab, .capture)
    XCTAssertTrue(navigation.canGoBack)
    XCTAssertTrue(navigation.canGoForward)
    XCTAssertEqual(navigation.backStack, [.general])
    XCTAssertEqual(navigation.forwardStack, [.annotate])

    // A new selection clears the forward stack
    navigation.select(.shortcuts)
    XCTAssertEqual(navigation.selectedTab, .shortcuts)
    XCTAssertFalse(navigation.canGoForward)
    XCTAssertEqual(navigation.backStack, [.general, .capture])
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
