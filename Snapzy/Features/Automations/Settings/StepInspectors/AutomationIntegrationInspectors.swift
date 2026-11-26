//
//  AutomationIntegrationInspectors.swift
//  Snapzy
//
//  Settings for milestone 4 steps: upload destination, webhook, shell script,
//  Apple Shortcut, share sheet and open in app. Fields that allow secrets get
//  an "Insert Secret" menu; script and Shortcut steps show a banner while
//  code steps are off.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Upload

struct UploadDestinationInspector: View {
  @Binding var config: AutomationUploadConfig
  @ObservedObject private var uploaders = CustomUploaderStore.shared

  var body: some View {
    Section {
      Picker(L10n.Automations.uploadDestinationLabel, selection: $config.destination) {
        Text(L10n.Automations.uploadDestinationDefault).tag(AutomationUploadDestination.default)
        if !uploaders.uploaders.isEmpty {
          Divider()
          ForEach(uploaders.uploaders) { uploader in
            Text(uploader.name).tag(AutomationUploadDestination.customUploader(uploader.id))
          }
        }
        if case .customUploader(let id) = config.destination, uploaders.uploader(id: id) == nil {
          Text(L10n.Automations.issueUploader).tag(config.destination)
        }
      }
      Button(L10n.Automations.manageUploaders) {
        PreferencesNavigationState.shared.select(.cloud)
      }
      .buttonStyle(.link)
    }
  }
}

// MARK: - Webhook

struct WebhookInspector: View {
  @Binding var config: AutomationWebhookConfig
  @State private var isTesting = false
  @State private var testOutcome: AutomationWebhookTestOutcome?
  @State private var testTask: Task<Void, Never>?

  var body: some View {
    Section {
      Picker(L10n.Automations.webhookPresetLabel, selection: presetBinding) {
        Text(L10n.Automations.webhookPresetSlack).tag(AutomationWebhookConfig.Preset?.some(.slack))
        Text(L10n.Automations.webhookPresetDiscord).tag(AutomationWebhookConfig.Preset?.some(.discord))
        Text(L10n.Automations.webhookPresetGeneric).tag(AutomationWebhookConfig.Preset?.some(.genericJSON))
        if presetBinding.wrappedValue == nil {
          Divider()
          Text(L10n.Automations.bodyJSON).tag(AutomationWebhookConfig.Preset?.none)
        }
      }
      Picker(L10n.Automations.methodLabel, selection: $config.method) {
        ForEach(AutomationHTTPMethod.allCases) { method in
          Text(verbatim: method.rawValue).tag(method)
        }
      }
      HStack {
        TextField(L10n.Automations.urlLabel, text: $config.url, prompt: Text(verbatim: "https://hooks.slack.com/services/…"))
          .font(.system(.body, design: .monospaced))
        AutomationSecretInsertMenu { config.url += $0 }
      }
      if !config.url.isEmpty, !AutomationWebhookPolicy.isAcceptableTemplate(config.url) {
        Label(L10n.Automations.issueWebhookURL, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
      }
    }

    Section(L10n.Automations.headersLabel) {
      AutomationKeyValueEditor(rows: $config.headers, addTitle: L10n.Automations.addHeader)
    }

    if config.method.hasBody {
      Section {
        Picker(L10n.Automations.bodyLabel, selection: $config.bodyKind) {
          Text(L10n.Automations.bodyNone).tag(AutomationWebhookBodyKind.none)
          Text(L10n.Automations.bodyJSON).tag(AutomationWebhookBodyKind.json)
          Text(L10n.Automations.bodyForm).tag(AutomationWebhookBodyKind.form)
          Text(L10n.Automations.bodyMultipart).tag(AutomationWebhookBodyKind.multipart)
        }
        switch config.bodyKind {
        case .json:
          HStack(alignment: .top) {
            TextField(L10n.Automations.bodyJSON, text: $config.jsonTemplate, axis: .vertical)
              .font(.system(.body, design: .monospaced))
              .lineLimit(3...8)
              .labelsHidden()
            VStack(spacing: 6) {
              AutomationTokenHelpButton()
              AutomationSecretInsertMenu { config.jsonTemplate += $0 }
            }
          }
          if !isJSONValid {
            Label(L10n.Automations.jsonInvalid, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.orange)
          }
        case .form, .multipart:
          if config.bodyKind == .multipart {
            TextField(L10n.Automations.fileFieldLabel, text: $config.fileField, prompt: Text(verbatim: "file"))
              .font(.system(.body, design: .monospaced))
          }
          AutomationKeyValueEditor(rows: $config.fields, addTitle: L10n.Automations.addField)
        case .none:
          EmptyView()
        }
      }
    }

    Section {
      Toggle(L10n.Automations.responseToText, isOn: $config.responseToText)
      TextField(
        L10n.Automations.responseLinkPath,
        text: Binding(get: { config.responseLinkPath ?? "" }, set: { config.responseLinkPath = $0.isEmpty ? nil : $0 }),
        prompt: Text(verbatim: "data.url")
      )
      .font(.system(.body, design: .monospaced))
      AutomationTimeoutPicker(timeout: $config.timeout, range: AutomationWebhookConfig.timeoutRange)
    } footer: {
      Text(L10n.Automations.webhookFooter)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    testSection
      .onChange(of: config) { _ in
        testTask?.cancel()
        testTask = nil
        isTesting = false
        testOutcome = nil
      }
      .onDisappear { testTask?.cancel() }
  }

  private var canTest: Bool {
    !config.url.trimmingCharacters(in: .whitespaces).isEmpty
      && AutomationWebhookPolicy.isAcceptableTemplate(config.url)
  }

  private var testSection: some View {
    Section {
      HStack(spacing: 10) {
        Button(action: runTest) {
          if isTesting {
            HStack(spacing: 6) {
              ProgressView().controlSize(.small)
              Text(L10n.CustomUploader.testing)
            }
          } else {
            Label(L10n.CustomUploader.test, systemImage: "paperplane")
          }
        }
        .disabled(!canTest || isTesting)

        Text(L10n.Automations.webhookTestDescription)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let testOutcome {
        testOutcomeView(testOutcome)
      }
    }
  }

  @ViewBuilder
  private func testOutcomeView(_ outcome: AutomationWebhookTestOutcome) -> some View {
    if let status = outcome.statusCode {
      LabeledContent(L10n.Common.status) {
        Text(L10n.CustomUploader.testStatus(status))
          .foregroundStyle((200..<300).contains(status) ? .green : .red)
          .monospacedDigit()
      }
    }
    if let body = outcome.responseBody {
      VStack(alignment: .leading, spacing: 4) {
        Text(L10n.CustomUploader.testResponseBody)
        ScrollView {
          Text(body.isEmpty ? L10n.CustomUploader.testEmptyBody : body)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 120)
      }
    }
    if let link = outcome.extractedLink {
      LabeledContent(L10n.CustomUploader.testExtractedURL) {
        Text(link)
          .font(.system(size: 11, design: .monospaced))
          .textSelection(.enabled)
          .lineLimit(2)
          .truncationMode(.middle)
      }
    }
    if let error = outcome.error {
      LabeledContent(L10n.CustomUploader.testError) {
        Text(error)
          .foregroundStyle(.red)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func runTest() {
    testTask?.cancel()
    testOutcome = nil
    isTesting = true
    let snapshot = config
    testTask = Task {
      let outcome = await AutomationWebhookTestRunner.run(snapshot)
      guard !Task.isCancelled else { return }
      testOutcome = outcome
      isTesting = false
    }
  }

  private var presetBinding: Binding<AutomationWebhookConfig.Preset?> {
    Binding(
      get: { AutomationWebhookConfig.Preset.allCases.first { $0.jsonTemplate == config.jsonTemplate } },
      set: { preset in
        guard let preset else { return }
        config.jsonTemplate = preset.jsonTemplate
        config.bodyKind = .json
        if !config.method.hasBody { config.method = .post }
      }
    )
  }

  /// The template rendered with sample values (secrets as placeholders) parses as JSON.
  private var isJSONValid: Bool {
    let rendered = (try? AutomationTemplatePreview.sample.renderAllowingSecrets(
      config.jsonTemplate,
      escape: .json,
      resolveSecret: { _ in "secret" }
    ))?.text ?? config.jsonTemplate
    return (try? JSONSerialization.jsonObject(with: Data(rendered.utf8), options: [.fragmentsAllowed])) != nil
  }
}

// MARK: - Webhook Test

struct AutomationWebhookTestOutcome: Equatable {
  var statusCode: Int?
  var responseBody: String?
  var extractedLink: String?
  var error: String?
}

/// Sends the webhook once with sample template values (and a 1×1 PNG for
/// multipart bodies); secrets resolve from the store and are masked out of
/// the response shown.
enum AutomationWebhookTestRunner {
  static let responsePreviewBytes = 2048

  /// A transparent 1×1 PNG.
  private static let pngData = Data(
    base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
  )!

  static func run(
    _ config: AutomationWebhookConfig,
    environment: AutomationRunEnvironment? = nil
  ) async -> AutomationWebhookTestOutcome {
    let environment = environment ?? LiveAutomationRunEnvironment()
    let runID = UUID()
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyWebhookTest-\(runID.uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let context = AutomationRunContext(
      runID: runID,
      automationID: UUID(),
      automationName: "Webhook Test",
      invocation: .menuBar,
      startedAt: Date(),
      appName: nil,
      windowTitle: nil,
      workingDirectory: directory
    )
    var secrets: [String] = []
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let file = directory.appendingPathComponent("Snapzy_shot.png")
      try pngData.write(to: file)
      let exchange = try await WebhookStepHandler.send(
        config,
        files: [file],
        variables: AutomationTemplatePreview.sample,
        context: context,
        environment: environment,
        secretValues: &secrets
      )
      return outcome(config: config, data: exchange.data, statusCode: exchange.response.statusCode, secrets: secrets)
    } catch {
      return AutomationWebhookTestOutcome(
        error: AutomationSecretStore.mask(error.localizedDescription, values: secrets)
      )
    }
  }

  static func outcome(
    config: AutomationWebhookConfig,
    data: Data,
    statusCode: Int,
    secrets: [String]
  ) -> AutomationWebhookTestOutcome {
    var outcome = AutomationWebhookTestOutcome(
      statusCode: statusCode,
      responseBody: AutomationSecretStore.mask(preview(of: data), values: secrets)
    )
    guard (200..<300).contains(statusCode) else { return outcome }
    if let path = config.trimmedResponseLinkPath {
      do {
        outcome.extractedLink = try WebhookStepHandler.link(at: path, in: data).absoluteString
      } catch {
        outcome.error = error.localizedDescription
      }
    }
    return outcome
  }

  /// The first 2 KB of the body as text.
  static func preview(of body: Data) -> String {
    let text = String(decoding: body.prefix(responsePreviewBytes), as: UTF8.self)
    return body.count > responsePreviewBytes ? text + "…" : text
  }
}

/// Ordered name / value rows (headers, form fields).
struct AutomationKeyValueEditor: View {
  @Binding var rows: [AutomationKeyValue]
  let addTitle: String

  var body: some View {
    ForEach($rows) { $row in
      HStack(spacing: 6) {
        TextField(L10n.Automations.keyPlaceholder, text: $row.name, prompt: Text(L10n.Automations.keyPlaceholder))
          .labelsHidden()
          .frame(maxWidth: 140)
        TextField(L10n.Automations.valuePlaceholder, text: $row.value, prompt: Text(L10n.Automations.valuePlaceholder))
          .labelsHidden()
          .font(.system(.body, design: .monospaced))
        AutomationSecretInsertMenu { row.value += $0 }
        Button {
          rows.removeAll { $0.id == row.id }
        } label: {
          Image(systemName: "minus.circle")
        }
        .buttonStyle(.borderless)
        .help(L10n.Automations.removeRow)
        .accessibilityLabel(L10n.Automations.removeRow)
      }
    }
    Button {
      rows.append(AutomationKeyValue(name: "", value: ""))
    } label: {
      Label(addTitle, systemImage: "plus")
    }
    .buttonStyle(.link)
  }
}

/// Inserts `{secret:NAME}`; links to the secrets list when there are none.
struct AutomationSecretInsertMenu: View {
  let insert: (String) -> Void
  @ObservedObject private var secrets = AutomationSecretStore.shared

  var body: some View {
    Menu {
      ForEach(secrets.names, id: \.self) { name in
        Button(name) { insert("{secret:\(name)}") }
      }
      if !secrets.names.isEmpty { Divider() }
      Button(L10n.Automations.manageSecrets) {
        AutomationSettingsNavigation.shared.page = .automations
        PreferencesNavigationState.shared.select(.automations)
      }
    } label: {
      Image(systemName: "key")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help(L10n.Automations.insertSecret)
    .accessibilityLabel(L10n.Automations.insertSecret)
  }
}

struct AutomationTimeoutPicker: View {
  @Binding var timeout: Double
  let range: ClosedRange<Double>

  private static let choices: [Double] = [5, 10, 15, 30, 60, 120, 300, 600]

  var body: some View {
    Picker(L10n.Automations.timeoutLabel, selection: $timeout) {
      ForEach(options, id: \.self) { seconds in
        Text(L10n.Automations.secondsValue(Int(seconds))).tag(seconds)
      }
    }
  }

  private var options: [Double] {
    var values = Self.choices.filter(range.contains)
    if !values.contains(timeout) {
      values.append(timeout)
      values.sort()
    }
    return values
  }
}

// MARK: - Script / Shortcut

/// Shown on script and Shortcut steps while Settings → Automations → Advanced
/// → "Allow script & Shortcut steps" is off.
struct AutomationCodeStepsBanner: View {
  @AppStorage(PreferencesKeys.automationsAllowCodeSteps) private var allowsCodeSteps = false

  var body: some View {
    if !allowsCodeSteps {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Label(L10n.Automations.codeStepsOffBanner, systemImage: "lock.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
        Button(L10n.Automations.allowInSettings) {
          AutomationSettingsNavigation.shared.page = .automations
          PreferencesNavigationState.shared.select(.automations)
        }
        .buttonStyle(.link)
        .font(.caption)
      }
    }
  }
}

struct RunScriptInspector: View {
  @Binding var config: AutomationRunScriptConfig

  var body: some View {
    Section {
      AutomationCodeStepsBanner()
      TextEditor(text: $config.script)
        .font(.system(.body, design: .monospaced))
        .frame(minHeight: 120)
        .scrollContentBackground(.hidden)
        .padding(4)
        .background(Radius.rect(Radius.controlXS).fill(Color.primary.opacity(0.05)))
        .accessibilityLabel(L10n.Automations.scriptLabel)
      Picker(L10n.Automations.shellLabel, selection: $config.shell) {
        ForEach(AutomationScriptShell.allCases) { shell in
          Text(verbatim: shell.executablePath).tag(shell)
        }
      }
      Toggle(L10n.Automations.loginShell, isOn: $config.useLoginShell)
      Picker(L10n.Automations.outputLabel, selection: $config.output) {
        Text(L10n.Automations.outputIgnore).tag(AutomationScriptOutput.ignore)
        Text(L10n.Automations.outputText).tag(AutomationScriptOutput.text)
        Text(L10n.Automations.outputLink).tag(AutomationScriptOutput.link)
        Text(L10n.Automations.outputFileFromScript).tag(AutomationScriptOutput.file)
      }
      AutomationTimeoutPicker(timeout: $config.timeout, range: AutomationRunScriptConfig.timeoutRange)
    } header: {
      Text(L10n.Automations.scriptLabel)
    } footer: {
      Text(L10n.Automations.scriptVariablesHelp)
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct RunShortcutInspector: View {
  @Binding var config: AutomationRunShortcutConfig
  @ObservedObject private var catalog = AutomationShortcutsCatalog.shared

  var body: some View {
    Section {
      AutomationCodeStepsBanner()
      HStack {
        Picker(L10n.Automations.shortcutPickerLabel, selection: $config.name) {
          Text(L10n.Automations.shortcutNone).tag("")
          ForEach(names, id: \.self) { name in
            Text(name).tag(name)
          }
        }
        Button {
          catalog.refresh(force: true)
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .disabled(catalog.isLoading)
        .help(L10n.Automations.refreshShortcuts)
        .accessibilityLabel(L10n.Automations.refreshShortcuts)
      }
      if !config.trimmedName.isEmpty, let url = AutomationShortcutsCatalog.openInShortcutsURL(config.trimmedName) {
        Button(L10n.Automations.openInShortcuts) {
          NSWorkspace.shared.open(url)
        }
        .buttonStyle(.link)
      }
      Picker(L10n.Automations.inputLabel, selection: $config.input) {
        Text(L10n.Automations.outputFile).tag(AutomationShortcutInput.file)
        Text(L10n.Automations.inputText).tag(AutomationShortcutInput.text)
        Text(L10n.Automations.inputLink).tag(AutomationShortcutInput.link)
        Text(L10n.Automations.inputNone).tag(AutomationShortcutInput.none)
      }
      Picker(L10n.Automations.outputLabel, selection: $config.output) {
        Text(L10n.Automations.outputIgnore).tag(AutomationShortcutOutput.ignore)
        Text(L10n.Automations.outputText).tag(AutomationShortcutOutput.text)
        Text(L10n.Automations.outputFile).tag(AutomationShortcutOutput.file)
      }
      AutomationTimeoutPicker(timeout: $config.timeout, range: AutomationRunShortcutConfig.timeoutRange)
    } footer: {
      Text(L10n.Automations.shortcutFooter)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .onAppear { catalog.refresh() }
  }

  /// Known shortcuts, plus the configured one if the list doesn't have it (yet).
  private var names: [String] {
    let name = config.trimmedName
    guard !name.isEmpty, !catalog.names.contains(name) else { return catalog.names }
    return [name] + catalog.names
  }
}

// MARK: - Share / open in app

struct ShareSheetInspector: View {
  @Binding var config: AutomationShareSheetConfig

  var body: some View {
    Section {
      Picker(L10n.Automations.serviceLabel, selection: $config.service) {
        ForEach(services, id: \.self) { service in
          Text(service.displayName).tag(service)
        }
      }
    }
  }

  private var services: [AutomationShareService] {
    var list: [AutomationShareService] = [.picker, .airDrop, .messages, .mail]
    if !list.contains(config.service) { list.append(config.service) }
    return list
  }
}

struct OpenInAppInspector: View {
  @Binding var config: AutomationOpenInAppConfig

  var body: some View {
    Section {
      LabeledContent(L10n.Automations.appLabel) {
        HStack(spacing: 8) {
          if let icon {
            Image(nsImage: icon)
              .resizable()
              .frame(width: 18, height: 18)
          }
          Text(displayName)
            .lineLimit(1)
            .foregroundStyle(config.trimmedBundleID.isEmpty ? .orange : .secondary)
          Button(L10n.Automations.chooseApp, action: chooseApp)
        }
      }
    }
  }

  private var displayName: String {
    if !config.appName.isEmpty { return config.appName }
    return config.trimmedBundleID.isEmpty ? L10n.Automations.issueApp : config.trimmedBundleID
  }

  private var icon: NSImage? {
    guard !config.trimmedBundleID.isEmpty,
          let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: config.trimmedBundleID)
    else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
  }

  private func chooseApp() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    guard panel.runModal() == .OK, let url = panel.url,
          let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier
    else { return }
    config.appBundleID = bundleID
    config.appName = FileManager.default.displayName(atPath: url.path)
      .replacingOccurrences(of: ".app", with: "")
  }
}
