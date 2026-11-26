//
//  AutomationStepInspector.swift
//  Snapzy
//
//  Right pane for a selected step: its settings (one small view per kind in
//  `StepInspectors/`), the enable switch and what happens when it fails.
//

import SwiftUI

struct AutomationStepInspector: View {
  @Binding var step: AutomationStep
  let issues: [AutomationChainIssue]
  let isCloudConfigured: Bool
  /// The automation being edited (Run Automation / Ask can't pick it).
  var automationID: UUID?
  /// Steps below this one (bounds "Otherwise skip").
  var stepsAfter = Automation.maxSteps

  var body: some View {
    Form {
      Section {
        HStack(spacing: 10) {
          Image(systemName: step.action?.kind.symbol ?? "questionmark.square.dashed")
            .font(.title3)
            .frame(width: 24)
          Text(step.action?.kind.displayName ?? L10n.Automations.unsupported)
            .font(.headline)
          Spacer()
          Toggle(L10n.Automations.stepEnabled, isOn: $step.isEnabled)
            .toggleStyle(.switch)
            .labelsHidden()
        }
        if let description = step.action?.kind.inspectorDescription {
          Text(description)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(issues, id: \.stepID) { issue in
          Label(issue.message, systemImage: issue.blocksRun ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(issue.blocksRun ? .red : .orange)
        }
        if case .upload(let config)? = step.action, config.destination == .default, !isCloudConfigured {
          Label(L10n.Automations.cloudWarning, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }

      if step.action != nil {
        configSection
      }

      Section {
        Picker(L10n.Automations.failureLabel, selection: $step.onFailure) {
          ForEach(AutomationFailurePolicy.allCases) { policy in
            Text(policy.displayName).tag(policy)
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  @ViewBuilder
  private var configSection: some View {
    switch step.action {
    case .applyCanvasPreset(let config)?:
      CanvasPresetInspector(config: binding(config, AutomationStepAction.applyCanvasPreset))
    case .resize(let config)?:
      ResizeInspector(config: binding(config, AutomationStepAction.resize))
    case .convert(let config)?:
      ConvertInspector(config: binding(config, AutomationStepAction.convert))
    case .ocr(let config)?:
      OCRInspector(config: binding(config, AutomationStepAction.ocr))
    case .translate(let config)?:
      TranslateInspector(config: binding(config, AutomationStepAction.translate))
    case .convertToGIF(let config)?:
      GIFInspector(config: binding(config, AutomationStepAction.convertToGIF))
    case .copyLink(let template)?:
      LinkTemplateInspector(template: binding(template, AutomationStepAction.copyLink))
    case .copyText(let template)?:
      TextTemplateInspector(template: binding(template, AutomationStepAction.copyText))
    case .saveToFolder(let config)?:
      SaveToFolderInspector(config: binding(config, AutomationStepAction.saveToFolder))
    case .upload(let config)?:
      UploadDestinationInspector(config: binding(config, AutomationStepAction.upload))
    case .webhook(let config)?:
      WebhookInspector(config: binding(config, AutomationStepAction.webhook))
    case .runScript(let config)?:
      RunScriptInspector(config: binding(config, AutomationStepAction.runScript))
    case .runShortcut(let config)?:
      RunShortcutInspector(config: binding(config, AutomationStepAction.runShortcut))
    case .shareSheet(let config)?:
      ShareSheetInspector(config: binding(config, AutomationStepAction.shareSheet))
    case .openInApp(let config)?:
      OpenInAppInspector(config: binding(config, AutomationStepAction.openInApp))
    case .condition(let config)?:
      ConditionInspector(config: binding(config, AutomationStepAction.condition), stepsAfter: stepsAfter)
    case .runAutomation(let config)?:
      RunAutomationInspector(config: binding(config, AutomationStepAction.runAutomation), excluding: automationID)
    case .ask(let config)?:
      AskInspector(config: binding(config, AutomationStepAction.ask), excluding: automationID)
    case .redact(let config)?:
      RedactInspector(config: binding(config, AutomationStepAction.redact))
    case .aiAnnotate(let config)?:
      AIAnnotateInspector(config: binding(config, AutomationStepAction.aiAnnotate))
    default:
      EmptyView()
    }
  }

  /// A binding to a step's config that writes back through `make`.
  private func binding<Config>(_ current: Config, _ make: @escaping (Config) -> AutomationStepAction) -> Binding<Config> {
    Binding(
      get: { current },
      set: { step.content = .action(make($0)) }
    )
  }
}

extension AutomationStepKind {
  /// What the step does, shown under its title in the inspector.
  var inspectorDescription: String? {
    switch self {
    case .applyCanvasPreset: L10n.Automations.describeCanvasPreset
    case .resize: L10n.Automations.describeResize
    case .convert: L10n.Automations.describeConvert
    case .stripMetadata: L10n.Automations.describeStripMetadata
    case .ocr: L10n.Automations.describeOCR
    case .translate: L10n.Automations.describeTranslate
    case .convertToGIF: L10n.Automations.describeConvertToGIF
    case .upload: L10n.Automations.describeUpload
    case .copyLink: L10n.Automations.describeCopyLink
    case .copyText: L10n.Automations.describeCopyText
    case .saveToFolder: L10n.Automations.describeSaveToFolder
    case .reveal: L10n.Automations.describeReveal
    case .pin: L10n.Automations.describePin
    case .notify: L10n.Automations.describeNotify
    case .webhook: L10n.Automations.describeWebhook
    case .runScript: L10n.Automations.describeRunScript
    case .runShortcut: L10n.Automations.describeRunShortcut
    case .shareSheet: L10n.Automations.describeShareSheet
    case .openInApp: L10n.Automations.describeOpenInApp
    case .copyImage, .copyFile: L10n.Automations.describeCopyImage
    case .condition: L10n.Automations.describeCondition
    case .stop: L10n.Automations.describeStop
    case .runAutomation: L10n.Automations.describeRunAutomation
    case .ask: L10n.Automations.describeAsk
    case .redact: L10n.Automations.describeRedact
    case .aiAnnotate: L10n.Automations.describeAIAnnotate
    case .showQuickAccess, .openAnnotate, .uploadAndCopyLink: nil
    }
  }
}

/// "Tokens" popover listing the variables a template can use.
struct AutomationTokenHelpButton: View {
  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      Image(systemName: "curlybraces.square")
    }
    .buttonStyle(.borderless)
    .help(L10n.Automations.tokensHelp)
    .accessibilityLabel(L10n.Automations.tokensHelp)
    .popover(isPresented: $isPresented, arrowEdge: .trailing) {
      VStack(alignment: .leading, spacing: 8) {
        Text(L10n.Automations.tokensHelp).font(.headline)
        tokenList(AutomationVariables.payloadTokens)
        Divider()
        tokenList(AutomationVariables.contextTokens)
        Divider()
        tokenList(AutomationVariables.namingTokens)
      }
      .padding(14)
      .frame(width: 260)
    }
  }

  private func tokenList(_ tokens: [String]) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      ForEach(tokens, id: \.self) { token in
        Text(token)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
      }
    }
  }
}
