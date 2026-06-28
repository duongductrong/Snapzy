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

enum AnnotateActionShortcutKind: String, CaseIterable, Codable {
  case copyAndClose
  case toggleSidebar
  case togglePin
  case cloudUpload
  case autoRedactSensitiveData
}

/// Manager for annotation tool keyboard shortcuts
@MainActor
final class AnnotateShortcutManager: ObservableObject {

  static let shared = AnnotateShortcutManager()

  /// Current shortcut bindings (tool -> key)
  @Published private(set) var shortcuts: [AnnotationToolType: Character] = [:]
  @Published private(set) var disabledToolShortcuts: Set<AnnotationToolType> = []

  /// Configurable action shortcuts (modifier+key combos)
  @Published private(set) var copyAndCloseShortcut: ShortcutConfig?
  @Published private(set) var toggleSidebarShortcut: ShortcutConfig?
  @Published private(set) var togglePinShortcut: ShortcutConfig?
  @Published private(set) var cloudUploadShortcut: ShortcutConfig?
  @Published private(set) var autoRedactSensitiveDataShortcut: ShortcutConfig?
  @Published private(set) var disabledActionShortcuts: Set<AnnotateActionShortcutKind> = []

  /// UserDefaults key prefix
  private let keyPrefix = "annotate.shortcut."
  private let copyAndCloseKey = "annotate.action.copyAndClose"
  private let toggleSidebarKey = "annotate.action.toggleSidebar"
  private let togglePinKey = "annotate.action.togglePin"
  private let cloudUploadKey = "annotate.action.cloudUpload"
  private let autoRedactSensitiveDataKey = "annotate.action.autoRedactSensitiveData"
  private let disabledToolShortcutsKey = PreferencesKeys.disabledAnnotateToolShortcuts
  private let disabledActionShortcutsKey = PreferencesKeys.disabledAnnotateActionShortcuts
  private let explicitEmptyActionShortcutData = Data("null".utf8)

  /// Tools that support shortcuts (excludes mockup - internal only)
  static let configurableTools: [AnnotationToolType] = [
    .crop, .selection, .rectangle, .filledRectangle, .oval, .arrow,
    .line, .text, .highlighter, .blur, .spotlight, .counter, .watermark, .pencil
  ]

  /// Default: ⌘⇧C
  static let defaultCopyAndClose = ShortcutConfig(
    keyCode: UInt32(kVK_ANSI_C),
    modifiers: UInt32(cmdKey | shiftKey)
  )

  /// Default: ⌘B
  static let defaultToggleSidebar = ShortcutConfig(
    keyCode: UInt32(kVK_ANSI_B),
    modifiers: UInt32(cmdKey)
  )

  /// Default: ⌃⌘P
  static let defaultTogglePin = ShortcutConfig(
    keyCode: UInt32(kVK_ANSI_P),
    modifiers: UInt32(cmdKey | controlKey)
  )

  /// Default: ⌘U
  static let defaultCloudUpload = ShortcutConfig(
    keyCode: UInt32(kVK_ANSI_U),
    modifiers: UInt32(cmdKey)
  )

  /// No default shortcut; available for users who want a local Annotate action key.
  static let defaultAutoRedactSensitiveData: ShortcutConfig? = nil

  private init() {
    copyAndCloseShortcut = Self.defaultCopyAndClose
    toggleSidebarShortcut = Self.defaultToggleSidebar
    togglePinShortcut = Self.defaultTogglePin
    cloudUploadShortcut = Self.defaultCloudUpload
    autoRedactSensitiveDataShortcut = Self.defaultAutoRedactSensitiveData
    loadShortcuts()
    loadDisabledToolShortcuts()
    loadActionShortcuts()
    loadDisabledActionShortcuts()
  }

  // MARK: - Lookup

  /// Get tool for a given key press
  func tool(for key: Character) -> AnnotationToolType? {
    shortcuts.first { isShortcutEnabled(for: $0.key) && $0.value == key }?.key
  }

  /// Get current shortcut for a tool
  func shortcut(for tool: AnnotationToolType) -> Character? {
    shortcuts[tool]
  }

  func isShortcutEnabled(for tool: AnnotationToolType) -> Bool {
    !disabledToolShortcuts.contains(tool)
  }

  func setShortcutEnabled(_ enabled: Bool, for tool: AnnotationToolType) {
    guard isShortcutEnabled(for: tool) != enabled else { return }
    var updated = disabledToolShortcuts
    if enabled {
      updated.remove(tool)
    } else {
      updated.insert(tool)
    }
    disabledToolShortcuts = updated
    saveDisabledToolShortcuts()
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
    disabledToolShortcuts = []
    saveDisabledToolShortcuts()

    // Reset action shortcuts
    disabledActionShortcuts = []
    saveDisabledActionShortcuts()
    setCopyAndCloseShortcut(Self.defaultCopyAndClose)
    setToggleSidebarShortcut(Self.defaultToggleSidebar)
    setTogglePinShortcut(Self.defaultTogglePin)
    setCloudUploadShortcut(Self.defaultCloudUpload)
    setAutoRedactSensitiveDataShortcut(Self.defaultAutoRedactSensitiveData)
  }

  // MARK: - Action Shortcut Mutation

  func setCopyAndCloseShortcut(_ config: ShortcutConfig?) {
    copyAndCloseShortcut = config
    saveActionShortcut(config, forKey: copyAndCloseKey)
  }

  func setToggleSidebarShortcut(_ config: ShortcutConfig?) {
    toggleSidebarShortcut = config
    saveActionShortcut(config, forKey: toggleSidebarKey)
  }

  func setTogglePinShortcut(_ config: ShortcutConfig?) {
    togglePinShortcut = config
    saveActionShortcut(config, forKey: togglePinKey)
  }

  func setCloudUploadShortcut(_ config: ShortcutConfig?) {
    cloudUploadShortcut = config
    saveActionShortcut(config, forKey: cloudUploadKey)
  }

  func setAutoRedactSensitiveDataShortcut(_ config: ShortcutConfig?) {
    autoRedactSensitiveDataShortcut = config
    saveActionShortcut(config, forKey: autoRedactSensitiveDataKey)
  }

  func isActionShortcutEnabled(for kind: AnnotateActionShortcutKind) -> Bool {
    !disabledActionShortcuts.contains(kind)
  }

  func shortcut(for kind: AnnotateActionShortcutKind) -> ShortcutConfig? {
    switch kind {
    case .copyAndClose:
      return copyAndCloseShortcut
    case .toggleSidebar:
      return toggleSidebarShortcut
    case .togglePin:
      return togglePinShortcut
    case .cloudUpload:
      return cloudUploadShortcut
    case .autoRedactSensitiveData:
      return autoRedactSensitiveDataShortcut
    }
  }

  func setActionShortcutEnabled(_ enabled: Bool, for kind: AnnotateActionShortcutKind) {
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

  /// Check if an NSEvent matches the Copy & Close shortcut
  func matchesCopyAndClose(_ event: NSEvent) -> Bool {
    guard isActionShortcutEnabled(for: .copyAndClose) else { return false }
    guard let copyAndCloseShortcut else { return false }
    return matchesShortcut(copyAndCloseShortcut, event: event)
  }

  /// Check if an NSEvent matches the Toggle Sidebar shortcut
  func matchesToggleSidebar(_ event: NSEvent) -> Bool {
    guard isActionShortcutEnabled(for: .toggleSidebar) else { return false }
    guard let toggleSidebarShortcut else { return false }
    return matchesShortcut(toggleSidebarShortcut, event: event)
  }

  /// Check if an NSEvent matches the Toggle Pin shortcut
  func matchesTogglePin(_ event: NSEvent) -> Bool {
    guard isActionShortcutEnabled(for: .togglePin) else { return false }
    guard let togglePinShortcut else { return false }
    return matchesShortcut(togglePinShortcut, event: event)
  }

  /// Check if an NSEvent matches the Cloud Upload shortcut
  func matchesCloudUpload(_ event: NSEvent) -> Bool {
    guard isActionShortcutEnabled(for: .cloudUpload) else { return false }
    guard let cloudUploadShortcut else { return false }
    return matchesShortcut(cloudUploadShortcut, event: event)
  }

  /// Check if an NSEvent matches the Auto Redact Sensitive Data shortcut.
  func matchesAutoRedactSensitiveData(_ event: NSEvent) -> Bool {
    guard isActionShortcutEnabled(for: .autoRedactSensitiveData) else { return false }
    guard let autoRedactSensitiveDataShortcut else { return false }
    return matchesShortcut(autoRedactSensitiveDataShortcut, event: event)
  }

  // MARK: - Validation

  /// Check if key conflicts with another tool's shortcut
  func conflictingTool(for key: Character, excluding tool: AnnotationToolType) -> AnnotationToolType? {
    shortcuts.first {
      $0.key != tool && isShortcutEnabled(for: $0.key) && $0.value == key
    }?.key
  }

  // MARK: - Persistence

  private func loadShortcuts() {
    for tool in Self.configurableTools {
      let key = keyPrefix + tool.rawValue
      if let stored = UserDefaults.standard.string(forKey: key) {
        if let char = stored.first {
          shortcuts[tool] = char
        } else {
          shortcuts.removeValue(forKey: tool)
        }
      } else {
        // Use default if not customized
        shortcuts[tool] = tool.defaultShortcut
      }
    }
  }

  private func loadDisabledToolShortcuts() {
    guard let rawValues = UserDefaults.standard.array(forKey: disabledToolShortcutsKey) as? [String] else {
      disabledToolShortcuts = []
      return
    }
    disabledToolShortcuts = Set(rawValues.compactMap(AnnotationToolType.init(rawValue:)))
  }

  private func saveShortcut(for tool: AnnotationToolType) {
    let key = keyPrefix + tool.rawValue
    if let shortcut = shortcuts[tool] {
      UserDefaults.standard.set(String(shortcut), forKey: key)
    } else {
      UserDefaults.standard.set("", forKey: key)
    }
  }

  private func saveDisabledToolShortcuts() {
    let rawValues = disabledToolShortcuts.map(\.rawValue).sorted()
    UserDefaults.standard.set(rawValues, forKey: disabledToolShortcutsKey)
  }

  // MARK: - Action Shortcut Persistence

  private func loadActionShortcuts() {
    copyAndCloseShortcut = loadActionShortcut(forKey: copyAndCloseKey, defaultValue: Self.defaultCopyAndClose)
    toggleSidebarShortcut = loadActionShortcut(forKey: toggleSidebarKey, defaultValue: Self.defaultToggleSidebar)
    togglePinShortcut = loadActionShortcut(forKey: togglePinKey, defaultValue: Self.defaultTogglePin)
    cloudUploadShortcut = loadActionShortcut(forKey: cloudUploadKey, defaultValue: Self.defaultCloudUpload)
    autoRedactSensitiveDataShortcut = loadActionShortcut(
      forKey: autoRedactSensitiveDataKey,
      defaultValue: Self.defaultAutoRedactSensitiveData
    )
  }

  private func loadDisabledActionShortcuts() {
    guard let rawValues = UserDefaults.standard.array(forKey: disabledActionShortcutsKey) as? [String] else {
      disabledActionShortcuts = []
      return
    }
    disabledActionShortcuts = Set(rawValues.compactMap(AnnotateActionShortcutKind.init(rawValue:)))
  }

  private func saveActionShortcut(_ config: ShortcutConfig?, forKey key: String) {
    guard let config else {
      UserDefaults.standard.set(explicitEmptyActionShortcutData, forKey: key)
      return
    }
    if let data = try? JSONEncoder().encode(config) {
      UserDefaults.standard.set(data, forKey: key)
    }
  }

  private func loadActionShortcut(forKey key: String, defaultValue: ShortcutConfig?) -> ShortcutConfig? {
    guard let data = UserDefaults.standard.data(forKey: key) else { return defaultValue }
    if data == explicitEmptyActionShortcutData {
      return nil
    }
    return (try? JSONDecoder().decode(ShortcutConfig.self, from: data)) ?? defaultValue
  }

  private func saveDisabledActionShortcuts() {
    let rawValues = disabledActionShortcuts.map(\.rawValue).sorted()
    UserDefaults.standard.set(rawValues, forKey: disabledActionShortcutsKey)
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
    if config.modifiers & ShortcutConfig.functionCarbonModifier != 0 { expected.insert(.function) }
    return flags == expected
  }
}
