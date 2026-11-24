//
//  CaptureToolbarSettingsSection.swift
//  Snapzy
//
//  Capture settings → "Capture toolbar": the shortcut lives in Shortcuts;
//  here the buttons (show / hide, order, key), the double-click action and
//  "Also use the toolbar for Capture Area".
//

import SwiftUI

struct CaptureToolbarSettingsSection: View {
  @ObservedObject private var store = CaptureToolbarConfigurationStore.shared
  @ObservedObject private var automations = AutomationStore.shared

  private var configuration: CaptureToolbarConfiguration { store.configuration }

  private var toolbarAutomations: [Automation] {
    CaptureToolbarConfigurationStore.toolbarAutomations(automations)
  }

  var body: some View {
    Section {
      Toggle(L10n.CaptureToolbar.showForArea, isOn: binding(\.showsForAreaShortcut))

      Picker(L10n.CaptureToolbar.doubleClickLabel, selection: doubleClickBinding) {
        Text(L10n.CaptureToolbar.doubleClickNone).tag(String?.none)
        Divider()
        ForEach(CaptureToolbarBuiltin.allCases.filter { !$0.startsNewCapture }) { builtin in
          Text(builtin.displayName).tag(Optional(CaptureToolbarItem.builtin(builtin).token))
        }
        ForEach(toolbarAutomations) { automation in
          Text(automation.displayName).tag(Optional(CaptureToolbarItem.automation(automation.id).token))
        }
      }
    } header: {
      VStack(alignment: .leading, spacing: 2) {
        Text(L10n.CaptureToolbar.settingsSection)
        Text(L10n.CaptureToolbar.settingsDescription)
          .font(.caption)
          .fontWeight(.regular)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .textCase(nil)
    }

    Section {
      ForEach(Array(configuration.entries.enumerated()), id: \.element.item) { index, entry in
        row(entry, list: \.entries, index: index)
      }
      .onMove { move(\.entries, from: $0, to: $1) }
      ForEach(Array(automationRows.enumerated()), id: \.element.item) { index, entry in
        row(entry, list: \.automationEntries, index: index)
      }
      .onMove { move(\.automationEntries, from: $0, to: $1) }
    } header: {
      Text(L10n.CaptureToolbar.itemsHeader)
    } footer: {
      HStack(alignment: .top) {
        Text(L10n.CaptureToolbar.automationsNote)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer()
        Button(L10n.CaptureToolbar.resetButton) { store.reset() }
          .buttonStyle(.link)
      }
    }
  }

  /// Automation entries: stored ones first, new toolbar automations after.
  private var automationRows: [CaptureToolbarEntry] {
    let ids = toolbarAutomations.map(\.id)
    var rows = configuration.automationEntries.filter {
      if case .automation(let id) = $0.item { return ids.contains(id) }
      return false
    }
    for id in ids where !rows.contains(where: { $0.item == .automation(id) }) {
      rows.append(CaptureToolbarEntry(item: .automation(id)))
    }
    return rows
  }

  private func row(
    _ entry: CaptureToolbarEntry,
    list: WritableKeyPath<CaptureToolbarConfiguration, [CaptureToolbarEntry]>,
    index: Int
  ) -> some View {
    let controller = CaptureToolbarController.shared
    let clash = entry.accelerator.flatMap { key in
      (configuration.entries + automationRows).filter { $0.accelerator == key }.count > 1 ? key : nil
    }
    return HStack(spacing: 10) {
      Toggle("", isOn: Binding(
        get: { entry.isVisible },
        set: { value in mutate(list, entry) { $0.isVisible = value } }
      ))
      .labelsHidden()
      .toggleStyle(.checkbox)
      Image(systemName: controller.symbol(for: entry.item))
        .frame(width: 20)
        .foregroundStyle(.secondary)
      Text(controller.title(for: entry.item))
      Spacer()
      if clash != nil {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .help(L10n.CaptureToolbar.acceleratorTaken)
      }
      TextField(L10n.CaptureToolbar.acceleratorLabel, text: Binding(
        get: { entry.accelerator ?? "" },
        set: { value in mutate(list, entry) { $0.accelerator = CaptureToolbarEntry.normalizedAccelerator(String(value.suffix(1))) } }
      ))
      .labelsHidden()
      .multilineTextAlignment(.center)
      .frame(width: 32)
      .accessibilityLabel(L10n.CaptureToolbar.acceleratorLabel)
    }
  }

  // MARK: - Mutations

  private func mutate(
    _ list: WritableKeyPath<CaptureToolbarConfiguration, [CaptureToolbarEntry]>,
    _ entry: CaptureToolbarEntry,
    change: (inout CaptureToolbarEntry) -> Void
  ) {
    var copy = configuration
    if list == \CaptureToolbarConfiguration.automationEntries {
      // Materialize the automation rows shown (new ones aren't stored yet).
      copy.automationEntries = automationRows
    }
    guard let index = copy[keyPath: list].firstIndex(where: { $0.item == entry.item }) else { return }
    change(&copy[keyPath: list][index])
    // A key just typed wins: clear it from whichever button had it.
    if let key = copy[keyPath: list][index].accelerator {
      for other in [\CaptureToolbarConfiguration.entries, \CaptureToolbarConfiguration.automationEntries] {
        for otherIndex in copy[keyPath: other].indices
        where copy[keyPath: other][otherIndex].item != entry.item && copy[keyPath: other][otherIndex].accelerator == key {
          copy[keyPath: other][otherIndex].accelerator = nil
        }
      }
    }
    store.update(copy)
  }

  private func move(
    _ list: WritableKeyPath<CaptureToolbarConfiguration, [CaptureToolbarEntry]>,
    from source: IndexSet,
    to destination: Int
  ) {
    var copy = configuration
    if list == \CaptureToolbarConfiguration.automationEntries {
      copy.automationEntries = automationRows
    }
    copy[keyPath: list].move(fromOffsets: source, toOffset: destination)
    store.update(copy)
  }

  private func binding(_ keyPath: WritableKeyPath<CaptureToolbarConfiguration, Bool>) -> Binding<Bool> {
    Binding(
      get: { configuration[keyPath: keyPath] },
      set: { value in
        var copy = configuration
        copy[keyPath: keyPath] = value
        store.update(copy)
      }
    )
  }

  private var doubleClickBinding: Binding<String?> {
    Binding(
      get: { configuration.doubleClickAction?.token },
      set: { token in
        var copy = configuration
        copy.doubleClickAction = token.flatMap(CaptureToolbarItem.init(token:))
        store.update(copy)
      }
    )
  }
}
