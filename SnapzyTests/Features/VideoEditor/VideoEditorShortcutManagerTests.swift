//
//  VideoEditorShortcutManagerTests.swift
//  SnapzyTests
//
//  Configurable Video Editor action shortcuts: persistence, matching, validation.
//

import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Snapzy

@MainActor
final class VideoEditorShortcutManagerTests: XCTestCase {
  func testDefaultsToCommandK() {
    let manager = VideoEditorShortcutManager(defaults: UserDefaultsFactory.make())
    XCTAssertEqual(manager.shortcut(for: .aiPrompt), VideoEditorShortcutManager.defaultAIPrompt)
    XCTAssertTrue(manager.isActionShortcutEnabled(for: .aiPrompt))
    XCTAssertEqual(manager.helpText("Ask AI", for: .aiPrompt), "Ask AI (⌘ K)")
  }

  func testPersistsCustomClearedAndDisabledBindings() {
    let defaults = UserDefaultsFactory.make()
    let custom = ShortcutConfig(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | optionKey))

    let manager = VideoEditorShortcutManager(defaults: defaults)
    manager.setShortcut(custom, for: .aiPrompt)
    manager.setActionShortcutEnabled(false, for: .aiPrompt)

    let reloaded = VideoEditorShortcutManager(defaults: defaults)
    XCTAssertEqual(reloaded.shortcut(for: .aiPrompt), custom)
    XCTAssertFalse(reloaded.isActionShortcutEnabled(for: .aiPrompt))
    XCTAssertNil(reloaded.activeShortcut(for: .aiPrompt))
    XCTAssertEqual(reloaded.helpText("Ask AI", for: .aiPrompt), "Ask AI")

    // A cleared binding stays cleared instead of falling back to ⌘K.
    reloaded.setShortcut(nil, for: .aiPrompt)
    XCTAssertNil(VideoEditorShortcutManager(defaults: defaults).shortcut(for: .aiPrompt))

    reloaded.resetToDefaults()
    let reset = VideoEditorShortcutManager(defaults: defaults)
    XCTAssertEqual(reset.shortcut(for: .aiPrompt), VideoEditorShortcutManager.defaultAIPrompt)
    XCTAssertTrue(reset.isActionShortcutEnabled(for: .aiPrompt))
  }

  func testMatchesOnlyTheExactEnabledCombo() throws {
    let manager = VideoEditorShortcutManager(defaults: UserDefaultsFactory.make())
    let commandK = try keyDown(keyCode: kVK_ANSI_K, flags: .command, characters: "k")
    let commandShiftK = try keyDown(keyCode: kVK_ANSI_K, flags: [.command, .shift], characters: "K")

    XCTAssertTrue(manager.matches(.aiPrompt, event: commandK))
    XCTAssertFalse(manager.matches(.aiPrompt, event: commandShiftK))

    manager.setActionShortcutEnabled(false, for: .aiPrompt)
    XCTAssertFalse(manager.matches(.aiPrompt, event: commandK))
  }

  func testValidationRejectsReservedEditorCombos() {
    let validator = ShortcutValidationService.shared
    let undo = ShortcutConfig(keyCode: UInt32(kVK_ANSI_Z), modifiers: UInt32(cmdKey))
    let save = ShortcutConfig(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey))
    let free = ShortcutConfig(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | optionKey | controlKey))

    for reserved in [undo, save] {
      guard case .reject = validator.validateVideoEditorActionShortcut(reserved, for: .aiPrompt) else {
        return XCTFail("\(reserved.displayString) should be rejected")
      }
    }
    guard case .accept(nil) = validator.validateVideoEditorActionShortcut(free, for: .aiPrompt) else {
      return XCTFail("a free combo should be accepted")
    }
    guard case .accept(nil) = validator.validateVideoEditorActionShortcut(nil, for: .aiPrompt) else {
      return XCTFail("clearing should be accepted")
    }
  }

  func testValidationRejectsEnabledGlobalShortcut() throws {
    let global = KeyboardShortcutManager.shared
    guard global.isShortcutEnabled(for: .shortcutList),
          let taken = global.shortcut(for: .shortcutList) else {
      throw XCTSkip("Shortcut list hotkey is not bound on this machine")
    }
    guard case .reject(let issue) = ShortcutValidationService.shared
      .validateVideoEditorActionShortcut(taken, for: .aiPrompt) else {
      return XCTFail("a global hotkey should win over the editor action")
    }
    XCTAssertEqual(issue.swapProposal?.owner, .global(.shortcutList))
  }

  private func keyDown(keyCode: Int, flags: NSEvent.ModifierFlags, characters: String) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: flags,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: characters,
      charactersIgnoringModifiers: characters.lowercased(),
      isARepeat: false,
      keyCode: UInt16(keyCode)
    ))
  }
}
