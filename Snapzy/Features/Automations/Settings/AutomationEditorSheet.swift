//
//  AutomationEditorSheet.swift
//  Snapzy
//
//  Create / edit one automation. Two panes: the source + step list on the
//  left, an inspector for the selected row on the right. The chain is
//  validated live; Save is disabled while a step has nothing to work on.
//

import SwiftUI

/// What the editor's inspector shows.
enum AutomationEditorSelection: Hashable {
  case triggers
  case step(UUID)
}

struct AutomationEditorSheet: View {
  let isNew: Bool
  let isCloudConfigured: Bool
  let onSave: (Automation) -> Void
  let onCancel: () -> Void

  @State private var automation: Automation
  @State private var selection: AutomationEditorSelection? = .triggers
  @State private var shortcutIssue: ShortcutValidationIssue?
  /// The last capture settings, kept while another source is picked so switching back restores them.
  @State private var lastCaptureSpec: AutomationCaptureSpec?
  @State private var isHoveringName = false
  @FocusState private var isNameFocused: Bool

  init(
    automation: Automation,
    isNew: Bool,
    isCloudConfigured: Bool,
    onSave: @escaping (Automation) -> Void,
    onCancel: @escaping () -> Void
  ) {
    var editable = automation.migrated()
    // Show presets under their localized name; renaming makes it a custom name.
    editable.name = automation.displayName
    _automation = State(initialValue: editable)
    // A default after-capture automation opens on its first step: it has no triggers.
    if editable.isSystemDefault {
      _selection = State(initialValue: editable.steps.first.map { .step($0.id) })
    }
    self.isNew = isNew
    self.isCloudConfigured = isCloudConfigured
    self.onSave = onSave
    self.onCancel = onCancel
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      if automation.needsReview {
        reviewBanner
        Divider()
      }
      if automation.isSystemDefault {
        systemDefaultBanner
        Divider()
      }
      HStack(spacing: 0) {
        AutomationStepListView(automation: $automation, selection: $selection, issues: issues)
          .frame(width: 300)
        Divider()
        inspector
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      Divider()
      footer
    }
    .frame(minWidth: 780, minHeight: 560)
  }

  // MARK: - Header

  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      PreferencesSymbolTile(symbol: automation.symbol ?? automation.sourceSymbol, size: 34, duotone: true)

      if automation.isSystemDefault {
        Text(automation.displayName)
          .font(.system(size: 17, weight: .semibold))
          .padding(.horizontal, 8)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        nameAndSource
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  @ViewBuilder
  private var nameAndSource: some View {
    VStack(alignment: .leading, spacing: 2) {
      TextField(L10n.Automations.nameLabel, text: $automation.name, prompt: Text(L10n.Automations.defaultName))
        .textFieldStyle(.plain)
        .font(.system(size: 17, weight: .semibold))
        .focused($isNameFocused)
        .padding(.horizontal, 8)
        .frame(height: Self.headerControlHeight)
        .background(
          Radius.rect(Radius.control(forHeight: Self.headerControlHeight))
            .fill(Color.primary.opacity(isNameFocused ? 0.07 : (isHoveringName ? 0.05 : 0)))
        )
        .overlay(
          Radius.rect(Radius.control(forHeight: Self.headerControlHeight))
            .strokeBorder(Color.accentColor.opacity(isNameFocused ? 0.55 : 0), lineWidth: 1)
        )
        .onHover { isHoveringName = $0 }
        .animation(.easeOut(duration: 0.15), value: isNameFocused)
        .animation(.easeOut(duration: 0.15), value: isHoveringName)
        .accessibilityLabel(L10n.Automations.nameLabel)
      if hasDuplicateName {
        Label(L10n.Automations.duplicateNameWarning, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .padding(.leading, 8)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)

    HStack(spacing: 8) {
      Text(L10n.Automations.sourceLabel)
        .foregroundStyle(.secondary)
      AutomationSourcePicker(
        automation: $automation,
        lastCaptureSpec: $lastCaptureSpec,
        onSourceChange: { shortcutIssue = nil }
      )
      .labelsHidden()
      .fixedSize()
    }
  }

  private static let headerControlHeight: CGFloat = 30

  /// Imported with network / script steps: saving is the review.
  private var reviewBanner: some View {
    Label(L10n.Automations.reviewBanner, systemImage: "checkmark.shield")
      .font(.callout)
      .foregroundStyle(.orange)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .background(Color.orange.opacity(0.08))
  }

  private var systemDefaultBanner: some View {
    Label(L10n.Automations.systemDefaultEditorNote, systemImage: "info.circle")
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
  }

  // MARK: - Inspector

  @ViewBuilder
  private var inspector: some View {
    switch selection {
    case .step(let id)?:
      if let index = automation.steps.firstIndex(where: { $0.id == id }) {
        AutomationStepInspector(
          step: $automation.steps[index],
          issues: issues.filter { $0.stepID == id },
          isCloudConfigured: isCloudConfigured,
          automationID: automation.id,
          stepsAfter: automation.steps.count - index - 1
        )
        .id(id)
      } else {
        placeholder
      }
    case .triggers? where !automation.isSystemDefault:
      AutomationTriggersInspector(automation: $automation, shortcutIssue: $shortcutIssue)
    case .triggers?:
      placeholder
    case nil:
      placeholder
    }
  }

  private var placeholder: some View {
    Text(L10n.Automations.inspectorEmpty)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Footer

  private var footer: some View {
    HStack(spacing: 12) {
      if let issue = issues.first {
        Button {
          selection = .step(issue.stepID)
        } label: {
          Label(
            L10n.Automations.issuesSummary(issues.count, issue.message),
            systemImage: issue.blocksRun ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
          )
          .foregroundStyle(issue.blocksRun ? .red : .orange)
          .lineLimit(1)
        }
        .buttonStyle(.plain)
        .font(.caption)
      }
      Spacer()
      Button(L10n.Common.cancel, role: .cancel, action: onCancel)
        .keyboardShortcut(.cancelAction)
      Button(L10n.Common.save, action: save)
        .keyboardShortcut(.defaultAction)
        .disabled(issues.contains(where: \.blocksRun))
        .help(issues.contains(where: \.blocksRun) ? L10n.Automations.saveBlockedHelp : "")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  // MARK: - Helpers

  private var issues: [AutomationChainIssue] {
    let presets = Set(AnnotateCanvasPresetStore.shared.loadPresets().map(\.id))
    return AutomationChainValidator.validate(automation, canvasPresetExists: { presets.contains($0) })
  }

  private var hasDuplicateName: Bool {
    guard !automation.isSystemDefault else { return false }
    return !AutomationStore.shared.duplicateNameIDs(for: storedForm(automation)).isEmpty
  }

  /// An untouched preset name goes back to its stored form so it keeps following the app language.
  private func storedForm(_ candidate: Automation) -> Automation {
    var copy = candidate
    if let type = copy.systemCaptureType, copy.name == AutomationSystemDefault.localizedName(for: type) {
      copy.name = AutomationSystemDefault.storedName(for: type)
    }
    if let preset = copy.presetID.flatMap(AutomationPreset.init(rawValue:)), copy.name == preset.localizedName {
      copy.name = preset.storedName
    }
    return copy
  }

  private func save() {
    var saved = storedForm(automation.normalized())
    // Saving from the editor is the review an imported automation waits for.
    saved.needsReview = false
    onSave(saved)
  }
}

/// Source menu: screenshot modes, recordings, clipboard image, or a handed-in file.
struct AutomationSourcePicker: View {
  @Binding var automation: Automation
  @Binding var lastCaptureSpec: AutomationCaptureSpec?
  let onSourceChange: () -> Void

  private enum Choice: Hashable {
    case capture(AutomationCaptureMode)
    case clipboard
    case input
  }

  var body: some View {
    Picker(L10n.Automations.sourceLabel, selection: binding) {
      Section(L10n.Automations.sourceScreenshotSection) {
        ForEach(AutomationCaptureMode.screenshotModes) { mode in
          Label(mode.displayName, systemImage: mode.symbol).tag(Choice.capture(mode))
        }
      }
      Section(L10n.Automations.sourceRecordingSection) {
        ForEach(AutomationCaptureMode.recordingModes) { mode in
          Label(mode.displayName, systemImage: mode.symbol).tag(Choice.capture(mode))
        }
      }
      Divider()
      Label(L10n.Automations.sourceClipboard, systemImage: "list.clipboard").tag(Choice.clipboard)
      Label(L10n.Automations.sourceInput, systemImage: AutomationDisplay.inputSymbol).tag(Choice.input)
    }
  }

  private var captureSpec: AutomationCaptureSpec {
    automation.captureSpec ?? lastCaptureSpec ?? AutomationCaptureSpec(mode: .area, saveToExportDirectory: false)
  }

  private var binding: Binding<Choice> {
    Binding(
      get: {
        switch automation.source {
        case .input: .input
        case .clipboardImage: .clipboard
        case .capture, .unsupported: .capture(captureSpec.mode)
        }
      },
      set: { choice in
        if let spec = automation.captureSpec { lastCaptureSpec = spec }
        switch choice {
        case .capture(let mode):
          var spec = captureSpec
          spec.mode = mode
          automation.source = .capture(spec)
        case .clipboard:
          automation.source = .clipboardImage
        case .input:
          automation.source = .input
        }
        onSourceChange()
      }
    )
  }
}
