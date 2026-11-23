//
//  AutomationRunEnvironment.swift
//  Snapzy
//
//  The app services automation steps touch, behind one seam so the runner and
//  step handlers can be tested without a pasteboard, network or windows.
//  Pure file transforms (resize, convert, strip metadata) don't go through
//  here: `AutomationImageTransforms` is tested directly on real files.
//

import AppKit
import Foundation

/// Progress the runner reports for the run HUD.
enum AutomationRunUpdate: Equatable {
  case started(runID: UUID, name: String)
  case step(runID: UUID, title: String)
  case finished(runID: UUID)
}

/// What a notification's action buttons act on.
struct AutomationNotificationContext: Equatable {
  enum Outcome: Equatable {
    case succeeded
    case failed
  }

  let outcome: Outcome
  let automationID: UUID
  let inputFiles: [URL]
  let link: URL?
  let savedFile: URL?
}

@MainActor
protocol AutomationRunEnvironment: AnyObject {
  /// Bake the default canvas preset into a fresh screenshot (as standard routing does).
  func prepareScreenshot(_ url: URL) -> AnnotationSessionData?
  /// Copies image(s) and returns the pasteboard change count after the write.
  func copyImages(_ urls: [URL]) -> Int
  /// Copies one video / GIF as a file reference; returns the change count after the write.
  func copyMedia(_ url: URL) -> Int
  /// Writes plain text and returns the pasteboard change count after the write.
  func copyText(_ text: String) -> Int
  var pasteboardChangeCount: Int { get }

  var isCloudConfigured: Bool { get }
  func upload(_ url: URL) async throws -> CloudUploadResult

  /// Adds a Quick Access card and returns its item id.
  func showQuickAccess(_ url: URL, kind: AutomationFileKind, sessionData: AnnotationSessionData?) async -> UUID?
  func setCloudLink(quickAccessItemID: UUID, result: CloudUploadResult)
  func openAnnotate(_ url: URL, quickAccessItemID: UUID?, sessionData: AnnotationSessionData?)
  func pin(_ url: URL) async -> Bool
  func reveal(_ urls: [URL])

  /// Renders an Annotate canvas preset (`nil` = default preset) from `source` into `destination`.
  func applyCanvasPreset(_ presetID: UUID?, source: URL, destination: URL) throws -> AnnotationSessionData?
  /// Settings of a Quick Access Optimize preset, if it still exists.
  func optimizeSettings(presetID: UUID) -> QuickAccessOptimizeSettings?
  func recognizeText(in url: URL, config: AutomationOCRConfig) async throws -> String
  func translate(_ text: String, targetLanguage: String?) async throws -> String
  /// Converts a video to a GIF written next to it; returns the GIF's URL.
  func convertToGIF(_ url: URL, config: AutomationGIFConfig) async throws -> URL
  /// The folder's URL, or `AutomationStepError.folderUnavailable`.
  func resolveFolder(_ ref: AutomationFolderRef) throws -> URL

  // Integrations (milestone 4). Defaults in `AutomationIntegrationEnvironment.swift`.
  func isUploadConfigured(_ destination: AutomationUploadDestination) -> Bool
  func upload(_ url: URL, destination: AutomationUploadDestination) async throws -> CloudUploadResult
  /// Value of a named secret (Keychain), `nil` when there is none.
  func secretValue(named name: String) -> String?
  /// Settings → Automations → Advanced → "Allow script & Shortcut steps".
  var allowsCodeSteps: Bool { get }
  /// Sends an HTTP request; `bodyFile` streams the body from disk.
  func send(_ request: URLRequest, bodyFile: URL?) async throws -> (Data, HTTPURLResponse)
  func runProcess(_ request: ProcessRequest) async throws -> ProcessOutcome
  /// Shares `items` (file URLs, a link URL or text) and returns once the user
  /// picked a service and it finished, or dismissed the picker.
  func share(_ items: [Any], service: AutomationShareService) async throws
  func open(_ items: [URL], appBundleID: String, appName: String) async throws

  func recordHistory(_ url: URL, kind: AutomationFileKind) async
  func notify(title: String, body: String, isError: Bool, context: AutomationNotificationContext?) async
  func runDidUpdate(_ update: AutomationRunUpdate)
  func recordRun(_ record: AutomationRunRecord)
}

/// Production environment backed by the app's singletons.
@MainActor
final class LiveAutomationRunEnvironment: AutomationRunEnvironment {
  func prepareScreenshot(_ url: URL) -> AnnotationSessionData? {
    PostCaptureActionHandler.shared.applyDefaultPreset(toScreenshot: url)
  }

  func copyImages(_ urls: [URL]) -> Int {
    if urls.count == 1, let url = urls.first {
      ClipboardHelper.copyImage(from: url)
    } else {
      ClipboardHelper.copyFileURLs(urls)
    }
    return NSPasteboard.general.changeCount
  }

  func copyMedia(_ url: URL) -> Int {
    ClipboardHelper.copyMediaFile(from: url)
    return NSPasteboard.general.changeCount
  }

  func copyText(_ text: String) -> Int {
    ClipboardHelper.copyText(text)
  }

  var pasteboardChangeCount: Int {
    NSPasteboard.general.changeCount
  }

  var isCloudConfigured: Bool {
    CloudShareService.shared.isConfigured
  }

  func upload(_ url: URL) async throws -> CloudUploadResult {
    try await CloudShareService.shared.upload(fileURL: url)
  }

  func showQuickAccess(_ url: URL, kind: AutomationFileKind, sessionData: AnnotationSessionData?) async -> UUID? {
    guard kind == .image else {
      return await QuickAccessManager.shared.addVideo(url: url)?.id
    }
    guard let item = await QuickAccessManager.shared.addScreenshot(url: url) else { return nil }
    if let sessionData {
      AnnotateManager.shared.saveSessionData(sessionData, for: item.id)
    }
    return item.id
  }

  func setCloudLink(quickAccessItemID: UUID, result: CloudUploadResult) {
    QuickAccessManager.shared.setCloudURL(id: quickAccessItemID, url: result.publicURL, key: result.key)
  }

  func openAnnotate(_ url: URL, quickAccessItemID: UUID?, sessionData: AnnotationSessionData?) {
    if let quickAccessItemID,
       let item = QuickAccessManager.shared.items.first(where: { $0.id == quickAccessItemID })
    {
      AnnotateManager.shared.openAnnotation(for: item)
    } else {
      AnnotateManager.shared.openAnnotation(url: url, sessionData: sessionData)
    }
  }

  func pin(_ url: URL) async -> Bool {
    await QuickAccessManager.shared.pinScreenshot(url: url) != nil
  }

  func reveal(_ urls: [URL]) {
    FileRevealer.reveal(urls)
  }

  func applyCanvasPreset(_ presetID: UUID?, source: URL, destination: URL) throws -> AnnotationSessionData? {
    let applier = ScreenshotPresetAutoApplier.shared
    guard let preset = applier.preset(id: presetID) else {
      throw AutomationStepError.canvasPresetMissing
    }
    return try applier.apply(preset, from: source, writingTo: destination)
  }

  func optimizeSettings(presetID: UUID) -> QuickAccessOptimizeSettings? {
    QuickAccessOptimizePresetStore.shared.presets.first { $0.id == presetID }?.settings
  }

  func recognizeText(in url: URL, config: AutomationOCRConfig) async throws -> String {
    try await AutomationTextRecognizer.recognize(url, config: config)
  }

  func translate(_ text: String, targetLanguage: String?) async throws -> String {
    try await AutomationTranslator.translate(text, targetLanguage: targetLanguage)
  }

  func convertToGIF(_ url: URL, config: AutomationGIFConfig) async throws -> URL {
    var options = GIFConverter.Options.default
    options.fps = config.clampedFPS
    options.maxWidth = CGFloat(config.clampedMaxWidth)
    return try await GIFConverter.convert(videoURL: url, options: options, onProgress: { _ in })
  }

  func resolveFolder(_ ref: AutomationFolderRef) throws -> URL {
    guard let url = AutomationFolderAccessStore.shared.resolve(ref) else {
      throw AutomationStepError.folderUnavailable
    }
    return url
  }

  func recordHistory(_ url: URL, kind: AutomationFileKind) async {
    // A file handed in from the CLI or Shortcuts may already have an entry.
    guard !CaptureHistoryStore.shared.hasRecord(forFilePath: url.path) else { return }
    switch kind {
    case .image:
      await PostCaptureActionHandler.shared.addScreenshotToHistory(url: url)
    case .video, .gif:
      await PostCaptureActionHandler.shared.addVideoToHistory(url: url)
    }
  }

  func notify(title: String, body: String, isError: Bool, context: AutomationNotificationContext?) async {
    let payload = context.flatMap(AutomationNotificationRouter.payload(for:))
    let delivered = await SystemNotificationService.shared.post(
      title: title,
      body: body,
      categoryIdentifier: payload?.category,
      userInfo: payload?.userInfo ?? [:]
    )
    if !delivered {
      AppToastManager.shared.show(message: body, style: isError ? .warning : .success)
    }
  }

  func runDidUpdate(_ update: AutomationRunUpdate) {
    AutomationRunHUDController.shared.handle(update)
  }

  func recordRun(_ record: AutomationRunRecord) {
    AutomationRunLog.shared.append(record)
  }
}
