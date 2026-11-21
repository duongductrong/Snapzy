//
//  VideoEditorShortcutManager.swift
//  Snapzy
//
//  Configurable Video Editor action shortcuts (modifier+key combos, editor-local).
//

import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

enum VideoEditorActionShortcutKind: String, CaseIterable, Codable {
  case aiPrompt
}

@MainActor
final class VideoEditorShortcutManager: ObservableObject {

  static let shared = VideoEditorShortcutManager()

  /// Default: ⌘K (editor-local; nothing else in the Video Editor uses K with ⌘).
  static let defaultAIPrompt = ShortcutConfig(
    keyCode: UInt32(kVK_ANSI_K),
    modifiers: UInt32(cmdKey)
  )

  /// Fixed combos the Video Editor (or the standard Edit/Window menu) already owns. A
  /// configurable action may not take one: it is matched before SwiftUI sees the key.
  static let reservedShortcuts: [ShortcutConfig] = {
    let command = UInt32(cmdKey)
    let commandShift = UInt32(cmdKey | shiftKey)
    let keys: [(Int, UInt32)] = [
      (kVK_ANSI_Z, command),        // Undo
      (kVK_ANSI_Z, commandShift),   // Redo
      (kVK_ANSI_S, command),        // Save
      (kVK_ANSI_U, command),        // Cloud upload
      (kVK_ANSI_B, command),        // Toggle sidebar
      (kVK_ANSI_Equal, command),    // Timeline zoom in
      (kVK_ANSI_Minus, command),    // Timeline zoom out
      (kVK_ANSI_0, command),        // Timeline fit
      (kVK_ANSI_C, command),        // Copy
      (kVK_ANSI_V, command),        // Paste
      (kVK_ANSI_X, command),        // Cut
      (kVK_ANSI_A, command),        // Select all
      (kVK_ANSI_W, command),        // Close window
      (kVK_ANSI_Q, command),        // Quit
      (kVK_ANSI_M, command),        // Minimize
      (kVK_ANSI_H, command),        // Hide
      (kVK_ANSI_Comma, command),    // Settings
    ]
    return keys.map { ShortcutConfig(keyCode: UInt32($0.0), modifiers: $0.1) }
  }()

  @Published private(set) var aiPromptShortcut: ShortcutConfig?
  @Published private(set) var disabledActionShortcuts: Set<VideoEditorActionShortcutKind> = []

  private let aiPromptKey = "videoEditor.action.aiPrompt"
  private let disabledActionShortcutsKey = PreferencesKeys.disabledVideoEditorActionShortcuts
  /// Persisted for a cleared binding so it does not fall back to the default on reload.
  private let explicitEmptyShortcutData = Data("null".utf8)
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    aiPromptShortcut = loadShortcut(forKey: aiPromptKey, defaultValue: Self.defaultAIPrompt)
    loadDisabledActionShortcuts()
  }

  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  // MARK: - Lookup

  static func defaultShortcut(for kind: VideoEditorActionShortcutKind) -> ShortcutConfig? {
    switch kind {
    case .aiPrompt: return defaultAIPrompt
    }
  }

  func shortcut(for kind: VideoEditorActionShortcutKind) -> ShortcutConfig? {
    switch kind {
    case .aiPrompt: return aiPromptShortcut
    }
  }

  func isActionShortcutEnabled(for kind: VideoEditorActionShortcutKind) -> Bool {
    !disabledActionShortcuts.contains(kind)
  }

  /// The binding that is live right now: enabled and set.
  func activeShortcut(for kind: VideoEditorActionShortcutKind) -> ShortcutConfig? {
    guard isActionShortcutEnabled(for: kind) else { return nil }
    return shortcut(for: kind)
  }

  func matches(_ kind: VideoEditorActionShortcutKind, event: NSEvent) -> Bool {
    guard event.type == .keyDown, let config = activeShortcut(for: kind) else { return false }
    return config.matches(event: event)
  }

  /// "Ask AI (⌘ K)" when bound, the bare title otherwise.
  func helpText(_ title: String, for kind: VideoEditorActionShortcutKind) -> String {
    guard let config = activeShortcut(for: kind) else { return title }
    return "\(title) (\(config.displayString))"
  }

  // MARK: - Mutation

  func setShortcut(_ config: ShortcutConfig?, for kind: VideoEditorActionShortcutKind) {
    switch kind {
    case .aiPrompt:
      aiPromptShortcut = config
      saveShortcut(config, forKey: aiPromptKey)
    }
  }

  func setActionShortcutEnabled(_ enabled: Bool, for kind: VideoEditorActionShortcutKind) {
    guard isActionShortcutEnabled(for: kind) != enabled else { return }
    var updated = disabledActionShortcuts
    if enabled {
      updated.remove(kind)
    } else {
      updated.insert(kind)
    }
    disabledActionShortcuts = updated
    saveDisabledActionShortcuts()
  }

  func resetToDefaults() {
    for kind in VideoEditorActionShortcutKind.allCases {
      setShortcut(Self.defaultShortcut(for: kind), for: kind)
      setActionShortcutEnabled(true, for: kind)
    }
  }

  // MARK: - Persistence

  private func loadShortcut(forKey key: String, defaultValue: ShortcutConfig?) -> ShortcutConfig? {
    guard let data = defaults.data(forKey: key) else { return defaultValue }
    if data == explicitEmptyShortcutData { return nil }
    return (try? JSONDecoder().decode(ShortcutConfig.self, from: data)) ?? defaultValue
  }

  private func saveShortcut(_ config: ShortcutConfig?, forKey key: String) {
    guard let config else {
      defaults.set(explicitEmptyShortcutData, forKey: key)
      return
    }
    if let data = try? JSONEncoder().encode(config) {
      defaults.set(data, forKey: key)
    }
  }

  private func loadDisabledActionShortcuts() {
    guard let rawValues = defaults.array(forKey: disabledActionShortcutsKey) as? [String] else {
      disabledActionShortcuts = []
      return
    }
    disabledActionShortcuts = Set(rawValues.compactMap(VideoEditorActionShortcutKind.init(rawValue:)))
  }

  private func saveDisabledActionShortcuts() {
    let rawValues = disabledActionShortcuts.map(\.rawValue).sorted()
    defaults.set(rawValues, forKey: disabledActionShortcutsKey)
  }
}
