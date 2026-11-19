//
//  PreferencesQuickAccessOptimizePresetsSection.swift
//  Snapzy
//
//  Quick Access settings section that lists, adds, edits and deletes the Optimize
//  presets shown in the card's Optimize menu.
//

import SwiftUI

struct QuickAccessOptimizePresetsSection: View {
  @ObservedObject private var store = QuickAccessOptimizePresetStore.shared
  @State private var editing: EditingPreset?

  /// A preset open in the editor sheet; `isNew` until it is first saved.
  private struct EditingPreset: Identifiable {
    var preset: QuickAccessOptimizePreset
    let isNew: Bool
    var id: UUID { preset.id }
  }

  var body: some View {
    Section {
      if store.presets.isEmpty {
        Text(L10n.PreferencesQuickAccess.optimizePresetsEmpty)
          .foregroundColor(.secondary)
      }

      ForEach(store.presets) { preset in
        HStack(spacing: 12) {
          Image(systemName: "slider.horizontal.3")
            .foregroundColor(.secondary)
            .frame(width: 20)

          VStack(alignment: .leading, spacing: 2) {
            Text(preset.name)
              .fontWeight(.medium)
            Text(preset.settings.summary())
              .font(.caption)
              .foregroundColor(.secondary)
              .monospacedDigit()
          }

          Spacer()

          Button {
            editing = EditingPreset(preset: preset, isNew: false)
          } label: {
            Image(systemName: "pencil")
          }
          .buttonStyle(.borderless)
          .help(L10n.Common.edit)

          Button {
            store.deletePreset(id: preset.id)
          } label: {
            Image(systemName: "trash")
          }
          .buttonStyle(.borderless)
          .help(L10n.Common.delete)
        }
        .padding(.vertical, 2)
      }
      .onMove { store.movePresets(fromOffsets: $0, toOffset: $1) }

      Button {
        editing = EditingPreset(
          preset: QuickAccessOptimizePreset(name: "", settings: store.lastCustomSettings),
          isNew: true
        )
      } label: {
        Label(L10n.PreferencesQuickAccess.addOptimizePreset, systemImage: "plus")
      }
      .buttonStyle(.borderless)
    } header: {
      Text(L10n.PreferencesQuickAccess.optimizePresetsSection)
    } footer: {
      Text(L10n.PreferencesQuickAccess.optimizePresetsDescription)
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .sheet(item: $editing) { editing in
      QuickAccessOptimizePresetEditorSheet(
        preset: editing.preset,
        isNew: editing.isNew,
        onSave: { preset in
          if editing.isNew {
            store.addPreset(name: preset.name, settings: preset.settings)
          } else {
            store.updatePreset(preset)
          }
          self.editing = nil
        },
        onCancel: { self.editing = nil }
      )
    }
  }
}

private struct QuickAccessOptimizePresetEditorSheet: View {
  @State var preset: QuickAccessOptimizePreset
  let isNew: Bool
  let onSave: (QuickAccessOptimizePreset) -> Void
  let onCancel: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(isNew ? L10n.PreferencesQuickAccess.newOptimizePresetTitle : L10n.PreferencesQuickAccess.editOptimizePresetTitle)
        .font(.headline)

      HStack(spacing: 10) {
        Text(L10n.PreferencesQuickAccess.optimizePresetNameLabel)
          .font(.system(size: 12))
          .frame(width: 70, alignment: .leading)
        TextField(L10n.QuickAccess.optimizePresetNamePlaceholder, text: $preset.name)
          .textFieldStyle(.roundedBorder)
      }

      QuickAccessOptimizeSettingsForm(settings: $preset.settings)

      HStack {
        Spacer()
        Button(L10n.Common.cancel, action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button(L10n.Common.save) { onSave(preset) }
          .keyboardShortcut(.defaultAction)
          .disabled(preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 440)
  }
}
