//
//  AnnotateShortcutManager.swift
//  Snapzy
//
//  Manages keyboard shortcuts for annotation tools (local, single-key)
//  and configurable action shortcuts (modifier+key combos)
//

import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

/// Manager for annotation tool keyboard shortcuts
@MainActor
final class AnnotateShortcutManager: ObservableObject {

  static let shared = AnnotateShortcutManager()

  /// Current shortcut bindings (tool -> key)
  @Published private(set) var shortcuts: [AnnotationToolType: Character] = [:]

  /// Configurable action shortcuts (modifier+key combos)
  @Published private(set) var copyAndCloseShortcut: ShortcutConfig
  @Published private(set) var togglePinShortcut: ShortcutConfig

  /// UserDefaults key prefix
  private let keyPrefix = "annotate.shortcut."
  private let copyAndCloseKey = "annotate.action.copyAndClose"
  private let togglePinKey = "annotate.action.togglePin"

  /// Tools that support shortcuts (excludes mockup - internal only)
  static let configurableTools: [AnnotationToolType] = [
    .selection, .crop, .rectangle, .filledRectangle, .oval, .arrow,
    .line, .text, .highlighter, .blur, .counter, .pencil
  ]

  /// Default: ⌘⇧C
  static let defaultCopyAndClose = ShortcutConfig(
    keyCode: UInt32(kVK_ANSI_C),
    modifiers: UInt32(cmdKey | shiftKey)
  )

  /// Default: ⌃⌘P
  static let defaultTogglePin = ShortcutConfig(
    keyCode: UInt32(kVK_ANSI_P),
    modifiers: UInt32(cmdKey | controlKey)
  )

  private init() {
    copyAndCloseShortcut = Self.defaultCopyAndClose
    togglePinShortcut = Self.defaultTogglePin
    loadShortcuts()
    loadActionShortcuts()
  }

  // MARK: - Lookup

  /// Get tool for a given key press
  func tool(for key: Character) -> AnnotationToolType? {
    shortcuts.first { $0.value == key }?.key
  }

  /// Get current shortcut for a tool
  func shortcut(for tool: AnnotationToolType) -> Character? {
    shortcuts[tool]
  }

  // MARK: - Mutation

  /// Set shortcut for a tool (nil to clear)
  func setShortcut(_ key: Character?, for tool: AnnotationToolType) {
    if let key = key {
      shortcuts[tool] = key
    } else {
      shortcuts.removeValue(forKey: tool)
    }
    saveShortcut(for: tool)
  }

  /// Reset all shortcuts to defaults
  func resetToDefaults() {
    for tool in Self.configurableTools {
      shortcuts[tool] = tool.defaultShortcut
      saveShortcut(for: tool)
    }
    // Reset action shortcuts
    setCopyAndCloseShortcut(Self.defaultCopyAndClose)
    setTogglePinShortcut(Self.defaultTogglePin)
  }

  // MARK: - Action Shortcut Mutation

  func setCopyAndCloseShortcut(_ config: ShortcutConfig) {
    copyAndCloseShortcut = config
    saveActionShortcut(config, forKey: copyAndCloseKey)
  }

  func setTogglePinShortcut(_ config: ShortcutConfig) {
    togglePinShortcut = config
    saveActionShortcut(config, forKey: togglePinKey)
  }

  /// Check if an NSEvent matches the Copy & Close shortcut
  func matchesCopyAndClose(_ event: NSEvent) -> Bool {
    matchesShortcut(copyAndCloseShortcut, event: event)
  }

  /// Check if an NSEvent matches the Toggle Pin shortcut
  func matchesTogglePin(_ event: NSEvent) -> Bool {
    matchesShortcut(togglePinShortcut, event: event)
  }

  // MARK: - Validation

  /// Check if key conflicts with another tool's shortcut
  func conflictingTool(for key: Character, excluding tool: AnnotationToolType) -> AnnotationToolType? {
    shortcuts.first { $0.key != tool && $0.value == key }?.key
  }

  // MARK: - Persistence

  private func loadShortcuts() {
    for tool in Self.configurableTools {
      let key = keyPrefix + tool.rawValue
      if let stored = UserDefaults.standard.string(forKey: key),
         let char = stored.first {
        shortcuts[tool] = char
      } else {
        // Use default if not customized
        shortcuts[tool] = tool.defaultShortcut
      }
    }
  }

  private func saveShortcut(for tool: AnnotationToolType) {
    let key = keyPrefix + tool.rawValue
    if let shortcut = shortcuts[tool] {
      UserDefaults.standard.set(String(shortcut), forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  // MARK: - Action Shortcut Persistence

  private func loadActionShortcuts() {
    let decoder = JSONDecoder()
    if let data = UserDefaults.standard.data(forKey: copyAndCloseKey),
       let config = try? decoder.decode(ShortcutConfig.self, from: data) {
      copyAndCloseShortcut = config
    }
    if let data = UserDefaults.standard.data(forKey: togglePinKey),
       let config = try? decoder.decode(ShortcutConfig.self, from: data) {
      togglePinShortcut = config
    }
  }

  private func saveActionShortcut(_ config: ShortcutConfig, forKey key: String) {
    if let data = try? JSONEncoder().encode(config) {
      UserDefaults.standard.set(data, forKey: key)
    }
  }

  /// Check if an NSEvent matches a given ShortcutConfig
  private func matchesShortcut(_ config: ShortcutConfig, event: NSEvent) -> Bool {
    guard UInt32(event.keyCode) == config.keyCode else { return false }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    var expected: NSEvent.ModifierFlags = []
    if config.modifiers & UInt32(cmdKey) != 0 { expected.insert(.command) }
    if config.modifiers & UInt32(shiftKey) != 0 { expected.insert(.shift) }
    if config.modifiers & UInt32(optionKey) != 0 { expected.insert(.option) }
    if config.modifiers & UInt32(controlKey) != 0 { expected.insert(.control) }
    return flags == expected
  }
}
