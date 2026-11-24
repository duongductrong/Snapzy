//
//  AutomationSystemDefaultViews.swift
//  Snapzy
//
//  Milestone 6: the two default after-capture automations in Settings.
//  - `AutomationSystemDefaultSection`: top of Settings → Automations.
//  - `AfterCaptureCustomizeRow`: under the After Capture matrix in Capture settings.
//  Both open the full editor (source and triggers hidden) and offer
//  "Reset to Simple" once a pipeline is beyond what the matrix can show.
//

import SwiftUI

extension CaptureType: Identifiable {
  public var id: String { rawValue }
}

/// Presents the editor for a default automation and asks before a reset.
private struct SystemDefaultEditorModifier: ViewModifier {
  @Binding var editing: CaptureType?
  @Binding var resetting: CaptureType?
  @ObservedObject private var store = AutomationStore.shared
  @ObservedObject private var cloudManager = CloudManager.shared

  func body(content: Content) -> some View {
    content
      .sheet(item: $editing) { type in
        AutomationEditorSheet(
          automation: store.defaultAutomation(for: type),
          isNew: false,
          isCloudConfigured: cloudManager.isConfigured,
          onSave: { saved in
            store.update(saved)
            editing = nil
          },
          onCancel: { editing = nil }
        )
      }
      .alert(
        L10n.Automations.systemDefaultReset,
        isPresented: Binding(get: { resetting != nil }, set: { if !$0 { resetting = nil } }),
        presenting: resetting
      ) { type in
        Button(L10n.Automations.systemDefaultReset, role: .destructive) {
          store.resetDefaultAutomation(for: type)
          resetting = nil
        }
        Button(L10n.Common.cancel, role: .cancel) { resetting = nil }
      } message: { _ in
        Text(L10n.Automations.systemDefaultResetConfirm)
      }
  }
}

extension View {
  func systemDefaultEditor(editing: Binding<CaptureType?>, resetting: Binding<CaptureType?>) -> some View {
    modifier(SystemDefaultEditorModifier(editing: editing, resetting: resetting))
  }
}

extension Automation {
  /// "Copy file → Quick Access" for a default automation; "Save only" when it has no step.
  var systemDefaultSummary: String {
    let steps = activeActions.map(\.kind.displayName)
    return steps.isEmpty ? L10n.Automations.systemDefaultNoSteps : steps.joined(separator: " → ")
  }
}

/// Settings → Automations: "Default after capture" with one row per capture type.
struct AutomationSystemDefaultSection: View {
  @ObservedObject private var store = AutomationStore.shared
  @State private var editing: CaptureType?
  @State private var resetting: CaptureType?

  var body: some View {
    Section {
      ForEach(CaptureType.allCases) { type in
        row(store.defaultAutomation(for: type), type: type)
      }
    } header: {
      Text(L10n.Automations.systemDefaultSection)
    } footer: {
      Text(L10n.Automations.systemDefaultSectionFooter)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .systemDefaultEditor(editing: $editing, resetting: $resetting)
  }

  private func row(_ automation: Automation, type: CaptureType) -> some View {
    HStack(spacing: 12) {
      PreferencesSymbolTile(symbol: automation.symbol ?? "camera.viewfinder", size: 28, duotone: true)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(automation.displayName)
          if automation.isCustomizedSystemDefault {
            customBadge
          }
        }
        Text(automation.systemDefaultSummary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer()
      if automation.isCustomizedSystemDefault {
        Button(L10n.Automations.systemDefaultReset) { resetting = type }
          .buttonStyle(.borderless)
      }
      Button(L10n.Automations.systemDefaultEdit) { editing = type }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }

  private var customBadge: some View {
    Text(L10n.Automations.systemDefaultCustomBadge)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 6)
      .padding(.vertical, 1)
      .background(Capsule().fill(Color.accentColor.opacity(0.15)))
      .foregroundStyle(Color.accentColor)
  }
}

/// Capture settings → After Capture: custom-pipeline notes and "Customize Pipeline…".
struct AfterCaptureCustomizeRow: View {
  @ObservedObject private var store = AutomationStore.shared
  @State private var editing: CaptureType?
  @State private var resetting: CaptureType?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(CaptureType.allCases.filter { store.defaultAutomation(for: $0).isCustomizedSystemDefault }) { type in
        HStack(spacing: 8) {
          Image(systemName: "slider.horizontal.3")
            .foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 1) {
            Text(L10n.Automations.systemDefaultCustomSummary(type.displayName))
            Text(store.defaultAutomation(for: type).systemDefaultSummary)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
          Spacer()
          Button(L10n.Automations.systemDefaultReset) { resetting = type }
            .buttonStyle(.borderless)
          Button(L10n.Automations.systemDefaultEdit) { editing = type }
        }
      }
      HStack {
        Spacer()
        Menu(L10n.Automations.systemDefaultCustomize) {
          ForEach(CaptureType.allCases) { type in
            Button(type.displayName) { editing = type }
          }
        }
        .fixedSize()
      }
    }
    .systemDefaultEditor(editing: $editing, resetting: $resetting)
  }
}
