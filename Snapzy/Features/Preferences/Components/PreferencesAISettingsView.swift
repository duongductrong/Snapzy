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
  private var providerValue = AnnotateAgentProviderSelection.automatic.persistedValue
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
            .tag(AnnotateAgentProviderSelection.automatic.persistedValue)
          Text(verbatim: "Apple Intelligence")
            .tag(AnnotateAgentProviderSelection.appleIntelligence.persistedValue)
          if !endpointStore.models.isEmpty {
            Divider()
            ForEach(endpointStore.models) { model in
              Text(verbatim: model.name)
                .tag(AnnotateAgentProviderSelection.endpoint(model.id).persistedValue)
            }
          }
          Divider()
          ForEach(AnnotateAgentCLIKind.allCases) { kind in
            Text(verbatim: kind.displayName)
              .tag(AnnotateAgentProviderSelection.cli(kind).persistedValue)
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
        let selection = AnnotateAgentProviderSelection(persistedValue: providerValue)
        if case .endpoint(let id) = selection, endpointStore.model(for: id) == nil {
          return AnnotateAgentProviderSelection.automatic.persistedValue
        }
        return selection.persistedValue
      },
      set: { providerValue = $0 }
    )
  }

  /// Why the picked provider won't answer yet.
  private var selectionWarning: String? {
    switch AnnotateAgentProviderSelection(persistedValue: providerBinding.wrappedValue) {
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
        Button(L10n.AnnotateAI.settingsRefresh) { detector.refresh(force: true, includeVersions: true, reloadShellPath: true) }
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
  @State private var capabilities: AnnotateAgentEndpointCapabilities
  @State private var isTesting = false
  @State private var errorMessage: String?

  init(model: CustomOCRModel) {
    self.model = model
    _capabilities = State(initialValue: AnnotateAgentEndpointCapabilityStore(defaults: .standard).capabilities(for: model))
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
      capabilities = AnnotateAgentEndpointCapabilityStore(defaults: .standard).capabilities(for: updated)
      errorMessage = nil
    }
    // A prompt in an Annotate window may learn capabilities while this page is open.
    .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
      let stored = AnnotateAgentEndpointCapabilityStore(defaults: .standard).capabilities(for: model)
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

  @State private var isExpanded = false
  @State private var model: String
  @State private var customPath: String

  init(kind: AnnotateAgentCLIKind, path: String?, version: String?, hasScanned: Bool, onChange: @escaping () -> Void) {
    self.kind = kind
    self.path = path
    self.version = version
    self.hasScanned = hasScanned
    self.onChange = onChange
    _model = State(initialValue: UserDefaults.standard.string(forKey: kind.modelDefaultsKey) ?? "")
    _customPath = State(initialValue: UserDefaults.standard.string(forKey: kind.pathDefaultsKey) ?? "")
  }

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 10) {
        AISettingsCLIFieldRow(
          title: L10n.AnnotateAI.settingsCLIModelTitle,
          description: L10n.AnnotateAI.settingsCLIModelDescription
        ) {
          TextField(L10n.AnnotateAI.settingsCLIModelPlaceholder, text: $model)
            .textFieldStyle(.roundedBorder)
            .frame(width: 220)
            .onSubmit(saveModel)
            .onChange(of: model) { _ in saveModel() }
        }

        AISettingsCLIFieldRow(
          title: L10n.AnnotateAI.settingsCLIPathTitle,
          description: L10n.AnnotateAI.settingsCLIPathDescription
        ) {
          HStack(spacing: 6) {
            TextField(L10n.AnnotateAI.settingsCLIPathPlaceholder, text: $customPath)
              .textFieldStyle(.roundedBorder)
              .frame(width: 220)
              .onSubmit(savePath)
            Button(L10n.AnnotateAI.settingsChoose, action: choosePath)
          }
        }

        if isCustomPathInvalid {
          Text(L10n.AnnotateAI.settingsCLIPathInvalid)
            .font(.caption)
            .foregroundColor(.red)
        }
      }
      .padding(.top, 6)
    } label: {
      HStack(spacing: 10) {
        Image(systemName: "terminal")
          .foregroundColor(.secondary)
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
        if hasScanned {
          AISettingsStatusDot(isOn: path != nil)
        }
      }
      .help(path ?? "")
      .contentShape(Rectangle())
      .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() } }
    }
    .onDisappear(perform: savePath)
    // Config import or `defaults write` while the page is open: show what is stored now,
    // unless the user is mid-edit on a value that differs.
    .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
      let storedModel = UserDefaults.standard.string(forKey: kind.modelDefaultsKey) ?? ""
      if storedModel != model.trimmingCharacters(in: .whitespacesAndNewlines) { model = storedModel }
      let storedPath = UserDefaults.standard.string(forKey: kind.pathDefaultsKey) ?? ""
      if storedPath != customPath, !isEditingPath { customPath = storedPath }
    }
  }

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
    let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
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

/// Like `SettingRow`, without its search anchor id: each CLI repeats these titles.
private struct AISettingsCLIFieldRow<Content: View>: View {
  let title: String
  let description: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    HStack(spacing: 12) {
      Text(title)
        .hint(description, variant: .icon(.info))
      Spacer()
      content()
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
