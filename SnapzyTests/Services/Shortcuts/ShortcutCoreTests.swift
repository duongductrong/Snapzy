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
    XCTAssertEqual(ShortcutConfig.defaultRepeatArea.keyCode, UInt32(kVK_ANSI_4))
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
    XCTAssertEqual(ShortcutConfig.defaultRepeatArea.modifiers, UInt32(controlKey | cmdKey | shiftKey))
    XCTAssertEqual(ShortcutConfig.defaultFullscreen.modifiers, expectedModifiers)
    XCTAssertEqual(ShortcutConfig.defaultAreaAnnotate.modifiers, expectedModifiers)
    XCTAssertEqual(ShortcutConfig.defaultHistory.modifiers, expectedModifiers)
  }

  func testShortcutConfigKeyCodeToString_mapsPrintableAndSpecialKeys() {
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_ANSI_A)), "A")
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_ANSI_0)), "0")
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_F12)), "F12")
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_LeftArrow)), "\u{2190}")
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_ANSI_Slash)), "/")
    XCTAssertEqual(ShortcutConfig.keyCodeToString(9999), "?")
  }

  func testShortcutConfigMenuKeyEquivalent_mapsSpecialKeys() {
    XCTAssertEqual(ShortcutConfig(keyCode: UInt32(kVK_Space), modifiers: 0).menuKeyEquivalent, " ")
    XCTAssertEqual(ShortcutConfig(keyCode: UInt32(kVK_Return), modifiers: 0).menuKeyEquivalent, "\r")
    XCTAssertEqual(ShortcutConfig(keyCode: UInt32(kVK_Tab), modifiers: 0).menuKeyEquivalent, "\t")
    XCTAssertEqual(ShortcutConfig(keyCode: UInt32(kVK_Escape), modifiers: 0).menuKeyEquivalent, "\u{1B}")
    XCTAssertNotNil(ShortcutConfig(keyCode: UInt32(kVK_F1), modifiers: 0).menuKeyEquivalent)
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

    XCTAssertEqual(relevant, [.fullscreen, .area, .repeatArea, .recording])
  }

  func testAreaAnnotateDefaultEnabledUnlessPersistedDisabled() {
    let freshDefaults = KeyboardShortcutManager.disabledShortcutSet(from: nil)
    XCTAssertFalse(freshDefaults.contains(.areaAnnotate))

    let persistedDefaults = KeyboardShortcutManager.disabledShortcutSet(from: [])
    XCTAssertFalse(persistedDefaults.contains(.areaAnnotate))

    let existingDisabledPreference = KeyboardShortcutManager.disabledShortcutSet(from: ["areaAnnotate"])
    XCTAssertTrue(existingDisabledPreference.contains(.areaAnnotate))
  }

  // MARK: - F13–F20 key support (issue #305)

  func testShortcutConfigKeyCodeToString_mapsExtendedFunctionKeys() {
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_F13)), "F13")
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_F14)), "F14")
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_F15)), "F15")
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_F16)), "F16")
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_F17)), "F17")
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_F18)), "F18")
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_F19)), "F19")
    XCTAssertEqual(ShortcutConfig.keyCodeToString(UInt32(kVK_F20)), "F20")
  }

  func testShortcutConfigMenuKeyEquivalent_mapsExtendedFunctionKeys() {
    for keyCode in [kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20] {
      XCTAssertNotNil(
        ShortcutConfig(keyCode: UInt32(keyCode), modifiers: 0).menuKeyEquivalent,
        "Expected menu key equivalent for keyCode \(keyCode)"
      )
    }
  }

  // MARK: - ShortcutConfig.matches(event:)

  private func makeKeyEvent(
    keyCode: UInt16,
    modifierFlags: NSEvent.ModifierFlags
  ) -> NSEvent? {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: modifierFlags,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "",
      charactersIgnoringModifiers: "",
      isARepeat: false,
      keyCode: keyCode
    )
  }

  func testMatches_fnOnlyShortcut_matchesOnlyWithFn() throws {
    let config = ShortcutConfig(
      keyCode: UInt32(kVK_F3),
      modifiers: ShortcutConfig.functionCarbonModifier
    )

    let withFn = try XCTUnwrap(makeKeyEvent(keyCode: UInt16(kVK_F3), modifierFlags: [.function]))
    XCTAssertTrue(config.matches(event: withFn))

    let withoutFn = try XCTUnwrap(makeKeyEvent(keyCode: UInt16(kVK_F3), modifierFlags: []))
    XCTAssertFalse(config.matches(event: withoutFn))
  }

  func testMatches_fnWithCommand_requiresExactModifierSet() throws {
    let config = ShortcutConfig(
      keyCode: UInt32(kVK_F3),
      modifiers: UInt32(cmdKey) | ShortcutConfig.functionCarbonModifier
    )

    let exact = try XCTUnwrap(makeKeyEvent(keyCode: UInt16(kVK_F3), modifierFlags: [.command, .function]))
    XCTAssertTrue(config.matches(event: exact))

    let missingFn = try XCTUnwrap(makeKeyEvent(keyCode: UInt16(kVK_F3), modifierFlags: [.command]))
    XCTAssertFalse(config.matches(event: missingFn), "Fn+Cmd binding must not fire on plain Cmd combo")

    let extraShift = try XCTUnwrap(
      makeKeyEvent(keyCode: UInt16(kVK_F3), modifierFlags: [.command, .function, .shift])
    )
    XCTAssertFalse(config.matches(event: extraShift))
  }

  func testMatches_wrongKeyCode_doesNotMatch() throws {
    let config = ShortcutConfig(
      keyCode: UInt32(kVK_F3),
      modifiers: ShortcutConfig.functionCarbonModifier
    )

    let otherKey = try XCTUnwrap(makeKeyEvent(keyCode: UInt16(kVK_F4), modifierFlags: [.function]))
    XCTAssertFalse(config.matches(event: otherKey))
  }

  func testMatches_capsLock_doesNotAffectMatching() throws {
    let config = ShortcutConfig(
      keyCode: UInt32(kVK_F13),
      modifiers: ShortcutConfig.functionCarbonModifier
    )

    let event = try XCTUnwrap(
      makeKeyEvent(keyCode: UInt16(kVK_F13), modifierFlags: [.function, .capsLock])
    )
    XCTAssertTrue(config.matches(event: event))
  }
}
