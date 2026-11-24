//
//  PreferencesAutomationsSettingsView.swift
//  Snapzy
//
//  Settings → Automations: list, shortcut binding, edit / duplicate / delete,
//  and restoring the built-in presets.
//

import SwiftUI

private struct AutomationEditorDraft: Identifiable {
  var automation: Automation
  let isNew: Bool
  var id: UUID { automation.id }
}

struct AutomationsSettingsView: View {
  @ObservedObject private var store = AutomationStore.shared
  @ObservedObject private var cloudManager = CloudManager.shared
  @ObservedObject private var navigation = AutomationSettingsNavigation.shared
  @ObservedObject private var importer = AutomationImportCoordinator.shared
  @State private var editorDraft: AutomationEditorDraft?
  @State private var isGalleryPresented = false
  @State private var pendingDelete: Automation?
  @State private var validationIssues: [UUID: ShortcutValidationIssue] = [:]
  @AppStorage(PreferencesKeys.automationsEditorStyle) private var editorStyle: AutomationEditorStyle = .list

  var body: some View {
    Form {
      Section {
      } header: {
        VStack(spacing: 4) {
          PreferencesPageHero(tab: .automations, subtitle: L10n.Automations.heroSubtitle)
          LiquidGlassSegmentedControl(
            items: AutomationSettingsNavigation.Page.allCases,
            selection: $navigation.page
          ) { page in
            Text(title(for: page))
              .lineLimit(1)
              .frame(minWidth: 96)
          }
          .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .textCase(nil)
      }

      if navigation.page == .activity {
        AutomationActivitySection()
      } else {
        AutomationSystemDefaultSection()
        automationsSection
        AutomationAdvancedSection()
        AutomationSecretsSection()
      }
    }
    .formStyle(.grouped)
    .sheet(isPresented: $isGalleryPresented) {
      AutomationGallerySheet(onClose: { isGalleryPresented = false })
    }
    .sheet(item: $importer.pending) { request in
      AutomationImportSheet(
        request: request,
        onImport: { importer.importSelected($0) },
        onCancel: { importer.pending = nil }
      )
    }
    .sheet(item: $editorDraft) { draft in
      AutomationEditorSheet(
        automation: draft.automation,
        isNew: draft.isNew,
        isCloudConfigured: cloudManager.isConfigured,
        onSave: { saved in
          if draft.isNew {
            store.add(saved)
          } else {
            store.update(saved)
          }
          validationIssues[saved.id] = nil
          editorDraft = nil
        },
        onCancel: { editorDraft = nil },
        onOpenInCanvas: { current in
          editorDraft = nil
          AutomationEditorRouter.openCanvas(current, isNew: draft.isNew)
        }
      )
    }
    .onAppear(perform: consumeListEditorRequest)
    .onChange(of: navigation.listEditorRequest) { _ in consumeListEditorRequest() }
    .alert(
      pendingDelete.map { L10n.Automations.deleteConfirmTitle($0.displayName) } ?? "",
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }
      ),
      presenting: pendingDelete
    ) { automation in
      Button(L10n.Common.delete, role: .destructive) {
        store.delete(id: automation.id)
        validationIssues[automation.id] = nil
        pendingDelete = nil
      }
      Button(L10n.Common.cancel, role: .cancel) {
        pendingDelete = nil
      }
    } message: { _ in
      Text(L10n.Automations.deleteConfirmMessage)
    }
  }

  @ViewBuilder
  private var automationsSection: some View {
      Section {
        if store.automations.isEmpty {
          Text(L10n.Automations.emptyList)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
        }

        ForEach(store.automations) { automation in
          AutomationRow(
            automation: automation,
            isCloudConfigured: cloudManager.isConfigured,
            canDuplicate: store.canAdd,
            validationIssue: validationIssues[automation.id],
            onToggle: { setEnabled($0, for: automation) },
            onShortcutChanged: { handleShortcutChange($0, for: automation.id) },
            alternateEditor: editorStyle == .canvas ? .list : .canvas,
            onEdit: { edit(automation, isNew: false) },
            onEditAlternate: { edit(automation, isNew: false, style: editorStyle == .canvas ? .list : .canvas) },
            onDuplicate: { store.duplicate(id: automation.id) },
            onExport: { AutomationExporter.export([automation], suggestedName: automation.displayName) },
            onCopyTOML: { AutomationExporter.copyTOML(automation) },
            onDelete: { pendingDelete = automation }
          )
        }
        .onMove { store.move(fromOffsets: $0, toOffset: $1) }
      } header: {
        HStack(alignment: .center, spacing: 12) {
          VStack(alignment: .leading, spacing: 2) {
            Text(L10n.Automations.listTitle)
            Text(L10n.Automations.listDescription)
              .font(.caption)
              .fontWeight(.regular)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 8)
          Picker(L10n.Automations.editorStyleLabel, selection: $editorStyle) {
            ForEach(AutomationEditorStyle.allCases) { style in
              Label(style.title, systemImage: style.symbol).tag(style)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .fixedSize()
          .help(L10n.Automations.editorStyleHelp)
          .accessibilityLabel(L10n.Automations.editorStyleLabel)
        }
        .textCase(nil)
      } footer: {
        HStack(spacing: 12) {
          Button {
            edit(makeNewAutomation(), isNew: true)
          } label: {
            Label(L10n.Automations.newButton, systemImage: "plus")
          }
          .buttonStyle(.liquidGlass(emphasis: .secondary, capsule: true))
          .fixedSize()
          .disabled(!store.canAdd)

          // Milestone 6: the gallery replaces "Restore built-in".
          Button(L10n.Automations.galleryButton) { isGalleryPresented = true }
            .buttonStyle(.link)

          Menu {
            Button(L10n.Automations.importButton) { AutomationExporter.chooseFileToImport() }
            Button(L10n.Automations.exportAll) {
              AutomationExporter.export(store.automations, suggestedName: L10n.Automations.pageAutomations)
            }
            .disabled(store.automations.isEmpty)
          } label: {
            Text(L10n.Automations.importButton)
          } primaryAction: {
            AutomationExporter.chooseFileToImport()
          }
          .menuStyle(.borderlessButton)
          .fixedSize()

          Spacer()

          if !store.canAdd {
            Text(L10n.Automations.limitReached(AutomationStore.maxAutomations))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.top, 4)
      }
  }

  private func title(for page: AutomationSettingsNavigation.Page) -> String {
    switch page {
    case .automations: L10n.Automations.pageAutomations
    case .activity: L10n.Automations.pageActivity
    }
  }

  /// Opens the editor picked in the header (or `style`) on `automation`.
  private func edit(_ automation: Automation, isNew: Bool, style: AutomationEditorStyle? = nil) {
    switch style ?? editorStyle {
    case .list:
      editorDraft = AutomationEditorDraft(automation: automation, isNew: isNew)
    case .canvas:
      AutomationEditorRouter.openCanvas(automation, isNew: isNew)
    }
  }

  private func consumeListEditorRequest() {
    guard let request = navigation.listEditorRequest else { return }
    navigation.listEditorRequest = nil
    editorDraft = AutomationEditorDraft(automation: request.automation, isNew: request.isNew)
  }

  private func makeNewAutomation() -> Automation {
    Automation(
      name: "",
      source: .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false)),
      steps: [AutomationStep(.copyImage), AutomationStep(.notify)]
    )
  }

  /// Re-enabling re-checks the shortcut: another automation or a global action may
  /// have taken the combo while this one was off. A clash leaves it unbound.
  private func setEnabled(_ enabled: Bool, for automation: Automation) {
    if enabled, let hotkey = automation.hotkey,
       case .reject(let issue) = ShortcutValidationService.shared.validateAutomationShortcut(hotkey, for: automation.id)
    {
      validationIssues[automation.id] = issue
      store.setHotkey(nil, id: automation.id)
    }
    store.setEnabled(enabled, id: automation.id)
  }

  private func handleShortcutChange(_ config: ShortcutConfig?, for id: UUID) -> Bool {
    switch ShortcutValidationService.shared.validateAutomationShortcut(config, for: id) {
    case .accept(let issue):
      validationIssues[id] = issue
      store.setHotkey(config, id: id)
      return true
    case .reject(let issue):
      validationIssues[id] = issue
      return false
    }
  }
}

// MARK: - Row

/// One automation: icon tile, name + summary (+ setup warning) on the left, and one
/// vertically centered cluster of controls on the right — shortcut field, on/off
/// switch, more menu — so every row lines up the same whatever its text height.
private struct AutomationRow: View {
  let automation: Automation
  let isCloudConfigured: Bool
  let canDuplicate: Bool
  let validationIssue: ShortcutValidationIssue?
  let onToggle: (Bool) -> Void
  let onShortcutChanged: (ShortcutConfig?) -> Bool
  /// The editor that is not the default; offered as "Open in …".
  let alternateEditor: AutomationEditorStyle
  let onEdit: () -> Void
  let onEditAlternate: () -> Void
  let onDuplicate: () -> Void
  let onExport: () -> Void
  let onCopyTOML: () -> Void
  let onDelete: () -> Void

  @State private var isHovering = false

  private var isEnabled: Binding<Bool> {
    Binding(get: { automation.isEnabled }, set: onToggle)
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      PreferencesSymbolTile(
        symbol: automation.symbol ?? automation.sourceSymbol,
        size: 30,
        tint: automation.isEnabled ? .blue : .graphite,
        duotone: true
      )
      .opacity(automation.isEnabled ? 1 : 0.55)

      details
        .frame(maxWidth: .infinity, alignment: .leading)

      controls
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .onHover { isHovering = $0 }
    .onTapGesture(count: 2) {
      guard !automation.hasUnsupportedSource else { return }
      onEdit()
    }
    .contextMenu { menuItems }
  }

  // MARK: Leading

  private var details: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(automation.displayName)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(automation.isEnabled ? Color.primary : Color.secondary)
        .lineLimit(1)

      HStack(alignment: .firstTextBaseline, spacing: 4) {
        if automation.externalInvocation {
          Image(systemName: "link")
            .imageScale(.small)
            .help(L10n.Automations.externalBadge)
            .accessibilityLabel(L10n.Automations.externalBadge)
        }
        Text(automation.summary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      .font(.system(size: 11))
      .foregroundStyle(.secondary)

      statusLine
    }
  }

  @ViewBuilder
  private var statusLine: some View {
    if automation.hasUnsupportedSource {
      warning(L10n.Automations.unsupported)
    } else if automation.needsReview {
      warningWithAction(L10n.Automations.reviewBadge, action: L10n.Automations.reviewButton, perform: onEdit)
    } else if automation.needsSetup {
      warningWithAction(L10n.Automations.needsSetupBadge, action: L10n.Automations.setUpButton, perform: onEdit)
    } else if automation.needsCloud && !isCloudConfigured {
      warningWithAction(L10n.Automations.cloudWarning, action: L10n.Automations.openCloudSettings) {
        PreferencesNavigationState.shared.select(.cloud)
      }
    }
  }

  private func warning(_ text: String) -> some View {
    Label {
      Text(text)
    } icon: {
      Image(systemName: "exclamationmark.triangle.fill")
        .imageScale(.small)
    }
    .font(.system(size: 11, weight: .medium))
    .foregroundStyle(.orange)
  }

  private func warningWithAction(_ text: String, action: String, perform: @escaping () -> Void) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      warning(text)
      Button(action, action: perform)
        .buttonStyle(.link)
        .font(.system(size: 11, weight: .medium))
    }
    .padding(.top, 2)
  }

  // MARK: Trailing

  private var controls: some View {
    HStack(alignment: .center, spacing: 10) {
      if automation.runsWithoutInput {
        ShortcutRecorderView(
          label: automation.displayName,
          shortcut: Binding(get: { automation.hotkey }, set: { _ in }),
          isEnabled: isEnabled,
          validationIssue: validationIssue,
          showsLabel: false,
          showsOptionsMenu: false,
          onShortcutChanged: onShortcutChanged
        )
        .fixedSize()
        .disabled(automation.hasUnsupportedSource)
      }

      Toggle("", isOn: isEnabled)
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
        .help(L10n.Common.enabled)
        .accessibilityLabel(L10n.Common.enabled)

      Menu {
        menuItems
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(isHovering ? Color.primary : Color.secondary)
          .frame(width: 24, height: 24)
          .background(
            Circle().fill(Color.primary.opacity(isHovering ? 0.08 : 0))
          )
          .contentShape(Circle())
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .help(L10n.Automations.moreActions)
      .accessibilityLabel(L10n.Automations.moreActions)
    }
    .animation(.easeOut(duration: 0.15), value: isHovering)
  }

  @ViewBuilder
  private var menuItems: some View {
    Button(L10n.Common.edit, action: onEdit)
      .disabled(automation.hasUnsupportedSource)
    Button(
      alternateEditor == .canvas ? L10n.Automations.canvasOpenInCanvas : L10n.Automations.canvasOpenInList,
      action: onEditAlternate
    )
    .disabled(automation.hasUnsupportedSource)
    Button(L10n.Automations.duplicate, action: onDuplicate)
      .disabled(!canDuplicate || automation.hasUnsupportedSource)
    Divider()
    Button(L10n.Automations.exportButton, action: onExport)
      .disabled(automation.hasUnsupportedSource)
    Button(L10n.Automations.copyTOML, action: onCopyTOML)
    Divider()
    Button(L10n.Common.delete, role: .destructive, action: onDelete)
  }
}
