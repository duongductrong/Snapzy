//
//  AutomationAdvancedSection.swift
//  Snapzy
//
//  Settings → Automations → Advanced: the switch that allows script and
//  Shortcut steps, and the Keychain-backed secrets used as `{secret:NAME}` in
//  webhooks and custom uploaders. Secret values are write-only here.
//

import AppKit
import SwiftUI

struct AutomationAdvancedSection: View {
  @AppStorage(PreferencesKeys.automationsAllowCodeSteps) private var allowsCodeSteps = false
  @AppStorage(PreferencesKeys.automationsRunSingleFileTriggerDirectly) private var runSingleDirectly = false

  var body: some View {
    Section {
      Toggle(isOn: $allowsCodeSteps) {
        VStack(alignment: .leading, spacing: 2) {
          Text(L10n.Automations.allowCodeStepsToggle)
          Text(L10n.Automations.allowCodeStepsDescription)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .toggleStyle(.switch)
      Toggle(isOn: $runSingleDirectly) {
        VStack(alignment: .leading, spacing: 2) {
          Text(L10n.Automations.runSingleDirectlyToggle)
          Text(L10n.Automations.runSingleDirectlyDescription)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .toggleStyle(.switch)
    } header: {
      Text(L10n.Automations.advancedHeader)
    }
  }
}

struct AutomationSecretsSection: View {
  @ObservedObject private var store = AutomationSecretStore.shared
  @State private var editor: SecretEditorDraft?
  @State private var pendingDelete: String?

  var body: some View {
    Section {
      if store.entries.isEmpty {
        Text(L10n.Automations.secretsEmpty)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      ForEach(store.entries) { entry in
        HStack(spacing: 8) {
          Image(systemName: "key.fill")
            .foregroundStyle(.secondary)
          Text(entry.name)
            .font(.system(.body, design: .monospaced))
          Text(AutomationSecretStore.maskText)
            .foregroundStyle(.tertiary)
          Spacer()
          Menu {
            Button(L10n.Automations.copySecretReference) {
              let pasteboard = NSPasteboard.general
              pasteboard.clearContents()
              pasteboard.setString("{secret:\(entry.name)}", forType: .string)
            }
            Button(L10n.Automations.replaceSecretValue) {
              editor = SecretEditorDraft(existingName: entry.name)
            }
            Divider()
            Button(L10n.Common.delete, role: .destructive) {
              pendingDelete = entry.name
            }
          } label: {
            Image(systemName: "ellipsis")
          }
          .menuStyle(.borderlessButton)
          .menuIndicator(.hidden)
          .fixedSize()
          .help(L10n.Automations.moreActions)
          .accessibilityLabel(L10n.Automations.moreActions)
        }
      }
    } header: {
      VStack(alignment: .leading, spacing: 2) {
        Text(L10n.Automations.secretsHeader)
        Text(L10n.Automations.secretsDescription)
          .font(.caption)
          .fontWeight(.regular)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .textCase(nil)
    } footer: {
      Button {
        editor = SecretEditorDraft(existingName: nil)
      } label: {
        Label(L10n.Automations.addSecret, systemImage: "plus")
      }
      .buttonStyle(.liquidGlass(emphasis: .secondary, capsule: true))
      .fixedSize()
      .disabled(store.entries.count >= AutomationSecretStore.maxSecrets)
      .padding(.top, 4)
    }
    .sheet(item: $editor) { draft in
      AutomationSecretEditorSheet(existingName: draft.existingName) { editor = nil }
    }
    .alert(
      pendingDelete.map { L10n.Automations.deleteConfirmTitle($0) } ?? "",
      isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
      presenting: pendingDelete
    ) { name in
      Button(L10n.Common.delete, role: .destructive) {
        store.delete(name: name)
        pendingDelete = nil
      }
      Button(L10n.Common.cancel, role: .cancel) { pendingDelete = nil }
    }
  }
}

private struct SecretEditorDraft: Identifiable {
  let existingName: String?
  let id = UUID()
}

/// Adds a secret, or replaces the value of `existingName` (the name is then fixed).
private struct AutomationSecretEditorSheet: View {
  let existingName: String?
  let onDone: () -> Void

  @State private var name = ""
  @State private var value = ""
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(existingName == nil ? L10n.Automations.addSecret : L10n.Automations.replaceSecretValue)
        .font(.headline)
      Form {
        if let existingName {
          LabeledContent(L10n.Automations.secretNameLabel) {
            Text(existingName).font(.system(.body, design: .monospaced))
          }
        } else {
          TextField(L10n.Automations.secretNameLabel, text: $name, prompt: Text(verbatim: "SLACK_WEBHOOK"))
            .font(.system(.body, design: .monospaced))
        }
        SecureField(L10n.Automations.secretValueLabel, text: $value)
      }
      .formStyle(.columns)
      if let error {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
      }
      HStack {
        Spacer()
        Button(L10n.Common.cancel, role: .cancel, action: onDone)
          .keyboardShortcut(.cancelAction)
        Button(L10n.Common.save, action: save)
          .keyboardShortcut(.defaultAction)
          .disabled(value.isEmpty || (existingName == nil && name.trimmingCharacters(in: .whitespaces).isEmpty))
      }
    }
    .padding(20)
    .frame(width: 420)
  }

  private func save() {
    let target = existingName ?? name
    if existingName == nil, AutomationSecretStore.shared.contains(target.trimmingCharacters(in: .whitespaces)) {
      error = AutomationSecretError.duplicateName.localizedDescription
      return
    }
    do {
      try AutomationSecretStore.shared.set(name: target, value: value)
      value = ""
      onDone()
    } catch {
      self.error = error.localizedDescription
    }
  }
}
