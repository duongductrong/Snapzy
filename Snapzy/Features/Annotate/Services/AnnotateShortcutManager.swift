//
//  AnnotateShortcutManager.swift
//  Snapzy
//
//  Manages keyboard shortcuts for annotation tools (local, single-key)
//

import Combine
import Foundation

/// Manager for annotation tool keyboard shortcuts
@MainActor
final class AnnotateShortcutManager: ObservableObject {

  static let shared = AnnotateShortcutManager()

  /// Current shortcut bindings (tool -> key)
  @Published private(set) var shortcuts: [AnnotationToolType: Character] = [:]

  /// UserDefaults key prefix
  private let keyPrefix = "annotate.shortcut."

  /// Tools that support shortcuts (excludes mockup - internal only)
  static let configurableTools: [AnnotationToolType] = [
    .selection, .crop, .rectangle, .oval, .arrow,
    .line, .text, .highlighter, .blur, .counter, .pencil
  ]

  private init() {
    loadShortcuts()
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
}
