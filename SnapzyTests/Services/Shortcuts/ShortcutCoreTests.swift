//
//  ShortcutCoreTests.swift
//  SnapzyTests
//
//  Unit tests for shortcut value models and menu equivalents.
//

import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Snapzy

final class ShortcutCoreTests: XCTestCase {

  func testDefaultGlobalShortcuts_matchDocumentedKeys() {
    XCTAssertEqual(ShortcutConfig.defaultFullscreen.keyCode, UInt32(kVK_ANSI_3))
    XCTAssertEqual(ShortcutConfig.defaultArea.keyCode, UInt32(kVK_ANSI_4))
    XCTAssertEqual(ShortcutConfig.defaultAreaAnnotate.keyCode, UInt32(kVK_ANSI_7))
    XCTAssertEqual(ShortcutConfig.defaultRecording.keyCode, UInt32(kVK_ANSI_5))
    XCTAssertEqual(ShortcutConfig.defaultScrollingCapture.keyCode, UInt32(kVK_ANSI_6))
    XCTAssertEqual(ShortcutConfig.defaultOCR.keyCode, UInt32(kVK_ANSI_2))
    XCTAssertEqual(ShortcutConfig.defaultObjectCutout.keyCode, UInt32(kVK_ANSI_1))
    XCTAssertEqual(ShortcutConfig.defaultAnnotate.keyCode, UInt32(kVK_ANSI_A))
    XCTAssertEqual(ShortcutConfig.defaultVideoEditor.keyCode, UInt32(kVK_ANSI_E))
    XCTAssertEqual(ShortcutConfig.defaultCloudUploads.keyCode, UInt32(kVK_ANSI_L))
    XCTAssertEqual(ShortcutConfig.defaultShortcutList.keyCode, UInt32(kVK_ANSI_K))
    XCTAssertEqual(ShortcutConfig.defaultHistory.keyCode, UInt32(kVK_ANSI_H))

    let expectedModifiers = UInt32(cmdKey | shiftKey)
    XCTAssertEqual(ShortcutConfig.defaultFullscreen.modifiers, expectedModifiers)
    XCTAssertEqual(ShortcutConfig.defaultAreaAnnotate.modifiers, expectedModifiers)
    XCTAssertEqual(ShortcutConfig.defaultHistory.modifiers, expectedModifiers)
  }

  func testShortcutConfigKeyCodeToString_mapsPrintableAndSpecialKeys() {
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_ANSI_A)), "A")
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_ANSI_0)), "0")
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_F12)), "F12")
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_F13)), "F13")
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_F14)), "F14")
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_F20)), "F20")
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_LeftArrow)), "\u{2190}")
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_ANSI_Slash)), "/")
    XCTAssertEqual(ShortcutConfig.keyCodeToString(9999), "?")
  }

  func testShortcutConfigDisplayParts_includeFnWithExtendedFunctionKeys() {
    let f13 = ShortcutConfig(
      keyCode: UInt32(kVK_F13),
      modifiers: ShortcutConfig.functionCarbonModifier
    )
    let f14 = ShortcutConfig(
      keyCode: UInt32(kVK_F14),
      modifiers: ShortcutConfig.functionCarbonModifier
    )

    XCTAssertEqual(f13.displayParts, ["fn", "F13"])
    XCTAssertEqual(f13.displayString, "fn F13")
    XCTAssertEqual(f14.displayParts, ["fn", "F14"])
  }

  func testShortcutConfigMenuKeyEquivalent_mapsSpecialKeys() {
    XCTAssertEqual(ShortcutConfig(keyCode: UInt32(kVK_Space), modifiers: 0).menuKeyEquivalent, " ")
    XCTAssertEqual(ShortcutConfig(keyCode: UInt32(kVK_Return), modifiers: 0).menuKeyEquivalent, "\r")
    XCTAssertEqual(ShortcutConfig(keyCode: UInt32(kVK_Tab), modifiers: 0).menuKeyEquivalent, "\t")
    XCTAssertEqual(ShortcutConfig(keyCode: UInt32(kVK_Escape), modifiers: 0).menuKeyEquivalent, "\u{1B}")
    XCTAssertNotNil(ShortcutConfig(keyCode: UInt32(kVK_F1), modifiers: 0).menuKeyEquivalent)
    XCTAssertNotNil(ShortcutConfig(keyCode: UInt32(kVK_F13), modifiers: 0).menuKeyEquivalent)
    XCTAssertNotNil(ShortcutConfig(keyCode: UInt32(kVK_F20), modifiers: 0).menuKeyEquivalent)
  }

  func testShortcutConfigMenuModifierFlags_convertCarbonModifiers() {
    let config = ShortcutConfig(
      keyCode: UInt32(kVK_ANSI_A),
      modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
    )

    let flags = config.menuModifierFlags
    XCTAssertTrue(flags.contains(.command))
    XCTAssertTrue(flags.contains(.shift))
    XCTAssertTrue(flags.contains(.option))
    XCTAssertTrue(flags.contains(.control))
  }

  func testGlobalShortcutKindSystemConflictRelevance_isLimitedToSystemScreenshotDefaults() {
    let relevant = Set(GlobalShortcutKind.allCases.filter(\.isSystemConflictRelevant))

    XCTAssertEqual(relevant, [.fullscreen, .area, .recording])
  }

  func testAreaAnnotateDefaultEnabledUnlessPersistedDisabled() {
    let freshDefaults = KeyboardShortcutManager.disabledShortcutSet(from: nil)
    XCTAssertFalse(freshDefaults.contains(.areaAnnotate))

    let persistedDefaults = KeyboardShortcutManager.disabledShortcutSet(from: [])
    XCTAssertFalse(persistedDefaults.contains(.areaAnnotate))

    let existingDisabledPreference = KeyboardShortcutManager.disabledShortcutSet(from: ["areaAnnotate"])
    XCTAssertTrue(existingDisabledPreference.contains(.areaAnnotate))
  }
}
