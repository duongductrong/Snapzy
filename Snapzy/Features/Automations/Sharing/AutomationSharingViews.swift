//
//  AutomationSharingViews.swift
//  Snapzy
//
//  Milestone 6: the recipe gallery, the import review sheet, and export
//  (file / TOML snippet) for Settings → Automations.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Trust badge

extension AutomationTrustTier {
  var displayName: String {
    switch self {
    case .local: L10n.Automations.trustLocal
    case .network: L10n.Automations.trustNetwork
    case .code: L10n.Automations.trustCode
    }
  }

  var symbol: String {
    switch self {
    case .local: "lock.laptopcomputer"
    case .network: "network"
    case .code: "terminal"
    }
  }

  var tint: Color {
    switch self {
    case .local: .green
    case .network: .blue
    case .code: .orange
    }
  }
}

struct AutomationBadge: View {
  let title: String
  let symbol: String
  let tint: Color

  var body: some View {
    Label(title, systemImage: symbol)
      .font(.caption2.weight(.medium))
      .labelStyle(.titleAndIcon)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Capsule().fill(tint.opacity(0.14)))
      .foregroundStyle(tint)
  }
}

// MARK: - Gallery

struct AutomationGallerySheet: View {
  @ObservedObject private var store = AutomationStore.shared
  let onClose: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(L10n.Automations.galleryTitle).font(.title3.weight(.semibold))
        Spacer()
      }
      .padding(16)
      Divider()
      Form {
        ForEach(AutomationRecipePersona.allCases) { persona in
          Section(persona.title) {
            ForEach(persona.presets, id: \.rawValue) { preset in
              row(preset)
            }
          }
        }
      }
      .formStyle(.grouped)
      Divider()
      HStack {
        if !store.canAdd {
          Text(L10n.Automations.limitReached(AutomationStore.maxAutomations))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button(L10n.Common.done, action: onClose)
          .keyboardShortcut(.defaultAction)
      }
      .padding(16)
    }
    .frame(width: 620, height: 600)
  }

  private func row(_ preset: AutomationPreset) -> some View {
    let sample = preset.makeAutomation(resolve: presetAutomationID)
    let isPresent = store.automations.contains { $0.presetID == preset.rawValue }
    return HStack(alignment: .top, spacing: 12) {
      PreferencesSymbolTile(symbol: preset.symbol, size: 30, duotone: true)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(preset.localizedName).fontWeight(.medium)
          AutomationBadge(title: sample.maxTrust.displayName, symbol: sample.maxTrust.symbol, tint: sample.maxTrust.tint)
        }
        Text(preset.galleryDescription)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Text(sample.activeActions.map(\.kind.displayName).joined(separator: " → "))
          .font(.caption)
          .foregroundStyle(.tertiary)
        if !sample.isEnabled {
          Text(L10n.Automations.galleryNeedsSetupNote)
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }
      Spacer()
      if isPresent {
        Text(L10n.Automations.galleryAdded)
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        Button(L10n.Automations.galleryAdd) { add(preset) }
          .disabled(!store.canAdd)
      }
    }
    .padding(.vertical, 4)
  }

  private func presetAutomationID(_ preset: AutomationPreset) -> UUID? {
    store.automations.first { $0.presetID == preset.rawValue }?.id
  }

  private func add(_ preset: AutomationPreset) {
    // Share Menu points at the presets already in the list; missing ones are left out.
    store.add(preset.makeAutomation(resolve: presetAutomationID))
  }
}

// MARK: - Import review

struct AutomationImportSheet: View {
  @State var request: AutomationImportRequest
  let onImport: (AutomationImportRequest) -> Void
  let onCancel: () -> Void
  @ObservedObject private var store = AutomationStore.shared

  private var selectedCount: Int {
    request.candidates.filter(\.isSelected).count
  }

  private var room: Int {
    AutomationStore.maxAutomations - store.automations.count
  }

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 2) {
        Text(L10n.Automations.importTitle).font(.title3.weight(.semibold))
        Text(request.origin.label).font(.caption).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      Divider()
      Form {
        Section {
          ForEach($request.candidates) { $candidate in
            row($candidate)
          }
        } footer: {
          VStack(alignment: .leading, spacing: 4) {
            if case .url = request.origin {
              Text(L10n.Automations.importDisabledNote)
            }
            if selectedCount > room {
              Text(L10n.Automations.importOverCap).foregroundStyle(.orange)
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
      Divider()
      HStack {
        Spacer()
        Button(L10n.Common.cancel, role: .cancel, action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button(L10n.Automations.importConfirm) { onImport(request) }
          .keyboardShortcut(.defaultAction)
          .disabled(selectedCount == 0 || room <= 0)
      }
      .padding(16)
    }
    .frame(width: 560, height: 480)
  }

  private func row(_ candidate: Binding<AutomationImportCandidate>) -> some View {
    let automation = candidate.wrappedValue.automation
    return Toggle(isOn: candidate.isSelected) {
      VStack(alignment: .leading, spacing: 4) {
        Text(automation.displayName).fontWeight(.medium)
        Text(automation.summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        HStack(spacing: 6) {
          AutomationBadge(title: automation.maxTrust.displayName, symbol: automation.maxTrust.symbol, tint: automation.maxTrust.tint)
          if automation.needsReview {
            AutomationBadge(title: L10n.Automations.importNeedsReview, symbol: "checkmark.shield", tint: .orange)
          }
          if automation.needsSetup {
            AutomationBadge(title: L10n.Automations.importNeedsSetup, symbol: "wrench.and.screwdriver", tint: .secondary)
          }
        }
      }
    }
    .toggleStyle(.checkbox)
    .padding(.vertical, 2)
  }
}

// MARK: - Export

@MainActor
enum AutomationExporter {
  /// Save panel for one or more automations as a `.snapzyautomation` file.
  static func export(_ automations: [Automation], suggestedName: String) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [AutomationRecipeCodec.contentType]
    panel.nameFieldStringValue = "\(suggestedName).\(AutomationRecipeCodec.fileExtension)"
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try AutomationRecipeCodec.encode(automations).write(to: url, options: .atomic)
      DiagnosticLogger.shared.log(.info, .action, "Automations exported", context: ["count": "\(automations.count)"])
    } catch {
      AppToastManager.shared.show(message: error.localizedDescription, style: .warning)
    }
  }

  /// Copies the automation as a `[automations.<id>]` config-file snippet.
  static func copyTOML(_ automation: Automation) {
    var writer = SimpleTOMLWriter()
    SnapzyConfigurationAutomationsCodec.write([automation], to: &writer)
    ClipboardHelper.copyText(writer.output)
    AppToastManager.shared.show(message: L10n.Automations.copiedTOML, style: .success)
  }

  /// Open panel for `.snapzyautomation` files.
  static func chooseFileToImport() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [AutomationRecipeCodec.contentType, .json]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    AutomationImportCoordinator.shared.open(fileURL: url)
  }
}
