//
//  SnapzyConfigurationShortcutCodecTests.swift
//  SnapzyTests
//
//  Regression tests for the TOML shortcut serializer: a shortcut must survive
//  export (ShortcutConfig -> TOML key/modifiers) and import (TOML -> ShortcutConfig)
//  unchanged. Function-key bindings (e.g. ⌘F5) were silently dropped on import
//  because the parser did not recognize any F-key label that the exporter emits.
//

import Carbon.HIToolbox
import XCTest
@testable import Snapzy

final class SnapzyConfigurationShortcutCodecTests: XCTestCase {

  // MARK: - Export side (ShortcutConfig -> TOML key string)

  func testExportKey_serializesFunctionKeysAsLabels() {
    XCTAssertEqual(SnapzyConfigurationShortcutCodec.exportKey(f(kVK_F1)), "F1")
    XCTAssertEqual(SnapzyConfigurationShortcutCodec.exportKey(f(kVK_F5)), "F5")
    XCTAssertEqual(SnapzyConfigurationShortcutCodec.exportKey(f(kVK_F12)), "F12")
    XCTAssertEqual(SnapzyConfigurationShortcutCodec.exportKey(f(kVK_F13)), "F13")
    XCTAssertEqual(SnapzyConfigurationShortcutCodec.exportKey(f(kVK_F20)), "F20")
  }

  // MARK: - Round trip (the lossless contract)

  func testRoundTrip_commandF5_preservesFunctionKeyBinding() {
    let original = ShortcutConfig(keyCode: UInt32(kVK_F5), modifiers: UInt32(cmdKey))
    XCTAssertEqual(roundTrip(original), original)
  }

  func testRoundTrip_functionKeysAcrossRange_preserveKeyCodeAndModifiers() {
    // Every modifier combination must survive export -> import. The lossless
    // contract is equality of the restored ShortcutConfig; modifier bits are
    // order-independent, so this also covers the modifier round trip.
    let cases: [(keyCode: Int, modifiers: UInt32)] = [
      (kVK_F1, UInt32(cmdKey) | UInt32(shiftKey)),
      (kVK_F5, UInt32(cmdKey)),
      (kVK_F12, UInt32(optionKey)),
      (kVK_F13, UInt32(controlKey) | UInt32(cmdKey)),
      (kVK_F20, UInt32(shiftKey) | UInt32(optionKey))
    ]

    for tc in cases {
      let original = ShortcutConfig(keyCode: UInt32(tc.keyCode), modifiers: tc.modifiers)
      XCTAssertEqual(roundTrip(original), original, "Function key code \(tc.keyCode) did not round-trip")
    }
  }

  func testRoundTrip_nonFunctionKeysRemainUnchanged() {
    let commandA = ShortcutConfig(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey))
    XCTAssertEqual(roundTrip(commandA), commandA)

    let shiftCommand3 = ShortcutConfig(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey) | UInt32(shiftKey))
    XCTAssertEqual(roundTrip(shiftCommand3), shiftCommand3)

    let commandSpace = ShortcutConfig(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))
    XCTAssertEqual(roundTrip(commandSpace), commandSpace)
  }

  func testRoundTrip_overlayFunctionKey_usesSameParserAsGlobalShortcuts() {
    // Capture-overlay shortcuts flow through a distinct codec entry point
    // (overlayShortcut) that shares keyCode(for:) with the global-shortcut path.
    // The exporter wraps the overlay into a ShortcutConfig before serializing;
    // mirror that here and pin the F-key round trip directly.
    let original = CaptureOverlayShortcut(keyCode: UInt32(kVK_F5), modifiers: UInt32(cmdKey))
    let exported = ShortcutConfig(keyCode: original.keyCode, modifiers: original.modifiers)

    let restored = SnapzyConfigurationShortcutCodec.overlayShortcut(
      key: SnapzyConfigurationShortcutCodec.exportKey(exported),
      modifiers: SnapzyConfigurationShortcutCodec.exportModifiers(exported)
    )

    XCTAssertEqual(restored, original)
  }

  // MARK: - Parser is case-insensitive on the F-key label (mirrors letters)

  func testShortcut_parsesLowercaseFunctionKeyLabel() {
    let parsed = SnapzyConfigurationShortcutCodec.shortcut(
      key: "f5",
      modifiers: ["command"],
      requireModifier: true
    )
    XCTAssertEqual(parsed, ShortcutConfig(keyCode: UInt32(kVK_F5), modifiers: UInt32(cmdKey)))
  }

  func testShortcut_rejectsUnknownKey() {
    XCTAssertNil(SnapzyConfigurationShortcutCodec.shortcut(key: "F99", modifiers: ["command"], requireModifier: true))
  }

  // MARK: - Helpers

  private func f(_ keyCode: Int) -> ShortcutConfig {
    ShortcutConfig(keyCode: UInt32(keyCode), modifiers: 0)
  }

  /// Export a ShortcutConfig to its TOML key + modifiers, then parse it back the same
  /// way the importer does. A lossless serializer returns a config equal to the input.
  private func roundTrip(_ config: ShortcutConfig) -> ShortcutConfig? {
    SnapzyConfigurationShortcutCodec.shortcut(
      key: SnapzyConfigurationShortcutCodec.exportKey(config),
      modifiers: SnapzyConfigurationShortcutCodec.exportModifiers(config),
      requireModifier: true
    )
  }
}
