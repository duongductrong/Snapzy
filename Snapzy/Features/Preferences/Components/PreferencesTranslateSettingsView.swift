//
//  PreferencesTranslateSettingsView.swift
//  Snapzy
//
//  Settings › Translate: target language and engine for Snip to Translate, Annotate
//  Auto Translate, caption translation and the Translate automation step. Custom
//  endpoints are shared with OCR; agent CLIs with Settings › AI.
//

import Combine
import SwiftUI

struct TranslateSettingsView: View {
  @AppStorage(PreferencesKeys.translateTargetLanguage) private var targetLanguage = ""
  @AppStorage(PreferencesKeys.translateSelectedEngine)
  private var selectedEngine = TranslationEngineSelection.builtIn.persistedValue
  @ObservedObject private var store = CustomOCRModelStore.shared
  @ObservedObject private var detector = AnnotateAgentCLIDetector.shared
  /// The CLI whose settings are open under its tile (gear), independent of the selection.
  @State private var configuringCLI: AnnotateAgentCLIKind?

  var body: some View {
    Form {
      Section {
      } header: {
        PreferencesPageHero(tab: .translate, subtitle: L10n.Translate.settingsHeroSubtitle)
      }

      Section(L10n.Translate.settingsLanguageSection) {
        SettingRow(
          title: L10n.Translate.targetLanguageLabel,
          description: L10n.Translate.settingsTargetDescription
        ) {
          Picker("", selection: $targetLanguage) {
            Text(L10n.Translate.settingsTargetAsk).tag("")
            Divider()
            ForEach(TranslationLanguage.all) { language in
              Text(language.displayName).tag(language.identifier)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }
      }

      Section {
        VStack(alignment: .leading, spacing: 14) {
          TranslateEngineGallery(
            selection: selection,
            endpoints: store.models,
            installed: detector.installed,
            versions: detector.versions,
            hasScanned: detector.hasScanned,
            configuring: configuringCLI,
            onSelect: { selectedEngine = $0.persistedValue },
            onConfigure: { kind in
              withAnimation(Self.expandSpring) {
                configuringCLI = configuringCLI == kind ? nil : kind
              }
            },
            onManageEndpoints: Self.openEndpointList,
            configuration: { kind in
              TranslateAgentCLIDetailCard(
                kind: kind,
                executable: detector.installed[kind],
                version: detector.versions[kind],
                hasScanned: detector.hasScanned,
                targetLanguage: targetLanguage
              )
              .id(kind)
            }
          )

          selectionNote
        }
        .padding(.vertical, 6)
      } header: {
        VStack(alignment: .leading, spacing: 3) {
          Text(L10n.Translate.settingsEngineTitle)
          Text(L10n.Translate.settingsEngineDescriptionAll)
            .font(.caption)
            .fontWeight(.regular)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Section {
        Label {
          Text(L10n.AnnotateTranslate.layoutNote)
            .font(.callout)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: "translate")
            .foregroundColor(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .onAppear { detector.refresh(includeVersions: true) }
  }

  /// Endpoints are added and edited in Capture › OCR (shared with OCR).
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

  /// Opening a CLI's settings: settles without overshoot, so the rows below glide down.
  static let expandSpring: Animation = .spring(response: 0.38, dampingFraction: 0.88)

  /// A stored endpoint that was removed reads as Apple Translation.
  private var selection: TranslationEngineSelection {
    let selection = TranslationEngineSelection(persistedValue: selectedEngine)
    if case .custom(let id) = selection, store.model(for: id) == nil {
      return .builtIn
    }
    return selection
  }

  /// One quiet line on where the text goes. Configuration lives behind each CLI's gear.
  @ViewBuilder
  private var selectionNote: some View {
    switch selection {
    case .builtIn:
      if TranslationEngineResolver.systemSupportsAppleTranslation {
        TranslateEngineNote(systemImage: "lock.fill", text: L10n.Translate.settingsAppleDetail)
      } else {
        TranslateEngineNote(
          systemImage: "exclamationmark.triangle.fill",
          text: store.models.isEmpty
            ? L10n.Translate.requiresMacOS15MessageNoEndpoint
            : L10n.Translate.requiresMacOS15MessageWithEndpoint,
          tint: .orange
        )
      }
    case .custom:
      TranslateEngineNote(systemImage: "network", text: L10n.Translate.useEndpointCaption)
    case .agentCLI(let kind):
      TranslateEngineNote(systemImage: "terminal", text: L10n.Translate.settingsCLIPrivacy(kind.displayName))
    }
  }
}

// MARK: - Gallery

/// Every engine as a quiet glass tile, grouped by where the text goes. A click selects;
/// a CLI's gear opens its settings in place under the CLI row.
private struct TranslateEngineGallery<Configuration: View>: View {
  let selection: TranslationEngineSelection
  let endpoints: [CustomOCRModel]
  let installed: [AnnotateAgentCLIKind: String]
  let versions: [AnnotateAgentCLIKind: String]
  let hasScanned: Bool
  let configuring: AnnotateAgentCLIKind?
  let onSelect: (TranslationEngineSelection) -> Void
  let onConfigure: (AnnotateAgentCLIKind) -> Void
  let onManageEndpoints: () -> Void
  @ViewBuilder let configuration: (AnnotateAgentCLIKind) -> Configuration

  private let columns = [GridItem(.adaptive(minimum: 176), spacing: 10, alignment: .top)]

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      group(L10n.Translate.settingsGroupDevice) {
        grid {
          TranslateEngineTile(
            icon: .symbol("apple.logo"),
            title: L10n.Translate.settingsAppleTileTitle,
            subtitle: TranslationEngineResolver.systemSupportsAppleTranslation
              ? L10n.Translate.settingsAppleTileSubtitle
              : L10n.Translate.settingsAppleTileUnavailable,
            badge: "lock.fill",
            isSelected: selection == .builtIn,
            isDimmed: !TranslationEngineResolver.systemSupportsAppleTranslation
          ) { onSelect(.builtIn) }
        }
      }

      group(L10n.Translate.settingsGroupAgentCLI) {
        grid {
          ForEach(AnnotateAgentCLIKind.allCases) { kind in
            TranslateEngineTile(
              icon: .logo(kind.logoImageName),
              title: kind.displayName,
              subtitle: cliSubtitle(kind),
              badge: "terminal",
              isSelected: selection == .agentCLI(kind),
              isDimmed: hasScanned && installed[kind] == nil,
              settings: .init(
                isOpen: configuring == kind,
                help: L10n.Translate.settingsCLIConfigure(kind.displayName)
              ) { onConfigure(kind) }
            ) { onSelect(.agentCLI(kind)) }
          }
        }
        if let configuring {
          configuration(configuring)
            .transition(.asymmetric(
              insertion: .opacity
                .combined(with: .scale(scale: 0.97, anchor: .top))
                .combined(with: .offset(y: -8)),
              removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
            ))
        }
      }

      group(L10n.Translate.settingsGroupEndpoints, accessory: {
        Button(L10n.AnnotateAI.settingsManageEndpoints, action: onManageEndpoints)
          .buttonStyle(.link)
          .font(.system(size: 11))
      }) {
        grid {
          if endpoints.isEmpty {
            TranslateAddEndpointTile(action: onManageEndpoints)
          }
          ForEach(endpoints) { endpoint in
            TranslateEngineTile(
              icon: .symbol("server.rack"),
              title: endpoint.name,
              subtitle: URL(string: endpoint.baseURL)?.host ?? endpoint.modelIdentifier,
              badge: "network",
              isSelected: selection == .custom(endpoint.id),
              isDimmed: false
            ) { onSelect(.custom(endpoint.id)) }
          }
        }
      }
    }
  }

  private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    group(title, accessory: { EmptyView() }, content: content)
  }

  private func group<Accessory: View, Content: View>(
    _ title: String,
    @ViewBuilder accessory: () -> Accessory,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text(title)
          .font(.system(size: 10.5, weight: .semibold))
          .tracking(0.4)
          .foregroundStyle(.secondary)
          .textCase(.uppercase)
        Spacer(minLength: 8)
        accessory()
      }
      .padding(.horizontal, 2)
      content()
    }
  }

  private func grid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
      content()
    }
  }

  /// "2.1.3 · Opus", "Not installed", or "…" before the first scan.
  private func cliSubtitle(_ kind: AnnotateAgentCLIKind) -> String {
    guard hasScanned else { return "…" }
    guard installed[kind] != nil else { return L10n.Translate.settingsCLINotInstalled }
    let model = TranslationAgentCLISettings.model(kind).map { TranslateModelName.display($0, kind: kind) }
    let parts = [versions[kind], model].compactMap { $0 }
    return parts.isEmpty ? kind.displayName : parts.joined(separator: " · ")
  }
}

/// One engine. Resting: a faint pane of glass with a hairline. Selected: the glass lifts
/// (denser material, a specular rim lit from the top-left) and a
/// small accent seal marks it; no flood of accent color, so the material stays pure.
private struct TranslateEngineTile: View {
  enum Icon {
    case symbol(String)
    case logo(String)
  }

  /// The gear on tiles that have settings of their own.
  struct Settings {
    let isOpen: Bool
    let help: String
    let action: () -> Void
  }

  let icon: Icon
  let title: String
  let subtitle: String
  /// Where the text goes: lock (this Mac), terminal (CLI), network (endpoint).
  let badge: String
  let isSelected: Bool
  let isDimmed: Bool
  var settings: Settings?
  let action: () -> Void

  @State private var isHovered = false
  @State private var isGearHovered = false

  private static let height: CGFloat = 54
  private static let gearSize: CGFloat = 24
  private var shape: RoundedRectangle { Radius.rect(Radius.card) }

  var body: some View {
    HStack(spacing: 6) {
      Button(action: action) {
        HStack(spacing: 10) {
          iconWell

          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
              .font(.system(size: 12.5, weight: .semibold))
              .foregroundStyle(.primary)
              .lineLimit(1)
            HStack(spacing: 4) {
              Image(systemName: badge)
                .font(.system(size: 8.5, weight: .semibold))
              Text(verbatim: subtitle)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
          }

          Spacer(minLength: 4)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)

      if let settings {
        gear(settings)
      }

      // The check sits at the trailing edge and selects too.
      Button(action: action) {
        seal
          .frame(width: Self.gearSize, height: Self.gearSize)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHidden(true)
    }
    .padding(.leading, 10)
    .padding(.trailing, 6)
    .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .leading)
    .opacity(isDimmed && !isSelected ? 0.5 : 1)
    .liquidGlassChrome(shape: shape, isVisible: true, isActive: isSelected)
    .overlay { rim }
    .onHover { isHovered = $0 }
    .animation(.easeOut(duration: 0.14), value: isHovered)
    .animation(.spring(response: 0.3, dampingFraction: 0.9), value: isSelected)
  }

  // MARK: Pieces

  private var iconWell: some View {
    iconView
      .frame(width: 30, height: 30)
      .background {
        Radius.rect(Radius.tile)
          .fill(Color.primary.opacity(isSelected ? 0.09 : 0.05))
          .overlay {
            Radius.rect(Radius.tile)
              .strokeBorder(Color.white.opacity(isSelected ? 0.16 : 0.06), lineWidth: 0.5)
          }
      }
  }

  /// Specular hairline: bright where light hits (top-left) and fading across, plus a
  /// whisper of accent on the selected pane. Hover only lifts the rim a touch.
  private var rim: some View {
    ZStack {
      shape.strokeBorder(
        LinearGradient(
          colors: [
            .white.opacity(isSelected ? 0.42 : (isHovered ? 0.18 : 0.08)),
            .white.opacity(isSelected ? 0.06 : 0.02),
            .white.opacity(isSelected ? 0.14 : 0.04),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        ),
        lineWidth: isSelected ? 1 : 0.5
      )
      if isSelected {
        shape
          .inset(by: 0.5)
          .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.5)
          .blendMode(.plusLighter)
      }
    }
    .allowsHitTesting(false)
  }

  /// Accent seal with a check when selected; a faint ring on hover; nothing at rest.
  private var seal: some View {
    ZStack {
      Circle()
        .strokeBorder(Color.secondary.opacity(isHovered && !isSelected ? 0.45 : 0), lineWidth: 1)
      Circle()
        .fill(Color.accentColor)
        .scaleEffect(isSelected ? 1 : 0.4)
        .opacity(isSelected ? 1 : 0)
      Image(systemName: "checkmark")
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(.white)
        .scaleEffect(isSelected ? 1 : 0.4)
        .opacity(isSelected ? 1 : 0)
    }
    .frame(width: 16, height: 16)
    .accessibilityHidden(true)
  }

  private func gear(_ settings: Settings) -> some View {
    Button(action: settings.action) {
      Image(systemName: "gearshape")
        .font(.system(size: 12, weight: .medium))
        .rotationEffect(.degrees(settings.isOpen ? 90 : 0))
        .foregroundStyle(settings.isOpen ? Color.primary : Color.secondary.opacity(isGearHovered ? 0.95 : 0.6))
        .frame(width: Self.gearSize, height: Self.gearSize)
        .background {
          Circle()
            .fill(Color.primary.opacity(settings.isOpen ? 0.12 : (isGearHovered ? 0.07 : 0)))
            .overlay(Circle().strokeBorder(Color.white.opacity(settings.isOpen ? 0.18 : 0), lineWidth: 0.5))
        }
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(settings.help)
    .accessibilityLabel(settings.help)
    .accessibilityAddTraits(settings.isOpen ? .isSelected : [])
    .onHover { isGearHovered = $0 }
    .animation(.easeOut(duration: 0.12), value: isGearHovered)
    .animation(TranslateSettingsView.expandSpring, value: settings.isOpen)
  }

  @ViewBuilder
  private var iconView: some View {
    switch icon {
    case .symbol(let name):
      Image(systemName: name)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.primary)
    case .logo(let name):
      Image(name)
        .resizable()
        .interpolation(.high)
        .aspectRatio(contentMode: .fit)
        .frame(width: 16, height: 16)
        .foregroundStyle(.primary)
    }
  }
}

/// Empty endpoint group: a dashed slot that leads to Capture › OCR.
private struct TranslateAddEndpointTile: View {
  let action: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: "plus")
          .font(.system(size: 12, weight: .semibold))
          .frame(width: 30, height: 30)
          .background(Radius.rect(Radius.tile).fill(Color.primary.opacity(isHovered ? 0.07 : 0.04)))
        Text(L10n.PreferencesCapture.ocrModelAddCustom)
          .font(.system(size: 12, weight: .medium))
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .foregroundStyle(isHovered ? Color.primary : Color.secondary)
      .padding(.horizontal, 10)
      .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54, alignment: .leading)
      .overlay {
        Radius.rect(Radius.card)
          .strokeBorder(Color.secondary.opacity(isHovered ? 0.45 : 0.28), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
      }
      .contentShape(Radius.rect(Radius.card))
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .animation(.easeOut(duration: 0.14), value: isHovered)
  }
}

private struct TranslateEngineNote: View {
  let systemImage: String
  let text: String
  var tint: Color = .secondary

  var body: some View {
    Label {
      Text(text)
        .font(.callout)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: systemImage)
        .foregroundStyle(tint)
    }
  }
}

// MARK: - Agent CLI detail

enum TranslateModelName {
  /// Catalog name for a model id when the catalog has it ("opus" → "Opus").
  @MainActor
  static func display(_ id: String, kind: AnnotateAgentCLIKind) -> String {
    let base = id.split(separator: "#", maxSplits: 1).first.map(String.init) ?? id
    let options = AnnotateAgentCLIModelCatalogStore.shared.models[kind] ?? []
    if let option = options.first(where: { $0.id == id || $0.id == base }) { return option.name }
    if kind == .claudeCode, let alias = ["opus": "Opus", "sonnet": "Sonnet", "haiku": "Haiku"][id] { return alias }
    return id
  }
}

/// Model override, privacy note and a live sample translation for the selected CLI.
private struct TranslateAgentCLIDetailCard: View {
  let kind: AnnotateAgentCLIKind
  let executable: String?
  let version: String?
  let hasScanned: Bool
  let targetLanguage: String

  @ObservedObject private var catalog = AnnotateAgentCLIModelCatalogStore.shared
  @State private var override = ""
  @State private var isCustom = false
  @State private var aiModel: String?
  @State private var test: TestState = .idle
  @State private var testTask: Task<Void, Never>?

  private enum TestState: Equatable {
    case idle
    case running
    case done(text: String, seconds: Double)
    case failed(String)
  }

  private static let customTag = "\u{0}custom"
  private static let sample = "Snapzy makes screenshots and recordings feel effortless."
  private var shape: RoundedRectangle { Radius.rect(Radius.card) }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header

      if hasScanned, executable == nil {
        TranslateEngineNote(
          systemImage: "exclamationmark.triangle.fill",
          text: L10n.AnnotateAI.cliNotInstalled(kind.displayName),
          tint: .orange
        )
      }

      Divider().opacity(0.5)

      modelRow

      if showsCustomField {
        TextField(text: $override, prompt: Text(L10n.AnnotateAI.settingsCLIModelCustomPlaceholder)) {
          Text(L10n.AnnotateAI.settingsCLIModelCustom)
        }
        .textFieldStyle(.roundedBorder)
        .onSubmit(save)
        .onChange(of: override) { _ in save() }
      }

      Divider().opacity(0.5)

      testRow
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .liquidGlassChrome(shape: shape, isVisible: true, isActive: false)
    .overlay { shape.strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5) }
    .onAppear(perform: load)
    .onChange(of: executable) { newValue in
      if let newValue { catalog.refresh(kind, executable: newValue, force: true) }
    }
    .onDisappear { testTask?.cancel() }
    // Defaults may change on any thread; @State is only touched on main.
    .onReceive(
      NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: DispatchQueue.main)
    ) { _ in
      aiModel = TranslationAgentCLISettings.aiModel(kind)
      let stored = TranslationAgentCLISettings.modelOverride(kind) ?? ""
      if stored != trimmedOverride { override = stored }
    }
  }

  // MARK: Header

  private var header: some View {
    HStack(spacing: 10) {
      Image(kind.logoImageName)
        .resizable()
        .interpolation(.high)
        .aspectRatio(contentMode: .fit)
        .frame(width: 18, height: 18)
        .frame(width: 32, height: 32)
        .background(Radius.rect(Radius.tile).fill(Color.primary.opacity(0.07)))

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(verbatim: kind.displayName)
            .font(.system(size: 13, weight: .semibold))
          if let version {
            Text(verbatim: version)
              .font(.system(size: 10, weight: .medium).monospacedDigit())
              .foregroundStyle(.secondary)
              .padding(.horizontal, 6)
              .frame(height: 16)
              .background(Capsule(style: .continuous).fill(Color.secondary.opacity(0.14)))
          }
          if !trimmedOverride.isEmpty {
            Text(L10n.Translate.settingsCLIModelOverridden)
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(Color.accentColor)
              .padding(.horizontal, 6)
              .frame(height: 16)
              .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.14)))
          }
        }
        Text(verbatim: executable.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? (hasScanned ? L10n.Translate.settingsCLINotInstalled : "…"))
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer(minLength: 8)

      Button(L10n.Translate.settingsOpenAISettings) {
        AppStatusBarController.shared.openPreferencesWindow(tab: .ai)
      }
      .buttonStyle(.liquidGlass())
      .controlSize(.small)
    }
  }

  // MARK: Model

  private var modelRow: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(L10n.Translate.settingsCLIModelTitle)
          if catalog.loading.contains(kind) {
            ProgressView().controlSize(.mini)
          }
        }
        Text(L10n.Translate.settingsCLIModelDescription)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Picker("", selection: modelSelection) {
        Text(followAILabel).tag("")
        if let unlisted = unlistedModel {
          Divider()
          Text(verbatim: unlisted).tag(unlisted)
        }
        if !options.isEmpty {
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
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .frame(maxWidth: 240)
    }
  }

  private var followAILabel: String {
    let name = aiModel.map { TranslateModelName.display($0, kind: kind) } ?? L10n.AnnotateAI.settingsCLIModelDefault
    return L10n.Translate.settingsCLIModelFollowAI(name)
  }

  private var options: [AnnotateAgentCLIModelOption] { catalog.models[kind] ?? [] }
  private var trimmedOverride: String { override.trimmingCharacters(in: .whitespacesAndNewlines) }

  private var selectedOption: AnnotateAgentCLIModelOption? {
    options.first { $0.id == trimmedOverride }
  }

  private var showsCustomField: Bool {
    if isCustom { return true }
    guard !trimmedOverride.isEmpty, catalog.models[kind] != nil, !catalog.loading.contains(kind) else { return false }
    return selectedOption == nil
  }

  /// A stored override the catalog doesn't list yet (still loading, or CLI missing).
  private var unlistedModel: String? {
    guard !trimmedOverride.isEmpty, !showsCustomField, selectedOption == nil else { return nil }
    return trimmedOverride
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

  private var modelSelection: Binding<String> {
    Binding(
      get: {
        if showsCustomField { return Self.customTag }
        return trimmedOverride
      },
      set: { tag in
        if tag == Self.customTag {
          isCustom = true
          return
        }
        isCustom = false
        override = tag
        save()
      }
    )
  }

  private func load() {
    override = TranslationAgentCLISettings.modelOverride(kind) ?? ""
    aiModel = TranslationAgentCLISettings.aiModel(kind)
    isCustom = false
    // Before the first scan the path is unknown; `onChange(of: executable)` loads it then
    // (a load started with no path would block the forced one and stay empty).
    if let executable { catalog.refresh(kind, executable: executable) }
  }

  private func save() {
    TranslationAgentCLISettings.setModelOverride(trimmedOverride, for: kind)
    if case .done = test { test = .idle }
  }

  // MARK: Try it

  private var testRow: some View {
    HStack(alignment: .center, spacing: 10) {
      Button {
        runTest()
      } label: {
        Label(L10n.Translate.settingsCLITest, systemImage: "sparkles")
      }
      .buttonStyle(.liquidGlass())
      .controlSize(.small)
      .disabled(test == .running || (hasScanned && executable == nil))

      Group {
        switch test {
        case .idle:
          EmptyView()
        case .running:
          HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(L10n.Translate.settingsCLITesting)
          }
          .foregroundStyle(.secondary)
        case .done(let text, let seconds):
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: text)
              .foregroundStyle(.primary)
              .textSelection(.enabled)
              .lineLimit(3)
            Label(
              L10n.Translate.settingsCLITestDone(String(format: "%.1f", seconds)),
              systemImage: "checkmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(.green)
          }
        case .failed(let message):
          Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .lineLimit(3)
        }
      }
      .font(.callout)
      .fixedSize(horizontal: false, vertical: true)
      .transition(.opacity)

      Spacer(minLength: 0)
    }
    .animation(.easeOut(duration: 0.18), value: test)
  }

  private var sampleTarget: TranslationLanguage {
    if let stored = TranslationLanguage.language(for: targetLanguage.isEmpty ? nil : targetLanguage) {
      return stored
    }
    let system = TranslationLanguage.language(for: Locale.current.language.languageCode?.identifier)
    if let system, !system.identifier.hasPrefix("en") { return system }
    return TranslationLanguage(identifier: "es")
  }

  private func runTest() {
    testTask?.cancel()
    test = .running
    let kind = kind
    let target = sampleTarget
    testTask = Task {
      let start = Date()
      do {
        let text = try await RemoteTranslationProvider(engine: .agentCLI(kind)).translate(Self.sample, to: target)
        guard !Task.isCancelled else { return }
        test = .done(text: text, seconds: Date().timeIntervalSince(start))
      } catch is CancellationError {
        test = .idle
      } catch {
        guard !Task.isCancelled else { return }
        test = .failed(error.localizedDescription)
      }
    }
  }
}
