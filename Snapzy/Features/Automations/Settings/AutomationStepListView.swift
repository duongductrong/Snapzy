//
//  AutomationStepListView.swift
//  Snapzy
//
//  Left pane of the editor: a "Source & Triggers" row, then the steps in run
//  order. Drag or ⌘↑ / ⌘↓ to reorder, ⌫ to delete, "+" to add.
//

import SwiftUI

struct AutomationStepListView: View {
  @Binding var automation: Automation
  @Binding var selection: AutomationEditorSelection?
  let issues: [AutomationChainIssue]

  var body: some View {
    VStack(spacing: 0) {
      List(selection: $selection) {
        Label(L10n.Automations.triggersRow, systemImage: "bolt.circle")
          .tag(AutomationEditorSelection.triggers)

        Section(L10n.Automations.stepsLabel) {
          ForEach($automation.steps) { $step in
            AutomationStepRow(step: $step, issue: issues.first { $0.stepID == step.id })
              .tag(AutomationEditorSelection.step(step.id))
              .contextMenu { contextMenu(for: step.id) }
          }
          .onMove { automation.steps.move(fromOffsets: $0, toOffset: $1) }
          .onDelete { automation.steps.remove(atOffsets: $0) }
        }
      }
      .listStyle(.sidebar)
      .onDeleteCommand(perform: deleteSelected)

      Divider()
      toolbar
    }
  }

  private var toolbar: some View {
    HStack(spacing: 4) {
      AutomationAddStepMenu(automation: automation, onAdd: add)
        .disabled(automation.steps.count >= Automation.maxSteps)
      Button(action: deleteSelected) {
        Image(systemName: "minus")
      }
      .help(L10n.Common.delete)
      .accessibilityLabel(L10n.Common.delete)
      .disabled(selectedIndex == nil)
      Spacer()
      Button { move(by: -1) } label: { Image(systemName: "chevron.up") }
        .keyboardShortcut(.upArrow, modifiers: .command)
        .help(L10n.Automations.moveUp)
        .accessibilityLabel(L10n.Automations.moveUp)
        .disabled(selectedIndex.map { $0 == 0 } ?? true)
      Button { move(by: 1) } label: { Image(systemName: "chevron.down") }
        .keyboardShortcut(.downArrow, modifiers: .command)
        .help(L10n.Automations.moveDown)
        .accessibilityLabel(L10n.Automations.moveDown)
        .disabled(selectedIndex.map { $0 >= automation.steps.count - 1 } ?? true)
    }
    .buttonStyle(.borderless)
    .padding(8)
  }

  @ViewBuilder
  private func contextMenu(for id: UUID) -> some View {
    Button(L10n.Automations.duplicate) { duplicate(id) }
      .disabled(automation.steps.count >= Automation.maxSteps)
    Button(L10n.Automations.moveUp) { selection = .step(id); move(by: -1) }
    Button(L10n.Automations.moveDown) { selection = .step(id); move(by: 1) }
    Divider()
    Button(L10n.Common.delete, role: .destructive) {
      automation.steps.removeAll { $0.id == id }
    }
  }

  private var selectedIndex: Int? {
    guard case .step(let id)? = selection else { return nil }
    return automation.steps.firstIndex { $0.id == id }
  }

  private func add(_ kind: AutomationStepKind) {
    let step = AutomationStep(kind.defaultAction)
    if let index = selectedIndex {
      automation.steps.insert(step, at: index + 1)
    } else {
      automation.steps.append(step)
    }
    selection = .step(step.id)
  }

  private func duplicate(_ id: UUID) {
    guard let index = automation.steps.firstIndex(where: { $0.id == id }) else { return }
    var copy = automation.steps[index]
    copy.id = UUID()
    automation.steps.insert(copy, at: index + 1)
    selection = .step(copy.id)
  }

  private func deleteSelected() {
    guard let index = selectedIndex else { return }
    automation.steps.remove(at: index)
    if automation.steps.indices.contains(index) {
      selection = .step(automation.steps[index].id)
    } else {
      selection = automation.steps.last.map { .step($0.id) } ?? .triggers
    }
  }

  private func move(by offset: Int) {
    guard let index = selectedIndex else { return }
    let target = index + offset
    guard automation.steps.indices.contains(target) else { return }
    automation.steps.swapAt(index, target)
  }
}

private struct AutomationStepRow: View {
  @Binding var step: AutomationStep
  let issue: AutomationChainIssue?

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: step.action?.kind.symbol ?? "questionmark.square.dashed")
        .frame(width: 18)
        .foregroundStyle(step.isEnabled ? .primary : .tertiary)
      VStack(alignment: .leading, spacing: 1) {
        Text(step.action?.kind.displayName ?? L10n.Automations.unsupported)
          .foregroundStyle(step.isEnabled ? .primary : .secondary)
          .lineLimit(1)
        if let summary = step.action?.configSummary, !summary.isEmpty {
          Text(summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 4)
      if let issue {
        Image(systemName: issue.blocksRun ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
          .foregroundStyle(issue.blocksRun ? .red : .orange)
          .help(issue.message)
          .accessibilityLabel(issue.message)
      }
      Toggle("", isOn: $step.isEnabled)
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.mini)
        .accessibilityLabel(L10n.Automations.stepEnabled)
    }
    .accessibilityElement(children: .combine)
  }
}

/// "+" menu grouped Transform / Deliver / Control. A step with nothing to work
/// on yet stays insertable; its row then shows the issue.
private struct AutomationAddStepMenu: View {
  let automation: Automation
  let onAdd: (AutomationStepKind) -> Void

  var body: some View {
    Menu {
      ForEach(AutomationStepGroup.allCases) { group in
        Section(group.title) {
          ForEach(group.kinds) { kind in
            Button {
              onAdd(kind)
            } label: {
              Label(kind.displayName, systemImage: kind.symbol)
            }
          }
        }
      }
    } label: {
      Image(systemName: "plus")
    }
    .menuIndicator(.hidden)
    .fixedSize()
    .help(L10n.Automations.addStep)
    .accessibilityLabel(L10n.Automations.addStep)
  }
}
