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
  @State private var isRouteByAppPresented = false

  var body: some View {
    VStack(spacing: 0) {
      List(selection: $selection) {
        AutomationListRowLayout(symbol: "bolt.circle", title: L10n.Automations.triggersRow)
          .tag(AutomationEditorSelection.triggers)

        Section(L10n.Automations.stepsLabel) {
          ForEach($automation.steps) { $step in
            AutomationStepRow(
              step: $step,
              issue: issues.first { $0.stepID == step.id },
              isInSkipRange: skippableStepIDs.contains(step.id)
            )
              .tag(AutomationEditorSelection.step(step.id))
              .contextMenu { contextMenu(for: step.id) }
          }
          .onMove { automation.steps.move(fromOffsets: $0, toOffset: $1) }
          .onDelete { offsets in offsets.sorted(by: >).forEach { automation.removeStep(at: $0) } }
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
      Button {
        isRouteByAppPresented = true
      } label: {
        Image(systemName: "arrow.triangle.branch")
      }
      .help(L10n.Automations.routeByApp)
      .accessibilityLabel(L10n.Automations.routeByApp)
      .disabled(automation.steps.count + 3 > Automation.maxSteps)
      .sheet(isPresented: $isRouteByAppPresented) {
        AutomationRouteByAppSheet(
          maxSteps: Automation.maxSteps - automation.steps.count - 2,
          onInsert: insertRoute,
          onCancel: { isRouteByAppPresented = false }
        )
      }
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
      if let index = automation.steps.firstIndex(where: { $0.id == id }) { automation.removeStep(at: index) }
    }
  }

  /// Steps a condition's "Otherwise skip" can jump over (drawn with a bracket).
  private var skippableStepIDs: Set<UUID> {
    var ids = Set<UUID>()
    for (index, step) in automation.steps.enumerated() where step.isEnabled {
      guard case .condition(let config)? = step.action, config.skipCount > 0 else { continue }
      let range = (index + 1)..<min(automation.steps.count, index + 1 + config.skipCount)
      for skipped in range { ids.insert(automation.steps[skipped].id) }
    }
    return ids
  }

  /// `condition(app is …, else skip n) · steps · stop`, after the selection.
  private func insertRoute(bundleIDs: [String], kinds: [AutomationStepKind]) {
    isRouteByAppPresented = false
    let routed = kinds.map { AutomationStep($0.defaultAction) }
    let block = [AutomationStep(.condition(AutomationConditionConfig(
      predicates: [.frontmostApp(bundleIDs: bundleIDs, negate: false)],
      otherwise: .skip(routed.count + 1)
    )))] + routed + [AutomationStep(.stop)]
    guard automation.steps.count + block.count <= Automation.maxSteps else { return }
    let at = selectedIndex.map { $0 + 1 } ?? automation.steps.count
    automation.steps.insert(contentsOf: block, at: at)
    selection = .step(block[0].id)
  }

  private var selectedIndex: Int? {
    guard case .step(let id)? = selection else { return nil }
    return automation.steps.firstIndex { $0.id == id }
  }

  private func add(_ kind: AutomationStepKind) {
    let step = AutomationStep(kind.defaultAction)
    if let index = selectedIndex {
      automation.insertStep(step, at: index + 1)
    } else {
      automation.steps.append(step)
    }
    selection = .step(step.id)
  }

  private func duplicate(_ id: UUID) {
    guard let index = automation.steps.firstIndex(where: { $0.id == id }) else { return }
    var copy = automation.steps[index]
    copy.id = UUID()
    automation.insertStep(copy, at: index + 1)
    selection = .step(copy.id)
  }

  private func deleteSelected() {
    guard let index = selectedIndex else { return }
    automation.removeStep(at: index)
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

/// Shared icon + title geometry so the "Source & Triggers" row and the step rows
/// put their icons and titles on the same columns.
private struct AutomationListRowLayout<Trailing: View>: View {
  let symbol: String
  let title: String
  var subtitle: String? = nil
  var isActive = true
  @ViewBuilder var trailing: () -> Trailing

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .medium))
        .frame(width: 20, alignment: .center)
        .foregroundStyle(isActive ? .primary : .tertiary)
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .foregroundStyle(isActive ? .primary : .secondary)
          .lineLimit(1)
        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 4)
      trailing()
    }
    .padding(.vertical, 3)
  }
}

extension AutomationListRowLayout where Trailing == EmptyView {
  init(symbol: String, title: String) {
    self.init(symbol: symbol, title: title, trailing: { EmptyView() })
  }
}

private struct AutomationStepRow: View {
  @Binding var step: AutomationStep
  let issue: AutomationChainIssue?
  var isInSkipRange = false

  var body: some View {
    HStack(spacing: 6) {
      if isInSkipRange {
        // Bracket: this step only runs when the condition above holds.
        Capsule()
          .fill(Color.accentColor.opacity(0.6))
          .frame(width: 3)
          .padding(.vertical, 2)
          .accessibilityHidden(true)
      }
      content
    }
    .accessibilityElement(children: .combine)
    .accessibilityHint(isInSkipRange ? L10n.Automations.stepInSkipRangeHint : "")
  }

  private var content: some View {
    AutomationListRowLayout(
      symbol: step.action?.kind.symbol ?? "questionmark.square.dashed",
      title: step.action?.kind.displayName ?? L10n.Automations.unsupported,
      subtitle: step.action?.configSummary,
      isActive: step.isEnabled
    ) {
      HStack(spacing: 6) {
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
