//
//  PreferencesAISettingsView.swift
//  Snapzy
//
//  Settings › AI: who answers Ask in Annotate (Apple Intelligence, a custom
//  endpoint, an agent CLI), what each provider can do, and what leaves the Mac.
//

import AppKit
import SwiftUI

struct AISettingsView: View {
  @AppStorage(PreferencesKeys.annotateAgentProvider)
  private var providerValue = AgentProviderSelection.automatic.persistedValue
  @AppStorage(PreferencesKeys.annotateAgentSendImage) private var sendImage = true
  @AppStorage(PreferencesKeys.annotateAgentCLITimeout)
  private var cliTimeout = AnnotateAgentAISettings.defaultCLITimeout

  @ObservedObject private var endpointStore = CustomOCRModelStore.shared
  @ObservedObject private var detector = AnnotateAgentCLIDetector.shared
  @State private var appleStatus = AnnotateAgentAppleIntelligence.status
  @State private var consentCount = AnnotateAgentAISettings.consentedProviderCount()

  var body: some View {
    Form {
      Section {
      } header: {
        PreferencesPageHero(tab: .ai, subtitle: L10n.AnnotateAI.settingsHeroSubtitle)
      }

      providerSection
      appleSection
      endpointSection
      cliSection
      privacySection
    }
    .formStyle(.grouped)
    .onAppear {
      appleStatus = AnnotateAgentAppleIntelligence.status
      consentCount = AnnotateAgentAISettings.consentedProviderCount()
      detector.refresh(includeVersions: true)
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      // The user may have just turned Apple Intelligence on in System Settings.
      appleStatus = AnnotateAgentAppleIntelligence.status
    }
  }

  // MARK: - Provider

  private var providerSection: some View {
    Section(L10n.AnnotateAI.settingsProviderSection) {
      SettingRow(
        title: L10n.AnnotateAI.settingsProviderTitle,
        description: L10n.AnnotateAI.settingsProviderDescription
      ) {
        Picker("", selection: providerBinding) {
          Text(L10n.AnnotateAI.automatic)
            .tag(AgentProviderSelection.automatic.persistedValue)
          Text(verbatim: "Apple Intelligence")
            .tag(AgentProviderSelection.appleIntelligence.persistedValue)
          if !endpointStore.models.isEmpty {
            Divider()
            ForEach(endpointStore.models) { model in
              Text(verbatim: model.name)
                .tag(AgentProviderSelection.endpoint(model.id).persistedValue)
            }
          }
          Divider()
          ForEach(AnnotateAgentCLIKind.allCases) { kind in
            Text(verbatim: kind.displayName)
              .tag(AgentProviderSelection.cli(kind).persistedValue)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
      }

      if let warning = selectionWarning {
        Label {
          Text(warning)
            .font(.callout)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundColor(.orange)
        }
      }
    }
  }

  /// A removed endpoint reads as Automatic, like the resolver treats it.
  private var providerBinding: Binding<String> {
    Binding(
      get: {
        let selection = AgentProviderSelection(persistedValue: providerValue)
        if case .endpoint(let id) = selection, endpointStore.model(for: id) == nil {
          return AgentProviderSelection.automatic.persistedValue
        }
        return selection.persistedValue
      },
      set: { providerValue = $0 }
    )
  }

  /// Why the picked provider won't answer yet.
  private var selectionWarning: String? {
    switch AgentProviderSelection(persistedValue: providerBinding.wrappedValue) {
    case .automatic, .appleIntelligence:
      return appleStatus == .available ? nil : appleStatusText
    case .cli(let kind):
      guard detector.hasScanned, detector.installed[kind] == nil else { return nil }
      return L10n.AnnotateAI.cliNotInstalled(kind.displayName)
    case .endpoint:
      return nil
    }
  }

  // MARK: - Apple Intelligence

  private var appleSection: some View {
    Section(L10n.AnnotateAI.settingsAppleSection) {
      SettingRow(
        title: L10n.AnnotateAI.settingsAppleStatusTitle,
        description: appleStatusText,
        descriptionStyle: .subtitle
      ) {
        HStack(spacing: 8) {
          AISettingsStatusDot(isOn: appleStatus == .available)
          if appleStatus == .notEnabled || appleStatus == .modelNotReady {
            Button(L10n.AnnotateAI.settingsOpenSystemSettings) {
              AnnotateAgentAppleIntelligence.openSystemSettings()
            }
          }
        }
      }
    }
  }

  private var appleStatusText: String {
    switch appleStatus {
    case .available: L10n.AnnotateAI.settingsAppleAvailable
    case .unsupportedOS: L10n.AnnotateAI.settingsAppleUnsupportedOS
    case .deviceNotEligible: L10n.AnnotateAI.settingsAppleNotEligible
    case .notEnabled: L10n.AnnotateAI.settingsAppleNotEnabled
    case .modelNotReady: L10n.AnnotateAI.settingsAppleNotReady
    }
  }

  // MARK: - Endpoints

  private var endpointSection: some View {
    Section {
      if endpointStore.models.isEmpty {
        Text(L10n.AnnotateAI.settingsEndpointsEmpty)
          .font(.callout)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.vertical, 6)
      }
      ForEach(endpointStore.models) { model in
        AISettingsEndpointRow(model: model)
      }
    } header: {
      AISettingsSectionHeader(title: L10n.AnnotateAI.settingsEndpointsSection) {
        Button(L10n.AnnotateAI.settingsManageEndpoints) { Self.openEndpointList() }
          .buttonStyle(.borderless)
          .font(.caption)
      }
    } footer: {
      AISettingsFooter(text: L10n.AnnotateAI.settingsEndpointsFooter)
    }
  }

  /// The endpoint list lives in Capture › OCR (shared with OCR and Translate).
  private static func openEndpointList() {
    PreferencesNavigationState.shared.reveal(
      PreferencesSearchEntry(
        .capture,
        section: L10n.PreferencesCapture.ocrModelSection,
        title: L10n.PreferencesCapture.ocrModelAddCustom,
        anchored: false
      ).inPane("ocr")
    )
  }

  // MARK: - Agent CLIs

  private var cliSection: some View {
    Section {
      ForEach(AnnotateAgentCLIKind.allCases) { kind in
        AISettingsCLIRow(
          kind: kind,
          path: detector.installed[kind],
          version: detector.versions[kind],
          hasScanned: detector.hasScanned,
          onChange: { detector.refresh(force: true, includeVersions: true) }
        )
      }

      Label {
        Text(L10n.AnnotateAI.settingsCLIWarning)
          .font(.callout)
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } icon: {
        Image(systemName: "exclamationmark.shield")
          .foregroundColor(.secondary)
      }
    } header: {
      AISettingsSectionHeader(title: L10n.AnnotateAI.settingsCLISection) {
        if detector.isScanning {
          ProgressView().controlSize(.small)
        }
        Button(L10n.AnnotateAI.settingsRefresh) {
          detector.refresh(force: true, includeVersions: true, reloadShellPath: true)
          for kind in AnnotateAgentCLIKind.allCases {
            AnnotateAgentCLIModelCatalogStore.shared.refresh(kind, executable: detector.installed[kind], force: true)
          }
        }
          .buttonStyle(.borderless)
          .font(.caption)
          .disabled(detector.isScanning)
      }
    } footer: {
      AISettingsFooter(text: L10n.AnnotateAI.settingsCLIFooter)
    }
  }

  // MARK: - Privacy

  private var privacySection: some View {
    Section(L10n.AnnotateAI.settingsPrivacySection) {
      SettingRow(
        title: L10n.AnnotateAI.settingsSendImageTitle,
        description: L10n.AnnotateAI.settingsSendImageDescription
      ) {
        Toggle("", isOn: $sendImage)
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.small)
      }

      SettingRow(
        title: L10n.AnnotateAI.settingsTimeoutTitle,
        description: L10n.AnnotateAI.settingsTimeoutDescription
      ) {
        Picker("", selection: timeoutBinding) {
          ForEach(timeoutChoices, id: \.self) { seconds in
            Text(Self.durationText(seconds)).tag(seconds)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
      }

      SettingRow(
        title: L10n.AnnotateAI.settingsConsentTitle,
        description: L10n.AnnotateAI.settingsConsentDescription
      ) {
        HStack(spacing: 10) {
          Text(L10n.AnnotateAI.settingsConsentCount("\(consentCount)"))
            .font(.callout)
            .foregroundColor(.secondary)
          Button(L10n.AnnotateAI.settingsConsentReset) {
            AnnotateAgentAISettings.resetConsents()
            consentCount = AnnotateAgentAISettings.consentedProviderCount()
          }
          .disabled(consentCount == 0)
        }
      }
    }
  }

  /// A value set in the config file that isn't one of the presets stays selectable.
  private var timeoutChoices: [TimeInterval] {
    let current = AnnotateAgentAISettings.cliTimeout()
    return (AnnotateAgentAISettings.cliTimeoutChoices + [current]).reduce(into: []) {
      if !$0.contains($1) { $0.append($1) }
    }.sorted()
  }

  private var timeoutBinding: Binding<TimeInterval> {
    Binding(
      get: { cliTimeout > 0 ? cliTimeout : AnnotateAgentAISettings.defaultCLITimeout },
      set: { cliTimeout = $0 }
    )
  }

  static func durationText(_ seconds: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = seconds >= 60 && seconds.truncatingRemainder(dividingBy: 60) == 0 ? [.minute] : [.minute, .second]
    formatter.unitsStyle = .short
    return formatter.string(from: seconds) ?? "\(Int(seconds))s"
  }
}

// MARK: - Endpoint row

private struct AISettingsEndpointRow: View {
  let model: CustomOCRModel
  @State private var capabilities: AgentEndpointCapabilities
  @State private var isTesting = false
  @State private var errorMessage: String?

  init(model: CustomOCRModel) {
    self.model = model
    _capabilities = State(initialValue: AgentEndpointCapabilityStore(defaults: .standard).capabilities(for: model))
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: "network")
        .foregroundColor(.secondary)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 3) {
        Text(verbatim: model.name)
          .fontWeight(.medium)
        Text(verbatim: model.modelIdentifier)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
        if let errorMessage {
          Text(errorMessage)
            .font(.caption)
            .foregroundColor(.red)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Spacer(minLength: 8)

      AISettingsCapabilityBadge(title: L10n.AnnotateAI.settingsCapabilityTools, value: capabilities.supportsTools)
      AISettingsCapabilityBadge(title: L10n.AnnotateAI.settingsCapabilityVision, value: capabilities.supportsVision)

      Button(isTesting ? L10n.AnnotateAI.settingsTesting : L10n.AnnotateAI.settingsTest) {
        test()
      }
      .disabled(isTesting)
    }
    .help(model.baseURL)
    .onChange(of: model) { updated in
      capabilities = AgentEndpointCapabilityStore(defaults: .standard).capabilities(for: updated)
      errorMessage = nil
    }
    // A prompt in an Annotate window may learn capabilities while this page is open.
    .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
      let stored = AgentEndpointCapabilityStore(defaults: .standard).capabilities(for: model)
      if stored != capabilities { capabilities = stored }
    }
  }

  private func test() {
    isTesting = true
    errorMessage = nil
    Task {
      switch await AnnotateAgentEndpointProbe.run(model) {
      case .finished(let result):
        capabilities = result
      case .failed(let message):
        errorMessage = message
      }
      isTesting = false
    }
  }
}

private struct AISettingsCapabilityBadge: View {
  let title: String
  let value: Bool?

  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: symbol)
        .font(.system(size: 9, weight: .bold))
      Text(title)
        .font(.system(size: 10, weight: .medium))
    }
    .foregroundColor(tint)
    .padding(.horizontal, 6)
    .frame(height: 18)
    .background(Capsule(style: .continuous).fill(tint.opacity(0.12)))
    .help("\(title): \(stateText)")
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(title): \(stateText)")
  }

  private var symbol: String {
    switch value {
    case true?: "checkmark"
    case false?: "xmark"
    case nil: "questionmark"
    }
  }

  private var tint: Color {
    switch value {
    case true?: .green
    case false?: .orange
    case nil: .secondary
    }
  }

  private var stateText: String {
    switch value {
    case true?: L10n.AnnotateAI.settingsCapabilitySupported
    case false?: L10n.AnnotateAI.settingsCapabilityUnsupported
    case nil: L10n.AnnotateAI.settingsCapabilityUnknown
    }
  }
}

// MARK: - CLI row

private struct AISettingsCLIRow: View {
  let kind: AnnotateAgentCLIKind
  let path: String?
  let version: String?
  let hasScanned: Bool
  let onChange: () -> Void

  @ObservedObject private var catalog = AnnotateAgentCLIModelCatalogStore.shared
  @State private var isExpanded = false
  @State private var model: String
  @State private var effort: String
  @State private var customPath: String
  /// "Custom…" picked, before anything is typed.
  @State private var isCustomModel = false

  init(kind: AnnotateAgentCLIKind, path: String?, version: String?, hasScanned: Bool, onChange: @escaping () -> Void) {
    self.kind = kind
    self.path = path
    self.version = version
    self.hasScanned = hasScanned
    self.onChange = onChange
    _model = State(initialValue: UserDefaults.standard.string(forKey: kind.modelDefaultsKey) ?? "")
    _effort = State(initialValue: UserDefaults.standard.string(forKey: kind.effortDefaultsKey) ?? "")
    _customPath = State(initialValue: UserDefaults.standard.string(forKey: kind.pathDefaultsKey) ?? "")
  }

  private static let customTag = "\u{0}custom"

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      Picker(selection: modelSelection) {
        Text(L10n.AnnotateAI.settingsCLIModelDefault).tag("")
        if let current = unlistedModel {
          Text(verbatim: current).tag(current)
        }
        if catalog.loading.contains(kind) && options.isEmpty {
          Divider()
          Text(L10n.AnnotateAI.settingsCLIModelLoading).tag("\u{0}loading").disabled(true)
        } else if !options.isEmpty {
          ForEach(groupedOptions, id: \.0) { group, items in
            if group.isEmpty {
              Divider()
              ForEach(items) { Text(verbatim: $0.name).tag($0.id) }
            } else {
              Section(group) {
                ForEach(items) { Text(verbatim: $0.name).tag($0.id) }
              }
            }
          }
        }
        Divider()
        Text(L10n.AnnotateAI.settingsCLIModelCustom).tag(Self.customTag)
      } label: {
        AISettingsCLIRowLabel(
          title: L10n.AnnotateAI.settingsCLIModelTitle,
          description: L10n.AnnotateAI.settingsCLIModelPickerDescription,
          isLoading: catalog.loading.contains(kind)
        )
      }
      .pickerStyle(.menu)
      .padding(.top, 8)

      if showsCustomField {
        TextField(text: $model, prompt: Text(L10n.AnnotateAI.settingsCLIModelCustomPlaceholder)) {
          Text(L10n.AnnotateAI.settingsCLIModelCustom)
        }
        .onSubmit(saveModel)
        .onChange(of: model) { _ in saveModel() }
      }

      Picker(selection: effortBinding) {
        Text(L10n.AnnotateAI.settingsCLIModelDefault).tag("")
        Divider()
        ForEach(effortChoices, id: \.self) { level in
          Text(L10n.AnnotateAI.settingsCLIEffortLevel(level)).tag(level)
        }
      } label: {
        AISettingsCLIRowLabel(
          title: L10n.AnnotateAI.settingsCLIEffortTitle,
          description: effortAvailable ? L10n.AnnotateAI.settingsCLIEffortDescription : L10n.AnnotateAI.settingsCLIEffortNeedsModel
        )
      }
      .pickerStyle(.menu)
      .disabled(!effortAvailable)
      .padding(.vertical, 6)

      LabeledContent {
        HStack(spacing: 6) {
          Text(verbatim: locationText)
            .foregroundStyle(isCustomPathInvalid ? Color.red : Color.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(customPath.isEmpty ? (path ?? "") : customPath)
          if !customPath.isEmpty {
            Button {
              customPath = ""
              savePath()
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(L10n.AnnotateAI.settingsCLIPathPlaceholder)
          }
          Button(L10n.AnnotateAI.settingsChoose, action: choosePath)
        }
      } label: {
        AISettingsCLIRowLabel(
          title: L10n.AnnotateAI.settingsCLIPathTitle,
          description: isCustomPathInvalid ? L10n.AnnotateAI.settingsCLIPathInvalid : L10n.AnnotateAI.settingsCLILocationDescription
        )
      }
    } label: {
      HStack(spacing: 10) {
        AnnotateAgentProviderIcon(symbolName: "terminal", logoImageName: kind.logoImageName, size: 16)
          .foregroundColor(.primary)
          .frame(width: 20)
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: kind.displayName)
            .fontWeight(.medium)
          Text(verbatim: subtitle)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        Spacer(minLength: 8)
        if !isExpanded, let summary = selectionSummary {
          Text(verbatim: summary)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(Capsule(style: .continuous).fill(Color.secondary.opacity(0.12)))
        }
        if hasScanned {
          AISettingsStatusDot(isOn: path != nil)
        }
      }
      .help(path ?? "")
      .contentShape(Rectangle())
      .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() } }
    }
    .onChange(of: isExpanded) { expanded in
      if expanded { catalog.refresh(kind, executable: path) }
    }
    .onChange(of: path) { newPath in
      catalog.refresh(kind, executable: newPath, force: true)
    }
    .onDisappear(perform: savePath)
    // Config import or `defaults write` while the page is open: show what is stored now,
    // unless the user is mid-edit on a value that differs.
    .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
      let storedModel = UserDefaults.standard.string(forKey: kind.modelDefaultsKey) ?? ""
      if storedModel != model.trimmingCharacters(in: .whitespacesAndNewlines) { model = storedModel }
      let storedEffort = UserDefaults.standard.string(forKey: kind.effortDefaultsKey) ?? ""
      if storedEffort != effort { effort = storedEffort }
      let storedPath = UserDefaults.standard.string(forKey: kind.pathDefaultsKey) ?? ""
      if storedPath != customPath, !isEditingPath { customPath = storedPath }
    }
  }

  // MARK: Model

  private var options: [AnnotateAgentCLIModelOption] { catalog.models[kind] ?? [] }
  private var trimmedModel: String { model.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var selectedOption: AnnotateAgentCLIModelOption? {
    let base = trimmedModel.split(separator: "#", maxSplits: 1).first.map(String.init) ?? trimmedModel
    return options.first { $0.id == trimmedModel || $0.id == base }
  }

  private var showsCustomField: Bool {
    if isCustomModel { return true }
    guard !trimmedModel.isEmpty, catalog.models[kind] != nil else { return false }
    return selectedOption == nil
  }

  /// A stored model the list doesn't have yet (still loading, or CLI not found).
  private var unlistedModel: String? {
    guard !trimmedModel.isEmpty, !showsCustomField, selectedOption == nil else { return nil }
    return trimmedModel
  }

  private var modelSelection: Binding<String> {
    Binding(
      get: {
        if showsCustomField { return Self.customTag }
        if trimmedModel.isEmpty { return "" }
        return selectedOption?.id ?? trimmedModel
      },
      set: { tag in
        if tag == Self.customTag {
          isCustomModel = true
        } else if tag != trimmedModel {
          selectModel(tag)
        }
      }
    )
  }

  /// "Automatic (~/.local/bin/claude)" or the picked file.
  private var locationText: String {
    let trimmed = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return (trimmed as NSString).abbreviatingWithTildeInPath }
    return L10n.AnnotateAI.settingsCLIPathPlaceholder
  }

  private var groupedOptions: [(String, [AnnotateAgentCLIModelOption])] {
    var order: [String] = []
    var groups: [String: [AnnotateAgentCLIModelOption]] = [:]
    for option in options {
      let group = option.group ?? ""
      if groups[group] == nil { order.append(group) }
      groups[group, default: []].append(option)
    }
    return order.map { ($0, groups[$0] ?? []) }
  }

  private var modelTitle: String {
    if showsCustomField { return trimmedModel.isEmpty ? L10n.AnnotateAI.settingsCLIModelCustom : trimmedModel }
    if let selectedOption {
      return selectedOption.group.map { "\($0) / \(selectedOption.name)" } ?? selectedOption.name
    }
    return trimmedModel.isEmpty ? L10n.AnnotateAI.settingsCLIModelDefault : trimmedModel
  }

  private func selectModel(_ id: String) {
    isCustomModel = false
    model = id
    saveModel()
    // Keep the effort only where the new model takes it.
    if !effort.isEmpty, !effortChoices.contains(effort) { effortBinding.wrappedValue = "" }
  }

  /// Collapsed summary: "Opus · High".
  private var selectionSummary: String? {
    var parts: [String] = []
    if !trimmedModel.isEmpty { parts.append(selectedOption?.name ?? trimmedModel) }
    if !effort.isEmpty, effortAvailable { parts.append(L10n.AnnotateAI.settingsCLIEffortLevel(effort)) }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  // MARK: Effort

  private var effortChoices: [String] {
    let levels = selectedOption?.efforts ?? AnnotateAgentCLIEffort.levels(for: kind)
    // A value from the config file stays selectable.
    return AnnotateAgentCLIEffort.sorted(effort.isEmpty ? levels : levels + [effort])
  }

  /// OpenCode sets effort as the model's variant, so it needs a model.
  private var effortAvailable: Bool {
    kind != .openCode || (!trimmedModel.isEmpty && !trimmedModel.contains("#"))
  }

  private var effortBinding: Binding<String> {
    Binding(
      get: { effort },
      set: { value in
        effort = value
        if value.isEmpty {
          UserDefaults.standard.removeObject(forKey: kind.effortDefaultsKey)
        } else {
          UserDefaults.standard.set(value, forKey: kind.effortDefaultsKey)
        }
      }
    )
  }

  // MARK: Path

  private var subtitle: String {
    guard hasScanned else { return "…" }
    guard let path else { return L10n.AnnotateAI.settingsCLINotFound }
    let shortPath = (path as NSString).abbreviatingWithTildeInPath
    return [version, shortPath].compactMap { $0 }.joined(separator: " · ")
  }

  /// Typed but not yet saved (saved on Return, Choose… or leaving the page).
  private var isEditingPath: Bool {
    customPath.trimmingCharacters(in: .whitespacesAndNewlines)
      != (UserDefaults.standard.string(forKey: kind.pathDefaultsKey) ?? "")
  }

  private var isCustomPathInvalid: Bool {
    let trimmed = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    return !FileManager.default.isExecutableFile(atPath: (trimmed as NSString).expandingTildeInPath)
  }

  private func saveModel() {
    let trimmed = trimmedModel
    if trimmed.isEmpty {
      UserDefaults.standard.removeObject(forKey: kind.modelDefaultsKey)
    } else {
      UserDefaults.standard.set(trimmed, forKey: kind.modelDefaultsKey)
    }
  }

  private func savePath() {
    let trimmed = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
    let stored = UserDefaults.standard.string(forKey: kind.pathDefaultsKey) ?? ""
    guard trimmed != stored else { return }
    if trimmed.isEmpty {
      UserDefaults.standard.removeObject(forKey: kind.pathDefaultsKey)
    } else {
      UserDefaults.standard.set(trimmed, forKey: kind.pathDefaultsKey)
    }
    onChange()
  }

  private func choosePath() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.treatsFilePackagesAsDirectories = true
    panel.showsHiddenFiles = true
    if let path {
      panel.directoryURL = URL(fileURLWithPath: (path as NSString).deletingLastPathComponent)
    }
    guard panel.runModal() == .OK, let url = panel.url else { return }
    customPath = url.path
    savePath()
  }
}

// MARK: - Shared pieces

/// Title over a secondary line, the way System Settings labels a row.
/// Not `SettingRow`: that adds a search anchor id, and each CLI repeats these titles.
private struct AISettingsCLIRowLabel: View {
  let title: String
  let description: String
  var isLoading = false

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Text(title)
        if isLoading {
          ProgressView().controlSize(.mini)
        }
      }
      Text(description)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct AISettingsStatusDot: View {
  let isOn: Bool

  var body: some View {
    Circle()
      .fill(isOn ? Color.green : Color.secondary.opacity(0.45))
      .frame(width: 8, height: 8)
      .accessibilityHidden(true)
  }
}

private struct AISettingsSectionHeader<Accessory: View>: View {
  let title: String
  @ViewBuilder let accessory: () -> Accessory

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      Text(title)
      Spacer()
      accessory()
    }
  }
}

private struct AISettingsFooter: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.caption)
      .foregroundColor(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }
}
