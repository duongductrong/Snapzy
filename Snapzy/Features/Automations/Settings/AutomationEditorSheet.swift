//
//  AutomationEditorSheet.swift
//  Snapzy
//
//  Create / edit one automation. Steps are edited as a checklist in a fixed
//  canonical order; the stored model already supports any order. Also edits
//  where the automation is listed and whether other apps may run it.
//

import SwiftUI

struct AutomationEditorSheet: View {
  let isNew: Bool
  let isCloudConfigured: Bool
  let onSave: (Automation) -> Void
  let onCancel: () -> Void

  @State private var automation: Automation
  @State private var shortcutIssue: ShortcutValidationIssue?
  @AppStorage(PreferencesKeys.urlSchemeEnabled) private var urlSchemeEnabled = true

  init(
    automation: Automation,
    isNew: Bool,
    isCloudConfigured: Bool,
    onSave: @escaping (Automation) -> Void,
    onCancel: @escaping () -> Void
  ) {
    var editable = automation
    // Show presets under their localized name; renaming makes it a custom name.
    editable.name = automation.displayName
    _automation = State(initialValue: editable)
    self.isNew = isNew
    self.isCloudConfigured = isCloudConfigured
    self.onSave = onSave
    self.onCancel = onCancel
  }

  var body: some View {
    VStack(spacing: 0) {
      Text(isNew ? L10n.Automations.editorNewTitle : L10n.Automations.editorEditTitle)
        .font(.headline)
        .padding(.top, 16)

      Form {
        Section {
          TextField(L10n.Automations.nameLabel, text: $automation.name, prompt: Text(L10n.Automations.defaultName))

          if hasDuplicateName {
            Label(L10n.Automations.duplicateNameWarning, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.orange)
          }

          Picker(L10n.Automations.sourceLabel, selection: sourceBinding) {
            ForEach(AutomationCaptureMode.allCases) { mode in
              Label(mode.displayName, systemImage: mode.symbol).tag(SourceChoice.capture(mode))
            }
            Divider()
            Label(L10n.Automations.sourceInput, systemImage: AutomationDisplay.inputSymbol).tag(SourceChoice.input)
          }

          if automation.startsCapture {
            Toggle(isOn: saveBinding) {
              VStack(alignment: .leading, spacing: 2) {
                Text(L10n.Automations.saveToFolderLabel)
                Text(L10n.Automations.saveToFolderDescription)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }

            ShortcutRecorderView(
              label: L10n.Automations.shortcutLabel,
              shortcut: Binding(get: { automation.hotkey }, set: { _ in }),
              validationIssue: shortcutIssue,
              onShortcutChanged: handleShortcutChange
            )
          } else {
            Text(L10n.Automations.sourceInputDescription)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        Section {
          ForEach(AutomationStepKind.allCases) { kind in
            Toggle(isOn: stepBinding(kind)) {
              Label(kind.displayName, systemImage: kind.symbol)
            }

            if kind == .uploadAndCopyLink, automation.contains(.uploadAndCopyLink) {
              Picker(L10n.Automations.linkFormatLabel, selection: linkFormatBinding) {
                ForEach(AutomationLinkFormat.allCases) { format in
                  Text(format.displayName).tag(format)
                }
              }
              .pickerStyle(.segmented)
              .padding(.leading, 24)

              if !isCloudConfigured {
                Label(L10n.Automations.cloudWarning, systemImage: "exclamationmark.triangle.fill")
                  .font(.caption)
                  .foregroundStyle(.orange)
                  .padding(.leading, 24)
              }
            }
          }
        } header: {
          Text(L10n.Automations.stepsLabel)
        } footer: {
          Text(L10n.Automations.stepsDescription)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Section {
          Toggle(L10n.Automations.showInMenuBar, isOn: $automation.showsInMenuBar)
            .disabled(!automation.startsCapture)
          Toggle(L10n.Automations.showInQuickAccess, isOn: $automation.showsInQuickAccess)
          Toggle(L10n.Automations.showInHistory, isOn: $automation.showsInHistory)
        } header: {
          Text(L10n.Automations.showInLabel)
        } footer: {
          Text(automation.startsCapture ? L10n.Automations.showInDescription : L10n.Automations.showInInputDescription)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        AutomationExternalSection(automation: $automation, isURLSchemeEnabled: urlSchemeEnabled)
      }
      .formStyle(.grouped)

      HStack {
        Spacer()
        Button(L10n.Common.cancel, role: .cancel, action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button(L10n.Common.save) {
          var saved = automation.normalized()
          // An untouched preset name goes back to its stored form so it keeps following the app language.
          if let preset = saved.presetID.flatMap(AutomationPreset.init(rawValue:)), saved.name == preset.localizedName {
            saved.name = preset.storedName
          }
          onSave(saved)
        }
        .keyboardShortcut(.defaultAction)
      }
      .padding(16)
    }
    .frame(width: 500, height: 680)
  }

  // MARK: - Bindings

  /// The last capture settings, kept while "Run on a File" is picked so switching back restores them.
  @State private var lastCaptureSpec: AutomationCaptureSpec?

  private var captureSpec: AutomationCaptureSpec {
    automation.captureSpec ?? lastCaptureSpec ?? AutomationCaptureSpec(mode: .area, saveToExportDirectory: false)
  }

  private enum SourceChoice: Hashable {
    case capture(AutomationCaptureMode)
    case input
  }

  private var sourceBinding: Binding<SourceChoice> {
    Binding(
      get: {
        if automation.source == .input { return .input }
        return .capture(captureSpec.mode)
      },
      set: { choice in
        switch choice {
        case .capture(let mode):
          var spec = captureSpec
          spec.mode = mode
          automation.source = .capture(spec)
        case .input:
          lastCaptureSpec = automation.captureSpec ?? lastCaptureSpec
          // Keep the hotkey / menu bar choice out of the saved model: normalization drops them.
          automation.source = .input
          shortcutIssue = nil
        }
      }
    )
  }

  private var hasDuplicateName: Bool {
    var candidate = automation
    if let preset = candidate.presetID.flatMap(AutomationPreset.init(rawValue:)), candidate.name == preset.localizedName {
      candidate.name = preset.storedName
    }
    return !AutomationStore.shared.duplicateNameIDs(for: candidate).isEmpty
  }

  private var saveBinding: Binding<Bool> {
    Binding(
      get: { captureSpec.saveToExportDirectory },
      set: { save in
        var spec = captureSpec
        spec.saveToExportDirectory = save
        automation.source = .capture(spec)
      }
    )
  }

  private func stepBinding(_ kind: AutomationStepKind) -> Binding<Bool> {
    Binding(
      get: { automation.contains(kind) },
      set: { isOn in
        var steps = automation.steps
        if isOn {
          if let index = steps.firstIndex(where: { $0.action?.kind == kind }) {
            steps[index].isEnabled = true
          } else {
            steps.append(AutomationStep(defaultAction(for: kind)))
          }
        } else {
          steps.removeAll { $0.action?.kind == kind }
        }
        automation.steps = canonicallyOrdered(steps)
      }
    )
  }

  private var linkFormatBinding: Binding<AutomationLinkFormat> {
    Binding(
      get: {
        for step in automation.steps {
          if case .uploadAndCopyLink(let format)? = step.action { return format }
        }
        return .url
      },
      set: { format in
        guard let index = automation.steps.firstIndex(where: { $0.action?.kind == .uploadAndCopyLink }) else { return }
        automation.steps[index].content = .action(.uploadAndCopyLink(format))
      }
    )
  }

  private func defaultAction(for kind: AutomationStepKind) -> AutomationStepAction {
    switch kind {
    case .copyImage: .copyImage
    case .uploadAndCopyLink: .uploadAndCopyLink(.url)
    case .showQuickAccess: .showQuickAccess
    case .openAnnotate: .openAnnotate
    case .notify: .notify
    }
  }

  /// Supported steps in the checklist's order; steps this build doesn't know stay last.
  private func canonicallyOrdered(_ steps: [AutomationStep]) -> [AutomationStep] {
    let order = AutomationStepKind.allCases
    let supported = steps
      .filter { $0.action != nil }
      .sorted { lhs, rhs in
        (order.firstIndex(of: lhs.action!.kind) ?? 0) < (order.firstIndex(of: rhs.action!.kind) ?? 0)
      }
    return supported + steps.filter { $0.action == nil }
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
