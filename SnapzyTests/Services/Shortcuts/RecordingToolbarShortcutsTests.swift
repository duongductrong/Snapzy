//
//  RecordingToolbarShortcutsTests.swift
//  SnapzyTests
//
//  Unit tests for the three new optional recording shortcuts:
//  - Pen / Annotation Toggle (`togglePenRecording`)
//  - Re-record / Restart Recording (`restartRecording`)
//  - Delete Recording / Cancel Recording (`deleteRecording`)
//

import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Snapzy

final class RecordingToolbarShortcutsTests: XCTestCase {

  @MainActor
  func testPreRecordToolbarWindow_usesActivatingPanelForButtonClicks() {
    let window = RecordingToolbarWindow(anchorRect: CGRect(x: 0, y: 0, width: 640, height: 360))
    defer { window.close() }

    XCTAssertTrue(window.styleMask.contains(.borderless))
    XCTAssertFalse(window.styleMask.contains(.nonactivatingPanel))
    XCTAssertTrue(window.canBecomeKey)
    XCTAssertFalse(window.canBecomeMain)
  }

  @MainActor
  func testPreRecordToolbarWindow_escapeInvokesCancel() throws {
    let window = RecordingToolbarWindow(anchorRect: CGRect(x: 0, y: 0, width: 640, height: 360))
    defer { window.close() }

    var didCancel = false
    window.onCancel = {
      didCancel = true
    }

    let event = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      characters: "\u{1b}",
      charactersIgnoringModifiers: "\u{1b}",
      isARepeat: false,
      keyCode: UInt16(kVK_Escape)
    ))

    window.keyDown(with: event)

    XCTAssertTrue(didCancel)
  }

  // MARK: - GlobalShortcutKind & ShortcutAction Case Matching

  func testRecordingToolbarShortcuts_kindsArePresent() {
    XCTAssertTrue(GlobalShortcutKind.allCases.contains(.togglePenRecording))
    XCTAssertTrue(GlobalShortcutKind.allCases.contains(.restartRecording))
    XCTAssertTrue(GlobalShortcutKind.allCases.contains(.deleteRecording))
  }

  func testRecordingToolbarShortcuts_notSystemConflictRelevant() {
    XCTAssertFalse(GlobalShortcutKind.togglePenRecording.isSystemConflictRelevant)
    XCTAssertFalse(GlobalShortcutKind.restartRecording.isSystemConflictRelevant)
    XCTAssertFalse(GlobalShortcutKind.deleteRecording.isSystemConflictRelevant)
  }

  func testRecordingToolbarShortcuts_displayNamesAreNonEmpty() {
    XCTAssertFalse(GlobalShortcutKind.togglePenRecording.displayName.isEmpty)
    XCTAssertFalse(GlobalShortcutKind.restartRecording.displayName.isEmpty)
    XCTAssertFalse(GlobalShortcutKind.deleteRecording.displayName.isEmpty)
  }

  // MARK: - KeyboardShortcutManager default state and persistence

  @MainActor
  func testKeyboardShortcutManager_toolbarShortcuts_resolveNilByDefault() {
    let manager = KeyboardShortcutManager.shared
    
    // Save current states of these shortcuts to restore on teardown
    let origPen = manager.shortcut(for: .togglePenRecording)
    let origRestart = manager.shortcut(for: .restartRecording)
    let origDelete = manager.shortcut(for: .deleteRecording)
    let origPenEnabled = manager.isShortcutEnabled(for: .togglePenRecording)
    let origRestartEnabled = manager.isShortcutEnabled(for: .restartRecording)
    let origDeleteEnabled = manager.isShortcutEnabled(for: .deleteRecording)
    
    addTeardownBlock { @MainActor in
      manager.setTogglePenRecordingShortcut(origPen)
      manager.setRestartRecordingShortcut(origRestart)
      manager.setDeleteRecordingShortcut(origDelete)
      manager.setShortcutEnabled(origPenEnabled, for: .togglePenRecording)
      manager.setShortcutEnabled(origRestartEnabled, for: .restartRecording)
      manager.setShortcutEnabled(origDeleteEnabled, for: .deleteRecording)
    }
    
    // Explicitly reset to default clean-install state
    manager.setTogglePenRecordingShortcut(nil)
    manager.setRestartRecordingShortcut(nil)
    manager.setDeleteRecordingShortcut(nil)
    manager.setShortcutEnabled(true, for: .togglePenRecording)
    manager.setShortcutEnabled(true, for: .restartRecording)
    manager.setShortcutEnabled(true, for: .deleteRecording)
    
    // Check initial/default values
    XCTAssertNil(manager.shortcut(for: .togglePenRecording))
    XCTAssertNil(manager.shortcut(for: .restartRecording))
    XCTAssertNil(manager.shortcut(for: .deleteRecording))
    
    // Check default enablement (should be toggled on)
    XCTAssertTrue(manager.isShortcutEnabled(for: .togglePenRecording))
    XCTAssertTrue(manager.isShortcutEnabled(for: .restartRecording))
    XCTAssertTrue(manager.isShortcutEnabled(for: .deleteRecording))
  }

  @MainActor
  func testKeyboardShortcutManager_togglePenRecording_persistsThenClears() {
    let manager = KeyboardShortcutManager.shared
    let initial = manager.shortcut(for: .togglePenRecording)
    addTeardownBlock { @MainActor in
      manager.setTogglePenRecordingShortcut(initial)
    }

    let defaultsKey = "togglePenRecordingShortcut"
    let combo = ShortcutConfig(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | optionKey))
    
    manager.setTogglePenRecordingShortcut(combo)
    XCTAssertEqual(manager.shortcut(for: .togglePenRecording), combo)
    XCTAssertNotNil(UserDefaults.standard.data(forKey: defaultsKey))

    manager.setTogglePenRecordingShortcut(nil)
    XCTAssertNil(manager.shortcut(for: .togglePenRecording))
    XCTAssertNil(UserDefaults.standard.data(forKey: defaultsKey))
  }

  @MainActor
  func testKeyboardShortcutManager_restartRecording_persistsThenClears() {
    let manager = KeyboardShortcutManager.shared
    let initial = manager.shortcut(for: .restartRecording)
    addTeardownBlock { @MainActor in
      manager.setRestartRecordingShortcut(initial)
    }

    let defaultsKey = "restartRecordingShortcut"
    let combo = ShortcutConfig(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(cmdKey | optionKey))
    
    manager.setRestartRecordingShortcut(combo)
    XCTAssertEqual(manager.shortcut(for: .restartRecording), combo)
    XCTAssertNotNil(UserDefaults.standard.data(forKey: defaultsKey))

    manager.setRestartRecordingShortcut(nil)
    XCTAssertNil(manager.shortcut(for: .restartRecording))
    XCTAssertNil(UserDefaults.standard.data(forKey: defaultsKey))
  }

  @MainActor
  func testKeyboardShortcutManager_deleteRecording_persistsThenClears() {
    let manager = KeyboardShortcutManager.shared
    let initial = manager.shortcut(for: .deleteRecording)
    addTeardownBlock { @MainActor in
      manager.setDeleteRecordingShortcut(initial)
    }

    let defaultsKey = "deleteRecordingShortcut"
    let combo = ShortcutConfig(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey | optionKey))
    
    manager.setDeleteRecordingShortcut(combo)
    XCTAssertEqual(manager.shortcut(for: .deleteRecording), combo)
    XCTAssertNotNil(UserDefaults.standard.data(forKey: defaultsKey))

    manager.setDeleteRecordingShortcut(nil)
    XCTAssertNil(manager.shortcut(for: .deleteRecording))
    XCTAssertNil(UserDefaults.standard.data(forKey: defaultsKey))
  }

  // MARK: - TOML Config Export/Import

  @MainActor
  func testTOMLConfigExportImport() throws {
    // Exporter configKey checks
    XCTAssertEqual(GlobalShortcutKind.togglePenRecording.configKey, "toggle_pen_recording")
    XCTAssertEqual(GlobalShortcutKind.restartRecording.configKey, "restart_recording")
    XCTAssertEqual(GlobalShortcutKind.deleteRecording.configKey, "delete_recording")

    // Default configuration document checks
    let defaultDoc = SnapzyConfigurationDefaultDocument.self
    let defaultTOML = defaultDoc.toml()
    let defaultParsed = try SimpleTOMLParser.parse(defaultTOML)
    
    XCTAssertEqual(defaultParsed.value(at: "shortcuts", "global", "toggle_pen_recording", "key")?.stringValue, "")
    XCTAssertEqual(defaultParsed.value(at: "shortcuts", "global", "toggle_pen_recording", "enabled")?.boolValue, true)
    XCTAssertEqual(defaultParsed.value(at: "shortcuts", "global", "restart_recording", "key")?.stringValue, "")
    XCTAssertEqual(defaultParsed.value(at: "shortcuts", "global", "restart_recording", "enabled")?.boolValue, true)
    XCTAssertEqual(defaultParsed.value(at: "shortcuts", "global", "delete_recording", "key")?.stringValue, "")
    XCTAssertEqual(defaultParsed.value(at: "shortcuts", "global", "delete_recording", "enabled")?.boolValue, true)

    // Import test
    let defaults = UserDefaultsFactory.make()
    let manager = KeyboardShortcutManager.shared
    
    // Save current states of these shortcuts to restore on teardown
    let origPen = manager.shortcut(for: .togglePenRecording)
    let origRestart = manager.shortcut(for: .restartRecording)
    let origDelete = manager.shortcut(for: .deleteRecording)
    let origPenEnabled = manager.isShortcutEnabled(for: .togglePenRecording)
    let origRestartEnabled = manager.isShortcutEnabled(for: .restartRecording)
    let origDeleteEnabled = manager.isShortcutEnabled(for: .deleteRecording)
    
    addTeardownBlock { @MainActor in
      manager.setTogglePenRecordingShortcut(origPen)
      manager.setRestartRecordingShortcut(origRestart)
      manager.setDeleteRecordingShortcut(origDelete)
      manager.setShortcutEnabled(origPenEnabled, for: .togglePenRecording)
      manager.setShortcutEnabled(origRestartEnabled, for: .restartRecording)
      manager.setShortcutEnabled(origDeleteEnabled, for: .deleteRecording)
    }

    let source = """
    schema_version = 1

    [shortcuts.global.toggle_pen_recording]
    key = "p"
    modifiers = ["command", "option"]
    enabled = true

    [shortcuts.global.restart_recording]
    key = "r"
    modifiers = ["command", "option"]
    enabled = true

    [shortcuts.global.delete_recording]
    key = "d"
    modifiers = ["command", "option"]
    enabled = false
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)
    XCTAssertFalse(result.hasErrors)
    
    // Check imported values in KeyboardShortcutManager
    let expectedPen = ShortcutConfig(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | optionKey))
    let expectedRestart = ShortcutConfig(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(cmdKey | optionKey))
    let expectedDelete = ShortcutConfig(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey | optionKey))
    
    XCTAssertEqual(manager.shortcut(for: .togglePenRecording), expectedPen)
    XCTAssertEqual(manager.shortcut(for: .restartRecording), expectedRestart)
    XCTAssertEqual(manager.shortcut(for: .deleteRecording), expectedDelete)
    
    XCTAssertTrue(manager.isShortcutEnabled(for: .togglePenRecording))
    XCTAssertTrue(manager.isShortcutEnabled(for: .restartRecording))
    XCTAssertFalse(manager.isShortcutEnabled(for: .deleteRecording))

    // Export test
    let exportedSource = SnapzyConfigurationExporter.exportTOML(defaults: defaults)
    let document = try SimpleTOMLParser.parse(exportedSource)
    
    XCTAssertEqual(document.value(at: "shortcuts", "global", "toggle_pen_recording", "key")?.stringValue, "P")
    XCTAssertEqual(document.value(at: "shortcuts", "global", "toggle_pen_recording", "enabled")?.boolValue, true)
    
    XCTAssertEqual(document.value(at: "shortcuts", "global", "restart_recording", "key")?.stringValue, "R")
    XCTAssertEqual(document.value(at: "shortcuts", "global", "restart_recording", "enabled")?.boolValue, true)
    
    XCTAssertEqual(document.value(at: "shortcuts", "global", "delete_recording", "key")?.stringValue, "D")
    XCTAssertEqual(document.value(at: "shortcuts", "global", "delete_recording", "enabled")?.boolValue, false)
  }
}
