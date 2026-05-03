//
//  CaptureOverlayShortcutSettingsTests.swift
//  SnapzyTests
//
//  Unit tests for CaptureOverlayShortcut persistence, display formatting,
//  and legacy migration.
//

import Carbon.HIToolbox
import XCTest
@testable import Snapzy

final class CaptureOverlayShortcutSettingsTests: XCTestCase {

  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    defaults = UserDefaultsFactory.make()
    CaptureOverlayShortcutSettings.defaults = defaults
  }

  override func tearDown() {
    CaptureOverlayShortcutSettings.defaults = .standard
    super.tearDown()
  }

  // MARK: - Default Values

  func testDefaultApplicationCaptureShortcut_isKeyA() {
    let shortcut = CaptureOverlayShortcutSettings.defaultApplicationCaptureShortcut
    XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_A))
    XCTAssertEqual(shortcut.modifiers, 0)
  }

  func testDefaultRecordingApplicationCaptureShortcut_isKeyA() {
    let shortcut = CaptureOverlayShortcutSettings.defaultRecordingApplicationCaptureShortcut
    XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_A))
    XCTAssertEqual(shortcut.modifiers, 0)
  }

  // MARK: - isIndependent

  func testIsIndependent_noModifiers_returnsFalse() {
    let shortcut = CaptureOverlayShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: 0)
    XCTAssertFalse(shortcut.isIndependent)
  }

  func testIsIndependent_withModifiers_returnsTrue() {
    let shortcut = CaptureOverlayShortcut(
      keyCode: UInt32(kVK_ANSI_A),
      modifiers: UInt32(cmdKey)
    )
    XCTAssertTrue(shortcut.isIndependent)
  }

  // MARK: - independentShortcutConfig

  func testIndependentShortcutConfig_noModifiers_returnsNil() {
    let shortcut = CaptureOverlayShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: 0)
    XCTAssertNil(shortcut.independentShortcutConfig)
  }

  func testIndependentShortcutConfig_withModifiers_returnsConfig() {
    let shortcut = CaptureOverlayShortcut(
      keyCode: UInt32(kVK_ANSI_A),
      modifiers: UInt32(cmdKey)
    )
    let config = shortcut.independentShortcutConfig
    XCTAssertNotNil(config)
    XCTAssertEqual(config?.keyCode, UInt32(kVK_ANSI_A))
    XCTAssertEqual(config?.modifiers, UInt32(cmdKey))
  }

  // MARK: - Display Parts

  func testDisplayParts_singleKeyShortcut() {
    let shortcut = CaptureOverlayShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: 0)
    let parts = shortcut.displayParts
    XCTAssertEqual(parts.count, 1)
    XCTAssertEqual(parts.first, "A")
  }

  func testDisplayString_singleKey() {
    let shortcut = CaptureOverlayShortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: 0)
    XCTAssertEqual(shortcut.displayString, "B")
  }

  // MARK: - inlineDisplay

  func testInlineDisplay_emptyParts() {
    XCTAssertEqual(CaptureOverlayShortcut.inlineDisplay(parts: []), "")
  }

  func testInlineDisplay_singlePart() {
    XCTAssertEqual(CaptureOverlayShortcut.inlineDisplay(parts: ["A"]), "A")
  }

  func testInlineDisplay_modifiersAndKey() {
    XCTAssertEqual(CaptureOverlayShortcut.inlineDisplay(parts: ["⌘", "A"]), "⌘A")
  }

  func testInlineDisplay_multipleModifiers() {
    XCTAssertEqual(CaptureOverlayShortcut.inlineDisplay(parts: ["⌘", "⇧", "A"]), "⌘⇧A")
  }

  // MARK: - JSON Roundtrip Persistence

  func testSetAndReadShortcut_applicationCapture_roundtrips() {
    let shortcut = CaptureOverlayShortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: 0)
    CaptureOverlayShortcutSettings.setApplicationCaptureShortcut(shortcut)

    let loaded = CaptureOverlayShortcutSettings.applicationCaptureShortcut
    XCTAssertEqual(loaded.keyCode, UInt32(kVK_ANSI_B))
    XCTAssertEqual(loaded.modifiers, 0)
  }

  func testSetAndReadShortcut_recordingApplicationCapture_roundtrips() {
    let shortcut = CaptureOverlayShortcut(
      keyCode: UInt32(kVK_ANSI_C),
      modifiers: UInt32(shiftKey)
    )
    CaptureOverlayShortcutSettings.setRecordingApplicationCaptureShortcut(shortcut)

    let loaded = CaptureOverlayShortcutSettings.recordingApplicationCaptureShortcut
    XCTAssertEqual(loaded.keyCode, UInt32(kVK_ANSI_C))
    XCTAssertEqual(loaded.modifiers, UInt32(shiftKey))
  }

  // MARK: - Reset

  func testResetApplicationCaptureShortcut_fallsBackToDefault() {
    let custom = CaptureOverlayShortcut(keyCode: UInt32(kVK_ANSI_Z), modifiers: 0)
    CaptureOverlayShortcutSettings.setApplicationCaptureShortcut(custom)

    // Verify custom is set
    XCTAssertEqual(CaptureOverlayShortcutSettings.applicationCaptureShortcut.keyCode, UInt32(kVK_ANSI_Z))

    // Reset
    CaptureOverlayShortcutSettings.resetApplicationCaptureShortcut()

    // Should be back to default
    let loaded = CaptureOverlayShortcutSettings.applicationCaptureShortcut
    XCTAssertEqual(loaded.keyCode, UInt32(kVK_ANSI_A))
    XCTAssertEqual(loaded.modifiers, 0)
  }

  func testResetRecordingApplicationCaptureShortcut_fallsBackToDefault() {
    let custom = CaptureOverlayShortcut(keyCode: UInt32(kVK_ANSI_Z), modifiers: 0)
    CaptureOverlayShortcutSettings.setRecordingApplicationCaptureShortcut(custom)
    CaptureOverlayShortcutSettings.resetRecordingApplicationCaptureShortcut()

    let loaded = CaptureOverlayShortcutSettings.recordingApplicationCaptureShortcut
    XCTAssertEqual(loaded.keyCode, UInt32(kVK_ANSI_A))
    XCTAssertEqual(loaded.modifiers, 0)
  }

  // MARK: - shortcut(for:) dispatch

  func testShortcutForKind_applicationCapture() {
    let shortcut = CaptureOverlayShortcutSettings.shortcut(for: .applicationCapture)
    XCTAssertEqual(shortcut.keyCode, CaptureOverlayShortcutSettings.applicationCaptureShortcut.keyCode)
  }

  func testShortcutForKind_applicationRecording() {
    let shortcut = CaptureOverlayShortcutSettings.shortcut(for: .applicationRecording)
    XCTAssertEqual(shortcut.keyCode, CaptureOverlayShortcutSettings.recordingApplicationCaptureShortcut.keyCode)
  }

  // MARK: - Legacy String Migration

  func testLegacyStringMigration_singleLetter_migratesCorrectly() {
    // Simulate legacy data: plain string stored in UserDefaults
    defaults.set("b", forKey: PreferencesKeys.areaApplicationCaptureShortcut)

    let shortcut = CaptureOverlayShortcutSettings.applicationCaptureShortcut
    XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_B))
    XCTAssertEqual(shortcut.modifiers, 0)
  }

  func testLegacyStringMigration_uppercaseLetter_migratesCorrectly() {
    defaults.set("C", forKey: PreferencesKeys.areaApplicationCaptureShortcut)

    let shortcut = CaptureOverlayShortcutSettings.applicationCaptureShortcut
    XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_C))
    XCTAssertEqual(shortcut.modifiers, 0)
  }

  func testLegacyStringMigration_invalidValue_returnsDefault() {
    // Non-letter string should fall back to default
    defaults.set("123", forKey: PreferencesKeys.areaApplicationCaptureShortcut)

    let shortcut = CaptureOverlayShortcutSettings.applicationCaptureShortcut
    XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_A)) // default
    XCTAssertEqual(shortcut.modifiers, 0)
  }

  func testLegacyStringMigration_whitespace_returnsDefault() {
    defaults.set("  ", forKey: PreferencesKeys.areaApplicationCaptureShortcut)

    let shortcut = CaptureOverlayShortcutSettings.applicationCaptureShortcut
    XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_A))
  }

  // MARK: - CaptureOverlayShortcut Codable

  func testCaptureOverlayShortcut_encodeDecode_roundtrips() throws {
    let original = CaptureOverlayShortcut(
      keyCode: UInt32(kVK_ANSI_M),
      modifiers: UInt32(cmdKey | shiftKey)
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(CaptureOverlayShortcut.self, from: data)

    XCTAssertEqual(decoded.keyCode, original.keyCode)
    XCTAssertEqual(decoded.modifiers, original.modifiers)
  }

  // MARK: - Equatable

  func testCaptureOverlayShortcut_equatable() {
    let a = CaptureOverlayShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: 0)
    let b = CaptureOverlayShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: 0)
    let c = CaptureOverlayShortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: 0)

    XCTAssertEqual(a, b)
    XCTAssertNotEqual(a, c)
  }

  // MARK: - CaptureOverlayShortcutKind display

  func testCaptureOverlayShortcutKind_displayNames_nonEmpty() {
    XCTAssertFalse(CaptureOverlayShortcutKind.applicationCapture.displayName.isEmpty)
    XCTAssertFalse(CaptureOverlayShortcutKind.applicationRecording.displayName.isEmpty)
  }

  // MARK: - Space Key Support

  func testInitFromEvent_spaceKey_createsShortcut() {
    let event = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: " ",
      charactersIgnoringModifiers: " ",
      isARepeat: false,
      keyCode: UInt16(kVK_Space)
    )
    XCTAssertNotNil(event)
    let shortcut = CaptureOverlayShortcut(from: event!)
    XCTAssertNotNil(shortcut)
    XCTAssertEqual(shortcut?.keyCode, UInt32(kVK_Space))
    XCTAssertEqual(shortcut?.modifiers, 0)
  }

  func testDisplayParts_spaceKey() {
    let shortcut = CaptureOverlayShortcut(keyCode: UInt32(kVK_Space), modifiers: 0)
    XCTAssertEqual(shortcut.displayParts, ["Space"])
    XCTAssertEqual(shortcut.displayString, "Space")
  }

  func testSetAndReadShortcut_spaceKey_roundtrips() {
    let shortcut = CaptureOverlayShortcut(keyCode: UInt32(kVK_Space), modifiers: 0)
    CaptureOverlayShortcutSettings.setApplicationCaptureShortcut(shortcut)

    let loaded = CaptureOverlayShortcutSettings.applicationCaptureShortcut
    XCTAssertEqual(loaded.keyCode, UInt32(kVK_Space))
    XCTAssertEqual(loaded.modifiers, 0)
  }

  func testLegacyStringMigration_space_migratesCorrectly() {
    defaults.set(" ", forKey: PreferencesKeys.areaApplicationCaptureShortcut)

    let shortcut = CaptureOverlayShortcutSettings.applicationCaptureShortcut
    XCTAssertEqual(shortcut.keyCode, UInt32(kVK_Space))
    XCTAssertEqual(shortcut.modifiers, 0)
  }

  func testSetAndReadShortcut_spaceKey_recording_roundtrips() {
    let shortcut = CaptureOverlayShortcut(keyCode: UInt32(kVK_Space), modifiers: 0)
    CaptureOverlayShortcutSettings.setRecordingApplicationCaptureShortcut(shortcut)

    let loaded = CaptureOverlayShortcutSettings.recordingApplicationCaptureShortcut
    XCTAssertEqual(loaded.keyCode, UInt32(kVK_Space))
    XCTAssertEqual(loaded.modifiers, 0)
  }
}
