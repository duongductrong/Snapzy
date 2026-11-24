//
//  AutomationControlInspectors.swift
//  Snapzy
//
//  Inspectors for control steps (milestone 5): Condition (predicate rows with
//  a readable sentence preview), Run Automation and Ask. Stop has no settings.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Condition

struct ConditionInspector: View {
  @Binding var config: AutomationConditionConfig
  /// Steps below the condition; bounds "Otherwise skip".
  let stepsAfter: Int

  var body: some View {
    Section {
      Picker(L10n.Automations.conditionMatchLabel, selection: $config.match) {
        Text(L10n.Automations.conditionMatchAll).tag(AutomationConditionConfig.Match.all)
        Text(L10n.Automations.conditionMatchAny).tag(AutomationConditionConfig.Match.any)
      }
      .pickerStyle(.segmented)

      ForEach(config.predicates.indices, id: \.self) { index in
        PredicateRow(predicate: predicateBinding(index)) {
          config.predicates.remove(at: index)
        }
      }

      Menu(L10n.Automations.conditionAdd) {
        ForEach(AutomationPredicate.editableTypes, id: \.self) { type in
          Button(AutomationPredicate.typeDisplayName(type)) {
            if let predicate = AutomationPredicate.makeDefault(type: type) {
              config.predicates.append(predicate)
            }
          }
        }
      }
      .fixedSize()
    } header: {
      Text(L10n.Automations.conditionHeader)
    }

    Section {
      Picker(L10n.Automations.conditionOtherwiseLabel, selection: otherwiseIsSkip) {
        Text(L10n.Automations.conditionOtherwiseStop).tag(false)
        Text(L10n.Automations.conditionOtherwiseSkip).tag(true)
      }
      if case .skip(let count) = config.otherwise {
        Stepper(value: skipCount, in: 1...max(1, Automation.maxSteps)) {
          Text(L10n.Automations.conditionSkipCount(count))
        }
        if count > stepsAfter {
          Label(L10n.Automations.issueSkipRange, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }
    } footer: {
      Text(AutomationConditionText.sentence(config))
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func predicateBinding(_ index: Int) -> Binding<AutomationPredicate> {
    Binding(
      get: { config.predicates.indices.contains(index) ? config.predicates[index] : .hasText(contains: nil) },
      set: { if config.predicates.indices.contains(index) { config.predicates[index] = $0 } }
    )
  }

  private var otherwiseIsSkip: Binding<Bool> {
    Binding(
      get: { config.skipCount > 0 },
      set: { config.otherwise = $0 ? .skip(1) : .stop }
    )
  }

  private var skipCount: Binding<Int> {
    Binding(
      get: { max(1, config.skipCount) },
      set: { config.otherwise = .skip($0) }
    )
  }
}

/// One predicate: its type, values and a remove button.
private struct PredicateRow: View {
  @Binding var predicate: AutomationPredicate
  let onRemove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(AutomationPredicate.typeDisplayName(predicate.type))
          .font(.subheadline.weight(.medium))
        Spacer()
        Button(action: onRemove) {
          Image(systemName: "minus.circle")
        }
        .buttonStyle(.borderless)
        .help(L10n.Common.delete)
        .accessibilityLabel(L10n.Common.delete)
      }
      editor
    }
    .padding(.vertical, 2)
  }

  @ViewBuilder
  private var editor: some View {
    switch predicate {
    case .frontmostApp(let bundleIDs, let negate):
      AppListEditor(
        bundleIDs: Binding(get: { bundleIDs }, set: { predicate = .frontmostApp(bundleIDs: $0, negate: negate) }),
        negate: Binding(get: { negate }, set: { predicate = .frontmostApp(bundleIDs: bundleIDs, negate: $0) })
      )
    case .captureMode(let modes):
      MultiChoiceMenu(
        options: AutomationCaptureMode.allCases,
        selection: Binding(get: { modes }, set: { predicate = .captureMode($0) }),
        title: \.displayName
      )
    case .invocation(let invocations):
      MultiChoiceMenu(
        options: AutomationInvocation.conditionChoices,
        selection: Binding(get: { invocations }, set: { predicate = .invocation($0) }),
        title: \.displayName
      )
    case .fileKind(let kinds):
      MultiChoiceMenu(
        options: AutomationFileKind.allCases,
        selection: Binding(get: { kinds }, set: { predicate = .fileKind($0) }),
        title: \.displayName
      )
    case .pixelSize(let dimension, let comparison, let value):
      HStack {
        Picker("", selection: Binding(get: { dimension }, set: { predicate = .pixelSize(dimension: $0, comparison: comparison, value: value) })) {
          ForEach(AutomationDimension.allCases) { Text($0.displayName).tag($0) }
        }
        .labelsHidden()
        ComparisonPicker(selection: Binding(get: { comparison }, set: { predicate = .pixelSize(dimension: dimension, comparison: $0, value: value) }))
        TextField("", value: Binding(get: { value }, set: { predicate = .pixelSize(dimension: dimension, comparison: comparison, value: max(0, $0)) }), format: .number)
          .frame(width: 70)
          .labelsHidden()
        Text("px").foregroundStyle(.secondary)
      }
    case .fileSize(let comparison, let bytes):
      HStack {
        ComparisonPicker(selection: Binding(get: { comparison }, set: { predicate = .fileSize(comparison: $0, bytes: bytes) }))
        TextField("", value: Binding(get: { bytes / 1000 }, set: { predicate = .fileSize(comparison: comparison, bytes: max(0, $0) * 1000) }), format: .number)
          .frame(width: 80)
          .labelsHidden()
        Text("KB").foregroundStyle(.secondary)
      }
    case .hasText(let contains):
      TextField(
        L10n.Automations.conditionTextContainsPlaceholder,
        text: Binding(get: { contains ?? "" }, set: { predicate = .hasText(contains: $0.isEmpty ? nil : $0) })
      )
    case .unsupported:
      Text(L10n.Automations.unsupported).foregroundStyle(.secondary)
    }
  }
}

private struct ComparisonPicker: View {
  @Binding var selection: AutomationComparison

  var body: some View {
    Picker("", selection: $selection) {
      Text(L10n.Automations.comparisonGreater).tag(AutomationComparison.greaterThan)
      Text(L10n.Automations.comparisonLess).tag(AutomationComparison.lessThan)
    }
    .labelsHidden()
    .fixedSize()
  }
}

/// A menu of checkable options; the label lists what is selected.
private struct MultiChoiceMenu<Option: Hashable>: View {
  let options: [Option]
  @Binding var selection: [Option]
  let title: (Option) -> String

  init(options: [Option], selection: Binding<[Option]>, title: KeyPath<Option, String>) {
    self.options = options
    _selection = selection
    self.title = { $0[keyPath: title] }
  }

  var body: some View {
    Menu {
      ForEach(options, id: \.self) { option in
        Toggle(title(option), isOn: Binding(
          get: { selection.contains(option) },
          set: { isOn in
            if isOn {
              // Keep the menu's order, not the click order.
              selection = options.filter { selection.contains($0) || $0 == option }
            } else {
              selection.removeAll { $0 == option }
            }
          }
        ))
      }
    } label: {
      Text(selection.isEmpty ? L10n.Automations.conditionChoose : selection.map(title).joined(separator: ", "))
        .foregroundStyle(selection.isEmpty ? .orange : .primary)
    }
    .fixedSize()
  }
}

/// Apps a frontmost-app predicate matches: chips + "Add App" (running apps or /Applications).
struct AppListEditor: View {
  @Binding var bundleIDs: [String]
  @Binding var negate: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Picker("", selection: $negate) {
        Text(L10n.Automations.conditionAppIsLabel).tag(false)
        Text(L10n.Automations.conditionAppIsNotLabel).tag(true)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()

      ForEach(bundleIDs, id: \.self) { bundleID in
        HStack(spacing: 6) {
          if let icon = Self.icon(for: bundleID) {
            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
          }
          Text(AutomationConditionText.appName(for: bundleID))
          Text(bundleID).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
          Spacer()
          Button {
            bundleIDs.removeAll { $0 == bundleID }
          } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
          }
          .buttonStyle(.borderless)
          .accessibilityLabel(L10n.Common.delete)
        }
      }
      AppPickerMenu(title: L10n.Automations.conditionAddApp) { bundleID in
        if !bundleIDs.contains(bundleID) { bundleIDs.append(bundleID) }
      }
    }
  }

  static func icon(for bundleID: String) -> NSImage? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
  }
}

/// "Add App" menu: running regular apps, then "Choose…" for any installed app.
struct AppPickerMenu: View {
  let title: String
  let onPick: (String) -> Void

  var body: some View {
    Menu(title) {
      ForEach(Self.runningApps, id: \.bundleID) { app in
        Button(app.name) { onPick(app.bundleID) }
      }
      Divider()
      Button(L10n.Automations.chooseApp) {
        if let bundleID = Self.chooseApp() { onPick(bundleID) }
      }
    }
    .fixedSize()
  }

  private static var runningApps: [(name: String, bundleID: String)] {
    let own = Bundle.main.bundleIdentifier
    var seen = Set<String>()
    return NSWorkspace.shared.runningApplications
      .filter { $0.activationPolicy == .regular }
      .compactMap { app -> (String, String)? in
        guard let bundleID = app.bundleIdentifier, bundleID != own, seen.insert(bundleID).inserted else { return nil }
        return (app.localizedName ?? bundleID, bundleID)
      }
      .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
      .map { (name: $0.0, bundleID: $0.1) }
  }

  private static func chooseApp() -> String? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return Bundle(url: url)?.bundleIdentifier
  }
}

// MARK: - Run Automation

struct RunAutomationInspector: View {
  @Binding var config: AutomationRunAutomationConfig
  let excluding: UUID?
  @ObservedObject private var store = AutomationStore.shared

  var body: some View {
    Section {
      Picker(L10n.Automations.runAutomationTarget, selection: $config.automationID) {
        Text(L10n.Automations.conditionChoose).tag(UUID?.none)
        ForEach(candidates) { automation in
          Label(automation.displayName, systemImage: automation.symbol ?? automation.sourceSymbol)
            .tag(UUID?.some(automation.id))
        }
        if let id = config.automationID, store.automation(id: id) == nil {
          Text(L10n.Automations.unknownAutomation).tag(UUID?.some(id))
        }
      }
      if let id = config.automationID, let target = store.automation(id: id), !target.isEnabled {
        Label(L10n.Automations.runAutomationDisabledWarning, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
      }
    }
  }

  private var candidates: [Automation] {
    store.automations.filter { $0.id != excluding }
  }
}

// MARK: - Ask

struct AskInspector: View {
  @Binding var config: AutomationAskConfig
  let excluding: UUID?
  @ObservedObject private var store = AutomationStore.shared

  var body: some View {
    Section {
      TextField(L10n.Automations.askPromptLabel, text: $config.prompt, prompt: Text(L10n.Automations.askPromptPlaceholder))
    }

    Section {
      ForEach(Array(config.choices.enumerated()), id: \.element) { index, choice in
        HStack(spacing: 8) {
          Text("\(index + 1)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 16)
          Image(systemName: symbol(for: choice))
            .frame(width: 18)
          Text(AutomationDisplay.choiceTitle(choice))
            .foregroundStyle(isMissing(choice) ? .orange : .primary)
          Spacer()
          Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
            .disabled(index == 0)
            .accessibilityLabel(L10n.Automations.moveUp)
          Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
            .disabled(index == config.choices.count - 1)
            .accessibilityLabel(L10n.Automations.moveDown)
          Button { config.choices.remove(at: index) } label: { Image(systemName: "minus.circle") }
            .accessibilityLabel(L10n.Common.delete)
        }
        .buttonStyle(.borderless)
      }

      Menu(L10n.Automations.askAddChoice) {
        ForEach(store.automations.filter { $0.id != excluding && !config.choices.contains(.automation($0.id)) }) { automation in
          Button(automation.displayName) { add(.automation(automation.id)) }
        }
        Divider()
        Button(L10n.Automations.askContinue) { add(.continueRun) }
          .disabled(config.choices.contains(.continueRun))
        Button(L10n.Automations.askStop) { add(.stopRun) }
          .disabled(config.choices.contains(.stopRun))
      }
      .fixedSize()
      .disabled(config.choices.count >= AutomationAskConfig.maxChoices)
    } header: {
      Text(L10n.Automations.askChoicesHeader)
    } footer: {
      Text(L10n.Automations.askChoicesFooter)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func add(_ choice: AutomationAskChoice) {
    guard !config.choices.contains(choice) else { return }
    config.choices.append(choice)
  }

  private func move(_ index: Int, by offset: Int) {
    let target = index + offset
    guard config.choices.indices.contains(target) else { return }
    config.choices.swapAt(index, target)
  }

  private func symbol(for choice: AutomationAskChoice) -> String {
    switch choice {
    case .automation(let id):
      guard let automation = store.automation(id: id) else { return "questionmark.circle" }
      return automation.symbol ?? automation.sourceSymbol
    case .continueRun: return "arrow.down.circle"
    case .stopRun: return "stop.circle"
    }
  }

  private func isMissing(_ choice: AutomationAskChoice) -> Bool {
    guard case .automation(let id) = choice else { return false }
    return store.automation(id: id) == nil
  }
}
