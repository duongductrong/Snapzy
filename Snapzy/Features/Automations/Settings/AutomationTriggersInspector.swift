//
//  AutomationTriggersInspector.swift
//  Snapzy
//
//  Inspector for the "Source & Triggers" row: source options, keyboard
//  shortcut, where the automation is listed and whether other apps may run it.
//

import SwiftUI

struct AutomationTriggersInspector: View {
  @Binding var automation: Automation
  @Binding var shortcutIssue: ShortcutValidationIssue?
  @AppStorage(PreferencesKeys.urlSchemeEnabled) private var urlSchemeEnabled = true

  var body: some View {
    Form {
      Section {
        sourceOptions
      } header: {
        Text(L10n.Automations.sourceLabel)
      }

      if automation.runsWithoutInput {
        Section {
          ShortcutRecorderView(
            label: L10n.Automations.shortcutLabel,
            shortcut: Binding(get: { automation.hotkey }, set: { _ in }),
            validationIssue: shortcutIssue,
            onShortcutChanged: handleShortcutChange
          )
        }
      }

      Section {
        Toggle(L10n.Automations.showInMenuBar, isOn: $automation.showsInMenuBar)
          .disabled(!automation.runsWithoutInput)
        Toggle(L10n.Automations.showInQuickAccess, isOn: $automation.showsInQuickAccess)
        Toggle(L10n.Automations.showInHistory, isOn: $automation.showsInHistory)
        Toggle(L10n.Automations.showInFinder, isOn: $automation.showsInFinder)
        Toggle(L10n.Automations.showInCaptureToolbar, isOn: $automation.showsInCaptureToolbar)
      } header: {
        Text(L10n.Automations.showInLabel)
      } footer: {
        caption(automation.runsWithoutInput ? L10n.Automations.showInDescription : L10n.Automations.showInInputDescription)
      }

      AutomationExternalSection(automation: $automation, isURLSchemeEnabled: urlSchemeEnabled)
    }
    .formStyle(.grouped)
  }

  @ViewBuilder
  private var sourceOptions: some View {
    switch automation.source {
    case .capture(let spec):
      if spec.mode.isRecording {
        Picker(L10n.Automations.recordingOutputLabel, selection: specBinding(\.recordingOutput)) {
          ForEach(AutomationRecordingOutput.allCases) { output in
            Text(output.displayName).tag(output)
          }
        }
        .pickerStyle(.segmented)
      }
      Toggle(isOn: specBinding(\.saveToExportDirectory)) {
        VStack(alignment: .leading, spacing: 2) {
          Text(L10n.Automations.saveToFolderLabel)
          caption(L10n.Automations.saveToFolderDescription)
        }
      }
    case .clipboardImage:
      caption(L10n.Automations.sourceClipboardDescription)
    case .input:
      caption(L10n.Automations.sourceInputDescription)
    case .unsupported:
      caption(L10n.Automations.unsupported)
    }
  }

  private func specBinding<T>(_ keyPath: WritableKeyPath<AutomationCaptureSpec, T>) -> Binding<T> {
    Binding(
      get: {
        let spec = automation.captureSpec ?? AutomationCaptureSpec(mode: .area, saveToExportDirectory: false)
        return spec[keyPath: keyPath]
      },
      set: { value in
        guard var spec = automation.captureSpec else { return }
        spec[keyPath: keyPath] = value
        automation.source = .capture(spec)
      }
    )
  }

  private func caption(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func handleShortcutChange(_ config: ShortcutConfig?) -> Bool {
    switch ShortcutValidationService.shared.validateAutomationShortcut(config, for: automation.id) {
    case .accept(let issue):
      shortcutIssue = issue
      automation.hotkey = config
      return true
    case .reject(let issue):
      shortcutIssue = issue
      return false
    }
  }
}
