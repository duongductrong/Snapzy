//
//  AutomationDisplay.swift
//  Snapzy
//
//  Localized labels for automation model values. Storage keeps raw ids.
//

import Foundation

enum AutomationDisplay {
  static let inputSymbol = "doc.badge.gearshape"

  /// A template with its query string hidden (webhook URLs often carry tokens).
  static func maskedTemplate(_ template: String) -> String {
    guard let query = template.firstIndex(of: "?") else { return template }
    return String(template[..<query]) + "?…"
  }

  /// `snapzy://automation/run?id=<uuid>` for the "Run from other apps" section.
  static func runURL(for automation: Automation) -> String {
    "snapzy://automation/run?id=\(automation.id.uuidString)"
  }

  /// Name of a stored automation, `nil` when unset or gone.
  @MainActor
  static func automationName(_ id: UUID?) -> String? {
    id.flatMap { AutomationStore.shared.automation(id: $0)?.displayName }
  }

  @MainActor
  static func choiceTitle(_ choice: AutomationAskChoice) -> String {
    switch choice {
    case .automation(let id): automationName(id) ?? L10n.Automations.unknownAutomation
    case .continueRun: L10n.Automations.askContinue
    case .stopRun: L10n.Automations.askStop
    }
  }

  /// `snapzy automation run "<name>"`, quoting the name for a POSIX shell.
  static func cliCommand(for automation: Automation) -> String {
    let name = automation.displayName.replacingOccurrences(of: "'", with: "'\\''")
    return "snapzy automation run '\(name)'"
  }
}

extension AutomationCaptureMode {
  var displayName: String {
    switch self {
    case .area: L10n.Automations.modeArea
    case .fullscreen: L10n.Automations.modeFullscreen
    case .activeWindow: L10n.Automations.modeActiveWindow
    case .applicationWindow: L10n.Automations.modeApplicationWindow
    case .recordingArea: L10n.Automations.modeRecordingArea
    case .recordingWindow: L10n.Automations.modeRecordingWindow
    case .scrolling: L10n.Automations.modeScrolling
    }
  }

  var symbol: String {
    switch self {
    case .area: "rectangle.dashed"
    case .fullscreen: "display"
    case .activeWindow: "macwindow"
    case .applicationWindow: "macwindow.on.rectangle"
    case .recordingArea: "record.circle"
    case .recordingWindow: "rectangle.inset.filled.and.person.filled"
    case .scrolling: "arrow.up.and.down.text.horizontal"
    }
  }

  static let screenshotModes: [AutomationCaptureMode] = [.area, .fullscreen, .activeWindow, .applicationWindow, .scrolling]
  static let recordingModes: [AutomationCaptureMode] = [.recordingArea, .recordingWindow]
}

extension AutomationRecordingOutput {
  var displayName: String {
    switch self {
    case .video: L10n.Automations.recordingOutputVideo
    case .gif: L10n.Automations.recordingOutputGIF
    }
  }
}

/// Groups in the "Add Step" menu.
enum AutomationStepGroup: CaseIterable, Identifiable {
  case transform
  case deliver
  case integrations
  case control

  var id: Self { self }

  var title: String {
    switch self {
    case .transform: L10n.Automations.groupTransform
    case .deliver: L10n.Automations.groupDeliver
    case .integrations: L10n.Automations.groupIntegrations
    case .control: L10n.Automations.groupControl
    }
  }

  var kinds: [AutomationStepKind] {
    switch self {
    case .transform: [.applyCanvasPreset, .resize, .convert, .stripMetadata, .ocr, .translate, .convertToGIF]
    case .deliver: [.copyImage, .upload, .copyLink, .copyText, .saveToFolder, .reveal, .pin, .showQuickAccess, .openAnnotate]
    case .integrations: [.webhook, .shareSheet, .openInApp, .runShortcut, .runScript]
    case .control: [.condition, .ask, .runAutomation, .stop, .notify]
    }
  }
}

extension AutomationStepKind {
  var displayName: String {
    switch self {
    case .copyImage, .copyFile: L10n.Automations.stepCopyImage
    case .uploadAndCopyLink: L10n.Automations.stepUploadCopyLink
    case .showQuickAccess: L10n.Automations.stepShowQuickAccess
    case .openAnnotate: L10n.Automations.stepOpenAnnotate
    case .notify: L10n.Automations.stepNotify
    case .applyCanvasPreset: L10n.Automations.stepApplyCanvasPreset
    case .resize: L10n.Automations.stepResize
    case .convert: L10n.Automations.stepConvert
    case .stripMetadata: L10n.Automations.stepStripMetadata
    case .ocr: L10n.Automations.stepOCR
    case .translate: L10n.Automations.stepTranslate
    case .convertToGIF: L10n.Automations.stepConvertToGIF
    case .upload: L10n.Automations.stepUpload
    case .copyLink: L10n.Automations.stepCopyLink
    case .copyText: L10n.Automations.stepCopyText
    case .saveToFolder: L10n.Automations.stepSaveToFolder
    case .reveal: L10n.Automations.stepReveal
    case .pin: L10n.Automations.stepPin
    case .webhook: L10n.Automations.stepWebhook
    case .runScript: L10n.Automations.stepRunScript
    case .runShortcut: L10n.Automations.stepRunShortcut
    case .shareSheet: L10n.Automations.stepShareSheet
    case .openInApp: L10n.Automations.stepOpenInApp
    case .condition: L10n.Automations.stepCondition
    case .stop: L10n.Automations.stepStop
    case .runAutomation: L10n.Automations.stepRunAutomation
    case .ask: L10n.Automations.stepAsk
    }
  }

  var symbol: String {
    switch self {
    case .copyImage, .copyFile: "doc.on.clipboard"
    case .uploadAndCopyLink: "icloud.and.arrow.up"
    case .showQuickAccess: "square.stack.3d.up"
    case .openAnnotate: "pencil.and.scribble"
    case .notify: "bell"
    case .applyCanvasPreset: "square.on.square.dashed"
    case .resize: "arrow.down.right.and.arrow.up.left"
    case .convert: "arrow.triangle.2.circlepath"
    case .stripMetadata: "eye.slash"
    case .ocr: "text.viewfinder"
    case .translate: "character.bubble"
    case .convertToGIF: "photo.stack"
    case .upload: "icloud.and.arrow.up"
    case .copyLink: "link"
    case .copyText: "doc.plaintext"
    case .saveToFolder: "folder"
    case .reveal: "magnifyingglass"
    case .pin: "pin"
    case .webhook: "paperplane"
    case .runScript: "terminal"
    case .runShortcut: "square.2.layers.3d"
    case .shareSheet: "square.and.arrow.up"
    case .openInApp: "arrow.up.forward.app"
    case .condition: "arrow.triangle.branch"
    case .stop: "stop.circle"
    case .runAutomation: "arrow.turn.down.right"
    case .ask: "list.bullet.rectangle"
    }
  }
}

extension AutomationStepAction {
  /// One-line description of the step's settings, empty when it has none.
  @MainActor
  var configSummary: String {
    switch self {
    case .applyCanvasPreset(let config):
      guard let id = config.presetID else { return L10n.Automations.canvasPresetDefault }
      return AnnotateCanvasPresetStore.shared.loadPresets().first { $0.id == id }?.name
        ?? L10n.Automations.issueCanvasPreset
    case .resize(let config):
      switch config.mode {
      case .maxDimension: return L10n.Automations.resizeSummaryMax(config.clampedMaxDimension)
      case .scalePercent: return "\(config.clampedScalePercent)%"
      }
    case .convert(let config):
      if let id = config.optimizePresetID {
        return QuickAccessOptimizePresetStore.shared.presets.first { $0.id == id }?.name ?? ""
      }
      return config.optimizeSettings.summary()
    case .ocr(let config):
      return config.includeQR ? L10n.Automations.ocrIncludesQR : ""
    case .translate(let config):
      return TranslationLanguage.language(for: config.targetLanguage)?.displayName ?? L10n.Automations.translateDefaultTarget
    case .convertToGIF(let config):
      return "\(config.clampedFPS) fps · \(config.clampedMaxWidth) px"
    case .copyLink(let template):
      return template.style == .custom ? template.custom : template.style.displayName
    case .copyText(let template):
      return template.template
    case .saveToFolder(let config):
      guard let folder = config.folder else { return L10n.Automations.issueFolder }
      let path = AutomationFolderAccessStore.shared.path(for: folder) ?? config.folderPath ?? ""
      return (path as NSString).abbreviatingWithTildeInPath
    case .uploadAndCopyLink(let format):
      return format.displayName
    case .upload(let config):
      switch config.destination {
      case .default: return ""
      case .customUploader(let id):
        return CustomUploaderStore.shared.uploader(id: id)?.name ?? L10n.Automations.issueUploader
      }
    case .webhook(let config):
      return config.url.isEmpty ? L10n.Automations.issueWebhookURL : AutomationDisplay.maskedTemplate(config.url)
    case .runScript(let config):
      return config.script.split(whereSeparator: \.isNewline).first.map(String.init) ?? L10n.Automations.issueScript
    case .runShortcut(let config):
      return config.trimmedName.isEmpty ? L10n.Automations.issueShortcut : config.trimmedName
    case .shareSheet(let config):
      return config.service.displayName
    case .openInApp(let config):
      return config.appName.isEmpty ? (config.trimmedBundleID.isEmpty ? L10n.Automations.issueApp : config.trimmedBundleID) : config.appName
    case .condition(let config):
      return AutomationConditionText.sentence(config)
    case .runAutomation(let config):
      return AutomationDisplay.automationName(config.automationID) ?? L10n.Automations.issueAutomation
    case .ask(let config):
      guard !config.choices.isEmpty else { return L10n.Automations.issueChoices }
      return config.choices.map(AutomationDisplay.choiceTitle).joined(separator: " · ")
    case .copyImage, .showQuickAccess, .openAnnotate, .notify, .stripMetadata,
         .copyFile, .reveal, .pin, .stop:
      return ""
    }
  }
}

extension AutomationLinkFormat {
  var displayName: String {
    switch self {
    case .url: L10n.Automations.linkFormatURL
    case .markdown: L10n.Automations.linkFormatMarkdown
    }
  }
}

extension AutomationLinkStyle {
  var displayName: String {
    switch self {
    case .url: L10n.Automations.linkFormatURL
    case .markdown: L10n.Automations.linkFormatMarkdown
    case .html: "HTML"
    case .bbcode: "BBCode"
    case .custom: L10n.Automations.linkStyleCustom
    }
  }
}

extension AutomationFailurePolicy {
  var displayName: String {
    switch self {
    case .stop: L10n.Automations.failureStop
    case .continue: L10n.Automations.failureContinue
    }
  }
}

extension AutomationChainIssue {
  var message: String {
    switch reason {
    case .needs(let kinds):
      if kinds.contains(.text) { return L10n.Automations.issueNeedsText }
      if kinds.contains(.link) { return L10n.Automations.issueNeedsLink }
      if kinds == [.video] { return L10n.Automations.issueNeedsVideo }
      if kinds == [.image] { return L10n.Automations.issueNeedsImage }
      return L10n.Automations.issueNeedsFile
    case .missingConfig(.folder): return L10n.Automations.issueFolder
    case .missingConfig(.template): return L10n.Automations.issueTemplate
    case .missingConfig(.canvasPreset): return L10n.Automations.issueCanvasPreset
    case .missingConfig(.uploader): return L10n.Automations.issueUploader
    case .missingConfig(.webhookURL): return L10n.Automations.issueWebhookURL
    case .missingConfig(.script): return L10n.Automations.issueScript
    case .missingConfig(.shortcut): return L10n.Automations.issueShortcut
    case .missingConfig(.app): return L10n.Automations.issueApp
    case .missingConfig(.secret(let name)): return L10n.Automations.issueSecret(name)
    case .missingConfig(.automation): return L10n.Automations.issueAutomation
    case .missingConfig(.choices): return L10n.Automations.issueChoices
    case .missingConfig(.condition): return L10n.Automations.issueCondition
    case .missingConfig(.skipRange): return L10n.Automations.issueSkipRange
    case .recursion: return L10n.Automations.issueRecursion
    case .targetCannotRun: return L10n.Automations.issueTargetCannotRun
    }
  }
}

extension Automation {
  /// One line for the settings list, e.g. "Area · Copy image, Upload".
  var summary: String {
    let mode: String = switch source {
    case .capture(let spec): spec.mode.displayName
    case .input: L10n.Automations.sourceInputShort
    case .clipboardImage: L10n.Automations.sourceClipboard
    case .unsupported: L10n.Automations.unsupported
    }
    let steps = activeActions.map(\.kind.displayName)
    let stepsText = steps.isEmpty ? L10n.Automations.noSteps : steps.joined(separator: ", ")
    return "\(mode) · \(stepsText)"
  }

  /// Uploads through the provider configured in Settings → Cloud.
  var needsCloud: Bool {
    activeActions.contains { action in
      switch action {
      case .upload(let config): config.destination == .default
      case .uploadAndCopyLink: true
      default: false
      }
    }
  }

  /// A step still needs a setting (e.g. a folder) before the automation can run.
  @MainActor
  var needsSetup: Bool {
    AutomationChainValidator.validate(self).contains { !$0.blocksRun }
  }

  var sourceSymbol: String {
    switch source {
    case .capture(let spec): spec.mode.symbol
    case .input: AutomationDisplay.inputSymbol
    case .clipboardImage: "list.clipboard"
    case .unsupported: "bolt.fill"
    }
  }
}

extension AutomationLaunchRejection {
  /// Shown to the person who started the run (toast, Shortcuts error). Never
  /// lists other automations' names, so a URL caller can't probe for them.
  var localizedMessage: String {
    switch self {
    case .notFound: L10n.Automations.rejectionNotFound
    case .ambiguousName: L10n.Automations.rejectionAmbiguous
    case .disabled: L10n.Automations.rejectionDisabled
    case .externalNotAllowed: L10n.Automations.rejectionExternalNotAllowed
    case .urlSchemeDisabled: L10n.Automations.rejectionURLSchemeDisabled
    case .unsupportedSource: L10n.Automations.rejectionUnsupportedSource
    case .needsFile: L10n.Automations.rejectionNeedsFile
    case .unsupportedFile(let name): L10n.Automations.rejectionUnsupportedFile(name)
    case .noStepAcceptsFile: L10n.Automations.rejectionNoStepAcceptsFile
    case .fileMissing(let name): L10n.Automations.rejectionFileMissing(name)
    case .permissionRequired: L10n.Automations.rejectionPermissionRequired
    case .captureInProgress: L10n.Automations.rejectionCaptureInProgress
    case .clipboardEmpty: L10n.Automations.rejectionClipboardEmpty
    case .invalidChain: L10n.Automations.rejectionInvalidChain
    case .needsReview: L10n.Automations.rejectionNeedsReview
    case .codeStepsDisabled: L10n.Automations.rejectionCodeStepsDisabled
    case .externalCodeNotAllowed: L10n.Automations.rejectionExternalCode
    }
  }
}

extension AutomationShareService {
  var displayName: String {
    switch self {
    case .picker: L10n.Automations.shareServicePicker
    case .airDrop: "AirDrop"
    case .messages: L10n.Automations.shareServiceMessages
    case .mail: L10n.Automations.shareServiceMail
    case .named(let name): name
    }
  }
}
