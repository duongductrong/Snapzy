//
//  QuickAccessActionShortcutStore.swift
//  Snapzy
//
//  UserDefaults-backed keyboard shortcuts for Quick Access card actions.
//  Bindings are only live while a card is hovered — see
//  QuickAccessHoverShortcutRegistry for the registration lifecycle.
//

import Carbon.HIToolbox
import Combine
import Foundation

/// A card action shortcut that fired, addressed to the card under the pointer.
struct QuickAccessCardShortcutTrigger {
  let itemID: UUID
  let action: QuickAccessActionKind
}

@MainActor
final class QuickAccessActionShortcutStore: ObservableObject {
  static let shared = QuickAccessActionShortcutStore()

  /// Shipping defaults. Every entry carries at least one of ⌘/⌥/⌃ because these
  /// register as Carbon hotkeys that consume the keystroke while a card is hovered.
  static let defaultShortcuts: [QuickAccessActionKind: ShortcutConfig] = [
    .copy: ShortcutConfig(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey)),
    .saveOrOpen: ShortcutConfig(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey)),
    .edit: ShortcutConfig(keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(cmdKey)),
    .uploadToCloud: ShortcutConfig(keyCode: UInt32(kVK_ANSI_U), modifiers: UInt32(cmdKey)),
    .pinToScreen: ShortcutConfig(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey)),
    .delete: ShortcutConfig(keyCode: UInt32(kVK_Delete), modifiers: UInt32(cmdKey)),
    .dismiss: ShortcutConfig(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(cmdKey)),
  ]

  @Published private(set) var shortcuts: [QuickAccessActionKind: ShortcutConfig]
  @Published private(set) var disabledActions: Set<QuickAccessActionKind>

  @Published var isEnabled: Bool {
    didSet {
      guard isEnabled != oldValue else { return }
      defaults.set(isEnabled, forKey: Keys.masterEnabled)
    }
  }

  private let defaults: UserDefaults

  private enum Keys {
    static let shortcutPrefix = "quickAccess.action.shortcut."
    static let disabledActions = "quickAccess.action.shortcuts.disabled"
    static let masterEnabled = "quickAccess.action.shortcuts.enabled"
  }

  /// Distinguishes "user cleared this binding" from "never touched" — a missing
  /// key falls back to the default, this sentinel resolves to nil.
  private static let explicitEmptyShortcutData = Data("null".utf8)

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    isEnabled = defaults.object(forKey: Keys.masterEnabled) as? Bool ?? true
    disabledActions = Set(
      (defaults.stringArray(forKey: Keys.disabledActions) ?? [])
        .compactMap(QuickAccessActionKind.init(rawValue:))
    )

    var loaded: [QuickAccessActionKind: ShortcutConfig] = [:]
    for action in QuickAccessActionKind.allCases {
      guard let data = defaults.data(forKey: Keys.shortcutPrefix + action.rawValue) else {
        loaded[action] = Self.defaultShortcuts[action]
        continue
      }
      guard data != Self.explicitEmptyShortcutData else { continue }
      loaded[action] = (try? JSONDecoder().decode(ShortcutConfig.self, from: data))
        ?? Self.defaultShortcuts[action]
    }
    shortcuts = loaded
  }

  // MARK: - Reads

  func shortcut(for action: QuickAccessActionKind) -> ShortcutConfig? {
    shortcuts[action]
  }

  func isEnabled(for action: QuickAccessActionKind) -> Bool {
    !disabledActions.contains(action)
  }

  /// Bindings the registry should hold while a card is hovered.
  ///
  /// Fn combos are dropped: `RegisterEventHotKey` cannot express Fn, and the
  /// passive `NSEvent` fallback would let the keystroke reach the frontmost app too.
  var activeBindings: [(action: QuickAccessActionKind, shortcut: ShortcutConfig)] {
    guard isEnabled else { return [] }
    return QuickAccessActionKind.defaultOrder.compactMap { action in
      guard isEnabled(for: action),
            let shortcut = shortcuts[action],
            !Self.containsFunctionModifier(shortcut) else { return nil }
      return (action, shortcut)
    }
  }

  func action(matching config: ShortcutConfig) -> QuickAccessActionKind? {
    activeBindings.first { $0.shortcut == config }?.action
  }

  static func containsFunctionModifier(_ config: ShortcutConfig) -> Bool {
    config.modifiers & ShortcutConfig.functionCarbonModifier != 0
  }

  /// Carbon hotkeys swallow the keystroke system-wide while registered, so a
  /// binding without ⌘/⌥/⌃ would eat ordinary typing during hover.
  static func hasRequiredModifier(_ config: ShortcutConfig) -> Bool {
    config.modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
  }

  // MARK: - Writes

  func setShortcut(_ config: ShortcutConfig?, for action: QuickAccessActionKind) {
    var updated = shortcuts
    updated[action] = config
    shortcuts = updated

    if let config, let data = try? JSONEncoder().encode(config) {
      defaults.set(data, forKey: Keys.shortcutPrefix + action.rawValue)
    } else {
      defaults.set(Self.explicitEmptyShortcutData, forKey: Keys.shortcutPrefix + action.rawValue)
    }
  }

  func setEnabled(_ enabled: Bool, for action: QuickAccessActionKind) {
    var updated = disabledActions
    if enabled {
      updated.remove(action)
    } else {
      updated.insert(action)
    }
    guard updated != disabledActions else { return }
    disabledActions = updated
    persistDisabledActions()
  }

  func resetToDefaults() {
    isEnabled = true
    disabledActions = []
    persistDisabledActions()
    for action in QuickAccessActionKind.allCases {
      setShortcut(Self.defaultShortcuts[action], for: action)
    }
  }

  private func persistDisabledActions() {
    defaults.set(disabledActions.map(\.rawValue).sorted(), forKey: Keys.disabledActions)
  }
}
