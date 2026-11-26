//
//  AutomationStepHandlers.swift
//  Snapzy
//
//  One handler per step kind. Handlers only wrap existing services through
//  `AutomationRunEnvironment`; the runner owns ordering, failures and fallback.
//  Each handler declares the payload kinds it accepts and produces so the
//  editor and launcher can validate a chain before it runs.
//

import CoreGraphics
import Foundation
import ImageIO

/// What a run delivered last; drives the outcome message.
enum AutomationDelivery: Equatable {
  case imageCopied
  case fileCopied
  case linkCopied
  case linkReady
  case textCopied
  case saved(URL)
}

/// Mutable state threaded through a run's steps.
struct AutomationRunState {
  let runID: UUID
  let automation: Automation
  let context: AutomationRunContext
  /// The captured or handed-in files, untouched by transforms.
  let inputFiles: [URL]
  var payload: AutomationPayload
  var sessionData: [URL: AnnotationSessionData] = [:]
  var quickAccessItemIDs: [URL: UUID] = [:]
  var didCopyImage = false
  /// Pasteboard change count right after this run's latest write. A link or
  /// text is only written when nothing else touched the pasteboard since (the
  /// user may have copied something while an upload was running).
  var ownPasteboardChangeCount: Int?
  var uploadResult: CloudUploadResult?
  var linkText: String?
  var didCopyLink = false
  var didCopyText = false
  var uploadFailure: AutomationUploadFailure?
  var wantsNotification = false
  var lastDelivery: AutomationDelivery?
  /// Working files something still shows (Quick Access, pin, Annotate, pasteboard).
  var retainedFiles: Set<URL> = []
  /// Non-fatal notes for the run log (e.g. "WebP unavailable, wrote PNG").
  var warnings: [String] = []
  /// Secret values a step resolved; masked out of errors and the run log.
  var secretValues: Set<String> = []
  /// A note the step that just ran leaves for its run log row (e.g. "3 areas
  /// covered"). The runner takes it after each step.
  var stepDetail: String?

  init(
    runID: UUID,
    automation: Automation,
    files: [AutomationFile],
    context: AutomationRunContext
  ) {
    self.runID = runID
    self.automation = automation
    self.context = context
    inputFiles = files.map(\.original)
    payload = AutomationPayload(files: files)
  }

  var files: [URL] { payload.files.map(\.url) }
  var primaryFile: URL? { files.first }

  func kind(of file: URL) -> AutomationFileKind {
    payload.files.first { $0.url == file }?.kind ?? .image
  }

  /// True when every file is a still image (what "Image copied" means).
  var isImageOnly: Bool {
    payload.files.allSatisfy { $0.kind == .image }
  }

  /// Swaps the file at `url` for a transformed one, keeping its original.
  /// Quick Access / session state follow the file.
  mutating func replace(_ url: URL, with newURL: URL, kind: AutomationFileKind) {
    guard let index = payload.files.firstIndex(where: { $0.url == url }) else { return }
    let original = payload.files[index].original
    payload.files[index] = AutomationFile(url: newURL, kind: kind, original: original)
    if let itemID = quickAccessItemIDs.removeValue(forKey: url) {
      quickAccessItemIDs[newURL] = itemID
    }
    sessionData.removeValue(forKey: url)
  }

  /// Marks working files that must outlive the run.
  mutating func retain(_ urls: [URL]) {
    for url in urls where payload.files.contains(where: { $0.url == url && $0.isWorkingCopy }) {
      retainedFiles.insert(url)
    }
  }

  /// Template values for the current payload.
  func variables() -> AutomationVariables {
    let size = payload.files.first.flatMap { file -> CGSize? in
      guard file.kind == .image else { return nil }
      return Self.pixelSize(of: file.url)
    }
    return AutomationVariables(context: context, payload: payload, pixelSize: size)
  }

  nonisolated static func pixelSize(of url: URL) -> CGSize? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    return CGSize(width: width, height: height)
  }
}

enum AutomationUploadFailure: Equatable {
  case notConfigured
  case failed(String)
}

enum AutomationStepError: LocalizedError, Equatable {
  case cloudNotConfigured
  case noFile
  case noText
  case noLink
  case noTextFound
  case canvasPresetMissing
  case renderFailed
  case folderUnavailable
  case translationUnavailable(String)
  case failed(String)
  // Milestone 4
  case uploaderMissing
  case codeStepsDisabled
  case secretMissing(String)
  case invalidURL
  case httpStatus(Int, String)
  case timedOut(Int)
  case processFailed(Int32, String)
  case shortcutNotFound(String)
  case shareServiceUnavailable
  case appNotFound(String)
  case outputFileInvalid

  var errorDescription: String? {
    switch self {
    case .cloudNotConfigured: L10n.Automations.errorCloudNotConfigured
    case .noFile: L10n.Automations.errorNoFile
    case .noText: L10n.Automations.errorNoText
    case .noLink: L10n.Automations.errorNoLink
    case .noTextFound: L10n.Automations.errorNoTextFound
    case .canvasPresetMissing: L10n.Automations.errorCanvasPresetMissing
    case .renderFailed: L10n.Automations.errorRenderFailed
    case .folderUnavailable: L10n.Automations.errorFolderUnavailable
    case .translationUnavailable(let reason): reason
    case .failed(let reason): reason
    case .uploaderMissing: L10n.Automations.errorUploaderMissing
    case .codeStepsDisabled: L10n.Automations.errorCodeStepsDisabled
    case .secretMissing(let name): L10n.Automations.secretErrorNotFound(name)
    case .invalidURL: L10n.Automations.errorInvalidWebhookURL
    case .httpStatus(let status, let body):
      body.isEmpty ? L10n.Automations.errorHTTPStatus(status) : "\(L10n.Automations.errorHTTPStatus(status)): \(body)"
    case .timedOut(let seconds): L10n.Automations.errorTimedOut(seconds)
    case .processFailed(let status, let stderr):
      stderr.isEmpty ? L10n.Automations.errorExitStatus(Int(status)) : "\(L10n.Automations.errorExitStatus(Int(status))): \(stderr)"
    case .shortcutNotFound(let name): L10n.Automations.errorShortcutNotFound(name)
    case .shareServiceUnavailable: L10n.Automations.errorShareUnavailable
    case .appNotFound(let name): L10n.Automations.errorAppNotFound(name)
    case .outputFileInvalid: L10n.Automations.errorOutputFileInvalid
    }
  }
}

@MainActor
protocol AutomationStepHandler {
  /// Payload kinds the step can work on (any of them). The runner hands a step
  /// only the files it accepts and skips it when nothing it accepts is present.
  func accepts(_ action: AutomationStepAction) -> Set<AutomationPayloadKind>
  /// Kinds available after the step, given the kinds before it.
  func produces(_ action: AutomationStepAction, given: Set<AutomationPayloadKind>) -> Set<AutomationPayloadKind>
  var trust: AutomationTrustTier { get }
  func run(
    _ action: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws
}

extension AutomationStepHandler {
  func produces(_: AutomationStepAction, given: Set<AutomationPayloadKind>) -> Set<AutomationPayloadKind> {
    given
  }

  var trust: AutomationTrustTier { .local }
}

@MainActor
enum AutomationStepRegistry {
  static func handler(for kind: AutomationStepKind) -> AutomationStepHandler {
    switch kind {
    case .copyImage, .copyFile: CopyFileStepHandler()
    case .uploadAndCopyLink: LegacyUploadAndCopyLinkStepHandler()
    case .showQuickAccess: ShowQuickAccessStepHandler()
    case .openAnnotate: OpenAnnotateStepHandler()
    case .notify: NotifyStepHandler()
    case .applyCanvasPreset: ApplyCanvasPresetStepHandler()
    case .resize: ResizeStepHandler()
    case .convert: ConvertStepHandler()
    case .stripMetadata: StripMetadataStepHandler()
    case .ocr: OCRStepHandler()
    case .translate: TranslateStepHandler()
    case .convertToGIF: ConvertToGIFStepHandler()
    case .upload: UploadStepHandler()
    case .copyLink: CopyLinkStepHandler()
    case .copyText: CopyTextStepHandler()
    case .saveToFolder: SaveToFolderStepHandler()
    case .reveal: RevealStepHandler()
    case .pin: PinStepHandler()
    case .webhook: WebhookStepHandler()
    case .runScript: RunScriptStepHandler()
    case .runShortcut: RunShortcutStepHandler()
    case .shareSheet: ShareSheetStepHandler()
    case .openInApp: OpenInAppStepHandler()
    case .condition, .stop, .runAutomation, .ask: ControlStepHandler()
    case .redact: RedactStepHandler()
    case .aiAnnotate: AIAnnotateStepHandler()
    }
  }

  static func accepts(_ action: AutomationStepAction, _ fileKind: AutomationFileKind) -> Bool {
    handler(for: action.kind).accepts(action).contains(AutomationPayloadKind(fileKind))
  }
}

// MARK: - Milestone 1 handlers

/// Copies the file: image data for one still image, a file reference for a
/// video / GIF or several files. Serves both `copyImage` and `copyFile`.
struct CopyFileStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { AutomationPayloadKind.files }

  func run(
    _: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard !files.isEmpty else { throw AutomationStepError.noFile }
    state.ownPasteboardChangeCount = AutomationStepCopy.copy(files, state: state, environment: environment)
    state.didCopyImage = true
    state.retain(files)
    let isImage = files.allSatisfy { state.kind(of: $0) == .image }
    state.lastDelivery = isImage ? .imageCopied : .fileCopied
  }
}

@MainActor
enum AutomationStepCopy {
  /// Writes `files` to the pasteboard the way their kind needs; returns the change count.
  static func copy(_ files: [URL], state: AutomationRunState, environment: AutomationRunEnvironment) -> Int {
    if files.count == 1, let file = files.first, state.kind(of: file) != .image {
      return environment.copyMedia(file)
    }
    return environment.copyImages(files)
  }

  /// Writes text unless something else wrote to the pasteboard since this run's
  /// last write. Returns whether it was written.
  static func copyText(_ text: String, state: inout AutomationRunState, environment: AutomationRunEnvironment) -> Bool {
    let untouched = state.ownPasteboardChangeCount.map { $0 == environment.pasteboardChangeCount } ?? true
    guard untouched else { return false }
    state.ownPasteboardChangeCount = environment.copyText(text)
    return true
  }
}

struct ShowQuickAccessStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { AutomationPayloadKind.files }

  func run(
    _: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    for file in files where state.quickAccessItemIDs[file] == nil {
      guard let itemID = await environment.showQuickAccess(
        file,
        kind: state.kind(of: file),
        sessionData: state.sessionData[file]
      ) else { continue }
      state.quickAccessItemIDs[file] = itemID
      state.retain([file])
      if file == state.primaryFile, let result = state.uploadResult {
        environment.setCloudLink(quickAccessItemID: itemID, result: result)
      }
    }
  }
}

struct OpenAnnotateStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { [.image] }

  func run(
    _: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard let file = files.first else { throw AutomationStepError.noFile }
    state.retain([file])
    environment.openAnnotate(file, quickAccessItemID: state.quickAccessItemIDs[file], sessionData: state.sessionData[file])
  }
}

struct NotifyStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { AutomationPayloadKind.all }

  func run(
    _: AutomationStepAction,
    files _: [URL],
    state: inout AutomationRunState,
    environment _: AutomationRunEnvironment
  ) async throws {
    // Posted once by the runner after every step ran, so it can report the outcome.
    state.wantsNotification = true
  }
}

/// Milestone 1 data is migrated on load; this only runs for an automation built
/// in code with the legacy action.
struct LegacyUploadAndCopyLinkStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { AutomationPayloadKind.files }

  func produces(_: AutomationStepAction, given: Set<AutomationPayloadKind>) -> Set<AutomationPayloadKind> {
    given.union([.link])
  }

  var trust: AutomationTrustTier { .network }

  func run(
    _ action: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard case .uploadAndCopyLink(let format) = action else { return }
    try await UploadStepHandler().run(.upload(AutomationUploadConfig()), files: files, state: &state, environment: environment)
    try await CopyLinkStepHandler().run(
      .copyLink(AutomationLinkTemplate(format)),
      files: files,
      state: &state,
      environment: environment
    )
  }
}
