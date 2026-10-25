//
//  PreferencesQuickAccessActionShortcutsSection.swift
//  Snapzy
//
//  Shortcuts tab rows for hover-activated Quick Access card actions.
//

import SwiftUI

/// Rows for hover-activated Quick Access card actions, placed inside the Quick Access card
/// on the Shortcuts page. The card's Reset bumps `resetCount` to clear stale highlights.
struct QuickAccessActionShortcutRows: View {
  let resetCount: Int

  @ObservedObject private var store = QuickAccessActionShortcutStore.shared
  @ObservedObject private var actionConfiguration = QuickAccessActionConfigurationStore.shared
  @State private var validationIssues: [QuickAccessActionKind: ShortcutValidationIssue] = [:]

  private let validator = ShortcutValidationService.shared

  var body: some View {
    Group {
      SettingRow(
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
            footnote: footnote(for: action),
            shortcut: shortcutBinding(for: action),
            defaultShortcut: QuickAccessActionShortcutStore.defaultShortcuts[action],
            isEnabled: enabledBinding(for: action),
            validationIssue: validationIssues[action],
            onShortcutChanged: { handleChange($0, for: action) }
          )
        }
      }
    }
    .onChange(of: resetCount) { _ in
      validationIssues.removeAll()
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
