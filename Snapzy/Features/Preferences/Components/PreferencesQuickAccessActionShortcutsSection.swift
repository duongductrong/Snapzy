//
//  PreferencesQuickAccessActionShortcutsSection.swift
//  Snapzy
//
//  Shortcuts tab section for hover-activated Quick Access card actions.
//

import SwiftUI

struct QuickAccessActionShortcutsSection: View {
  @ObservedObject private var store = QuickAccessActionShortcutStore.shared
  @ObservedObject private var actionConfiguration = QuickAccessActionConfigurationStore.shared
  @State private var validationIssues: [QuickAccessActionKind: ShortcutValidationIssue] = [:]

  private let validator = ShortcutValidationService.shared

  var body: some View {
    Section {
      Text(L10n.PreferencesShortcuts.cardActionsSectionDescription)
        .font(.caption)
        .foregroundColor(.secondary)

      SettingRow(
        icon: "keyboard.badge.ellipsis",
        title: L10n.PreferencesShortcuts.cardActionsEnableTitle,
        description: L10n.PreferencesShortcuts.cardActionsEnableDescription
      ) {
        Toggle("", isOn: $store.isEnabled)
          .labelsHidden()
      }

      if store.isEnabled {
        ForEach(QuickAccessActionKind.defaultOrder) { action in
          ShortcutRecorderView(
            label: action.settingsTitle,
            icon: action.systemImage,
            footnote: footnote(for: action),
            shortcut: shortcutBinding(for: action),
            defaultShortcut: QuickAccessActionShortcutStore.defaultShortcuts[action],
            isEnabled: enabledBinding(for: action),
            validationIssue: validationIssues[action],
            onShortcutChanged: { handleChange($0, for: action) }
          )
        }
      }
    } header: {
      HStack {
        Text(L10n.PreferencesShortcuts.cardActionsSection)
        Spacer()
        Button(L10n.Common.reset) {
          store.resetToDefaults()
          validationIssues.removeAll()
        }
        .buttonStyle(.borderless)
        .font(.caption)
      }
    }
  }

  /// An action removed from the card in Quick Access settings has no button to
  /// drive, so the row says so instead of silently doing nothing.
  private func footnote(for action: QuickAccessActionKind) -> String {
    guard actionConfiguration.isEnabled(action) else {
      return L10n.PreferencesQuickAccess.actionDisabledFootnote
    }
    return L10n.PreferencesShortcuts.cardActionsHoverFootnote
  }

  private func shortcutBinding(for action: QuickAccessActionKind) -> Binding<ShortcutConfig?> {
    Binding(
      get: { store.shortcut(for: action) },
      set: { store.setShortcut($0, for: action) }
    )
  }

  private func enabledBinding(for action: QuickAccessActionKind) -> Binding<Bool> {
    Binding(
      get: { store.isEnabled(for: action) },
      set: { newValue in
        if newValue {
          switch validator.validateQuickAccessActionShortcut(store.shortcut(for: action), for: action) {
          case .accept(let issue):
            validationIssues[action] = issue
          case .reject(let issue):
            validationIssues[action] = issue
            return
          }
        }

        store.setEnabled(newValue, for: action)
        if !newValue {
          validationIssues.removeValue(forKey: action)
        }
      }
    )
  }

  private func handleChange(_ config: ShortcutConfig?, for action: QuickAccessActionKind) -> Bool {
    switch validator.validateQuickAccessActionShortcut(config, for: action) {
    case .accept(let issue):
      validationIssues[action] = issue
      store.setShortcut(config, for: action)
      return true
    case .reject(let issue):
      validationIssues[action] = issue
      return false
    }
  }
}
