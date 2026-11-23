//
//  PreferencesAutomationsSettingsView.swift
//  Snapzy
//
//  Settings → Automations: list, shortcut binding, edit / duplicate / delete,
//  and restoring the built-in presets.
//

import SwiftUI

private struct AutomationEditorDraft: Identifiable {
  var automation: Automation
  let isNew: Bool
  var id: UUID { automation.id }
}

struct AutomationsSettingsView: View {
  @ObservedObject private var store = AutomationStore.shared
  @ObservedObject private var cloudManager = CloudManager.shared
  @State private var editorDraft: AutomationEditorDraft?
  @State private var pendingDelete: Automation?
  @State private var validationIssues: [UUID: ShortcutValidationIssue] = [:]

  var body: some View {
    Form {
      Section {
      } header: {
        PreferencesPageHero(tab: .automations, subtitle: L10n.Automations.heroSubtitle)
      }

      Section {
        if store.automations.isEmpty {
          Text(L10n.Automations.emptyList)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
        }

        ForEach(store.automations) { automation in
          AutomationRow(
            automation: automation,
            isCloudConfigured: cloudManager.isConfigured,
            canDuplicate: store.canAdd,
            validationIssue: validationIssues[automation.id],
            onToggle: { setEnabled($0, for: automation) },
            onShortcutChanged: { handleShortcutChange($0, for: automation.id) },
            onEdit: { editorDraft = AutomationEditorDraft(automation: automation, isNew: false) },
            onDuplicate: { store.duplicate(id: automation.id) },
            onDelete: { pendingDelete = automation }
          )
        }
        .onMove { store.move(fromOffsets: $0, toOffset: $1) }
      } header: {
        VStack(alignment: .leading, spacing: 2) {
          Text(L10n.Automations.listTitle)
          Text(L10n.Automations.listDescription)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      } footer: {
        HStack(spacing: 12) {
          Button {
            editorDraft = AutomationEditorDraft(automation: makeNewAutomation(), isNew: true)
          } label: {
            Label(L10n.Automations.newButton, systemImage: "plus")
          }
          .disabled(!store.canAdd)

          if !store.missingPresets.isEmpty {
            Button(L10n.Automations.restorePresets) {
              store.restoreMissingPresets()
            }
            .buttonStyle(.link)
            .disabled(!store.canAdd)
          }

          Spacer()

          if !store.canAdd {
            Text(L10n.Automations.limitReached(AutomationStore.maxAutomations))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.top, 4)
      }
    }
    .formStyle(.grouped)
    .sheet(item: $editorDraft) { draft in
      AutomationEditorSheet(
        automation: draft.automation,
        isNew: draft.isNew,
        isCloudConfigured: cloudManager.isConfigured,
        onSave: { saved in
          if draft.isNew {
            store.add(saved)
          } else {
            store.update(saved)
          }
          validationIssues[saved.id] = nil
          editorDraft = nil
        },
        onCancel: { editorDraft = nil }
      )
    }
    .alert(
      pendingDelete.map { L10n.Automations.deleteConfirmTitle($0.displayName) } ?? "",
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }
      ),
      presenting: pendingDelete
    ) { automation in
      Button(L10n.Common.delete, role: .destructive) {
        store.delete(id: automation.id)
        validationIssues[automation.id] = nil
        pendingDelete = nil
      }
      Button(L10n.Common.cancel, role: .cancel) {
        pendingDelete = nil
      }
    } message: { _ in
      Text(L10n.Automations.deleteConfirmMessage)
    }
  }

  private func makeNewAutomation() -> Automation {
    Automation(
      name: "",
      source: .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false)),
      steps: [AutomationStep(.copyImage), AutomationStep(.notify)]
    )
  }

  /// Re-enabling re-checks the shortcut: another automation or a global action may
  /// have taken the combo while this one was off. A clash leaves it unbound.
  private func setEnabled(_ enabled: Bool, for automation: Automation) {
    if enabled, let hotkey = automation.hotkey,
       case .reject(let issue) = ShortcutValidationService.shared.validateAutomationShortcut(hotkey, for: automation.id)
    {
      validationIssues[automation.id] = issue
      store.setHotkey(nil, id: automation.id)
    }
    store.setEnabled(enabled, id: automation.id)
  }

  private func handleShortcutChange(_ config: ShortcutConfig?, for id: UUID) -> Bool {
    switch ShortcutValidationService.shared.validateAutomationShortcut(config, for: id) {
    case .accept(let issue):
      validationIssues[id] = issue
      store.setHotkey(config, id: id)
      return true
    case .reject(let issue):
      validationIssues[id] = issue
      return false
    }
  }
}

// MARK: - Row

private struct AutomationRow: View {
  let automation: Automation
  let isCloudConfigured: Bool
  let canDuplicate: Bool
  let validationIssue: ShortcutValidationIssue?
  let onToggle: (Bool) -> Void
  let onShortcutChanged: (ShortcutConfig?) -> Bool
  let onEdit: () -> Void
  let onDuplicate: () -> Void
  let onDelete: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: automation.symbol ?? rowSymbol)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 20, height: 22)

      VStack(alignment: .leading, spacing: 3) {
        if automation.source == .input {
          Toggle(isOn: Binding(get: { automation.isEnabled }, set: onToggle)) {
            Text(automation.displayName)
          }
        } else {
          ShortcutRecorderView(
            label: automation.displayName,
            shortcut: Binding(get: { automation.hotkey }, set: { _ in }),
            isEnabled: Binding(get: { automation.isEnabled }, set: onToggle),
            validationIssue: validationIssue,
            onShortcutChanged: onShortcutChanged
          )
          .disabled(automation.hasUnsupportedSource)
        }

        HStack(spacing: 4) {
          if automation.externalInvocation {
            Image(systemName: "link")
              .help(L10n.Automations.externalBadge)
              .accessibilityLabel(L10n.Automations.externalBadge)
          }
          Text(automation.summary)
            .lineLimit(2)
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        if automation.hasUnsupportedSource {
          warning(L10n.Automations.unsupported)
        } else if automation.needsCloud && !isCloudConfigured {
          HStack(spacing: 6) {
            warning(L10n.Automations.cloudWarning)
            Button(L10n.Automations.openCloudSettings) {
              PreferencesNavigationState.shared.select(.cloud)
            }
            .buttonStyle(.link)
            .font(.caption)
          }
        }
      }

      Menu {
        Button(L10n.Common.edit, action: onEdit)
          .disabled(automation.hasUnsupportedSource)
        Button(L10n.Automations.duplicate, action: onDuplicate)
          .disabled(!canDuplicate || automation.hasUnsupportedSource)
        Divider()
        Button(L10n.Common.delete, role: .destructive, action: onDelete)
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .padding(.top, 2)
      .accessibilityLabel(L10n.Automations.moreActions)
    }
    .contentShape(Rectangle())
    .onTapGesture(count: 2) {
      guard !automation.hasUnsupportedSource else { return }
      onEdit()
    }
  }

  private var rowSymbol: String {
    switch automation.source {
    case .capture(let spec): spec.mode.symbol
    case .input: AutomationDisplay.inputSymbol
    case .unsupported: "bolt.fill"
    }
  }

  private func warning(_ text: String) -> some View {
    Label(text, systemImage: "exclamationmark.triangle.fill")
      .font(.caption)
      .foregroundStyle(.orange)
      .labelStyle(.titleAndIcon)
  }
}
