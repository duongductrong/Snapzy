//
//  PostCaptureActionHandler.swift
//  Snapzy
//
//  Executes post-capture actions based on user preferences.
//
//  Milestone 6: a standard capture runs its default after-capture automation
//  (`AutomationStore.defaultAutomation(for:)`) through `AutomationRunner`.
//  `executeActions` stays as the fallback when no default automation is wired
//  (tests) and as the reference for the dual-run parity diagnostics.
//

import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "PostCaptureActionHandler")

/// Handles execution of post-capture actions based on user preferences
@MainActor
final class PostCaptureActionHandler {

  static let shared = PostCaptureActionHandler(
    preferences: PreferencesManager.shared,
    quickAccess: QuickAccessManager.shared,
    fileAccess: SandboxFileAccessManager.shared,
    screenshotPresetAutoApplier: ScreenshotPresetAutoApplier.shared,
    defaultAutomation: { AutomationStore.shared.defaultAutomation(for: $0) }
  )

  private let preferences: PreferencesProviding
  private let quickAccess: QuickAccessManaging
  private let fileAccess: SandboxFileAccessing
  private let screenshotPresetAutoApplier: ScreenshotPresetAutoApplier
  /// The default after-capture automation for a capture type; `nil` runs the legacy matrix path.
  private let defaultAutomation: ((CaptureType) -> Automation?)?

  init(
    preferences: PreferencesProviding,
    quickAccess: QuickAccessManaging,
    fileAccess: SandboxFileAccessing,
    screenshotPresetAutoApplier: ScreenshotPresetAutoApplier,
    defaultAutomation: ((CaptureType) -> Automation?)? = nil
  ) {
    self.preferences = preferences
    self.quickAccess = quickAccess
    self.fileAccess = fileAccess
    self.screenshotPresetAutoApplier = screenshotPresetAutoApplier
    self.defaultAutomation = defaultAutomation
  }

  // MARK: - Public API

  /// Execute all enabled post-capture actions for a screenshot
  @discardableResult
  func handleScreenshotCapture(
    url: URL,
    pinToScreen: Bool = false,
    routing: PostCaptureRouting = .standard
  ) async -> QuickAccessItem? {
    if case .automation(let runID) = routing {
      await AutomationRunner.shared.complete(runID: runID, capturedURLs: [url])
      return nil
    }
    if case .captureToolbar(let sessionID) = routing {
      CaptureToolbarController.shared.present(url: url, sessionID: sessionID)
      return nil
    }

    if let automation = defaultAutomation?(.screenshot) {
      // The run adds the History entry itself.
      return await runDefaultAutomation(automation, type: .screenshot, urls: [url], pinToScreen: pinToScreen)
    }

    let quickAccessItem = await executeActions(
      for: .screenshot,
      url: url,
      pinToScreen: pinToScreen
    )

    // Add to capture history
    await addScreenshotToHistory(url: url)

    return quickAccessItem
  }

  /// Execute post-capture actions for a batch of screenshots, such as
  /// fullscreen capture across multiple displays.
  func handleScreenshotCaptures(urls: [URL], routing: PostCaptureRouting = .standard) async {
    if case .automation(let runID) = routing {
      await AutomationRunner.shared.complete(runID: runID, capturedURLs: urls)
      return
    }
    if case .captureToolbar(let sessionID) = routing, let first = urls.first {
      CaptureToolbarController.shared.present(url: first, sessionID: sessionID)
      return
    }

    let validURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    guard !validURLs.isEmpty else {
      DiagnosticLogger.shared.log(
        .warning,
        .action,
        "Screenshot batch post-capture skipped; no files",
        context: ["requestedCount": "\(urls.count)"]
      )
      return
    }

    guard validURLs.count > 1 else {
      await handleScreenshotCapture(url: validURLs[0])
      return
    }

    if let automation = defaultAutomation?(.screenshot) {
      await runDefaultAutomation(automation, type: .screenshot, urls: validURLs)
      return
    }

    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Screenshot batch post-capture started",
      context: ["count": "\(validURLs.count)"]
    )

    var sessionDataByURL: [URL: AnnotationSessionData] = [:]
    for url in validURLs {
      if let sessionData = screenshotPresetAutoApplier.applyDefaultPresetIfNeeded(to: url) {
        sessionDataByURL[url] = sessionData
        persistAnnotationSessionIfNeeded(sessionData, for: url)
      }
    }

    if preferences.isActionEnabled(.copyFile, for: .screenshot) {
      ClipboardHelper.copyFileURLs(validURLs)
      DiagnosticLogger.shared.log(
        .info,
        .clipboard,
        "Screenshot batch file URLs copied to clipboard",
        context: ["count": "\(validURLs.count)"]
      )
    }

    if preferences.isActionEnabled(.showQuickAccess, for: .screenshot) {
      for url in validURLs {
        let item = await quickAccess.addScreenshot(url: url)
        if let item, let sessionData = sessionDataByURL[url] {
          AnnotateManager.shared.saveSessionData(sessionData, for: item.id)
        }
      }
    }

    if preferences.isActionEnabled(.openAnnotate, for: .screenshot), let firstURL = validURLs.first {
      AnnotateManager.shared.openAnnotation(url: firstURL, sessionData: sessionDataByURL[firstURL])
      DiagnosticLogger.shared.log(
        .info,
        .annotate,
        "Screenshot batch opened first capture in Annotate",
        context: [
          "fileName": firstURL.lastPathComponent,
          "skippedCount": "\(max(0, validURLs.count - 1))",
        ]
      )
    }

    for url in validURLs {
      await addScreenshotToHistory(url: url)
    }
  }

  /// Bake the default Annotate canvas preset into a fresh screenshot, as every
  /// routed capture does, and persist the editable session. Shared with automations.
  func applyDefaultPreset(toScreenshot url: URL) -> AnnotationSessionData? {
    let sessionData = screenshotPresetAutoApplier.applyDefaultPresetIfNeeded(to: url)
    if let sessionData {
      persistAnnotationSessionIfNeeded(sessionData, for: url)
    }
    return sessionData
  }

  /// Add a screenshot to capture history
  func addScreenshotToHistory(url: URL) async {
    guard FileManager.default.fileExists(atPath: url.path) else {
      DiagnosticLogger.shared.log(
        .warning,
        .history,
        "Screenshot history add skipped; file missing",
        context: ["fileName": url.lastPathComponent]
      )
      return
    }

    let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil)
    var width: Int?
    var height: Int?
    if let source = imageSource {
      if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
        if let pixelWidth = properties[kCGImagePropertyPixelWidth as String] as? Int {
          width = pixelWidth
        }
        if let pixelHeight = properties[kCGImagePropertyPixelHeight as String] as? Int {
          height = pixelHeight
        }
      }
    }

    CaptureHistoryStore.shared.addCapture(
      url: url,
      captureType: .screenshot,
      width: width,
      height: height
    )
    DiagnosticLogger.shared.log(
      .debug,
      .history,
      "Screenshot queued for history",
      context: [
        "fileName": url.lastPathComponent,
        "width": width.map { "\($0)" } ?? "unknown",
        "height": height.map { "\($0)" } ?? "unknown",
      ]
    )
  }

  /// Execute all enabled post-capture actions for a video recording
  /// - Parameter skipQuickAccess: When true, skip adding to QuickAccess (e.g. GIF flow already added it)
  func handleVideoCapture(url: URL, skipQuickAccess: Bool = false) async {
    if let automation = defaultAutomation?(.recording) {
      await runDefaultAutomation(automation, type: .recording, urls: [url], skipQuickAccess: skipQuickAccess)
      return
    }
    await executeActions(for: .recording, url: url, skipQuickAccess: skipQuickAccess)

    // Add to capture history
    await addVideoToHistory(url: url)
  }

  /// Add a video or GIF to capture history
  func addVideoToHistory(url: URL) async {
    guard FileManager.default.fileExists(atPath: url.path) else {
      DiagnosticLogger.shared.log(
        .warning,
        .history,
        "Video history add skipped; file missing",
        context: ["fileName": url.lastPathComponent]
      )
      return
    }

    let isGIF = url.pathExtension.lowercased() == "gif"
    let captureType: CaptureHistoryType = isGIF ? .gif : .video

    var duration: TimeInterval?
    var width: Int?
    var height: Int?

    if !isGIF {
      let asset = AVURLAsset(url: url)
      let assetDuration = (try? await asset.load(.duration)) ?? .invalid
      let seconds = CMTimeGetSeconds(assetDuration)
      if seconds.isFinite && seconds > 0 {
        duration = seconds
      }

      let videoTrack = try? await asset.loadTracks(withMediaType: .video).first
      if let track = videoTrack {
        let naturalSize = (try? await track.load(.naturalSize)) ?? .zero
        width = Int(naturalSize.width)
        height = Int(naturalSize.height)
      }
    }

    CaptureHistoryStore.shared.addCapture(
      url: url,
      captureType: captureType,
      duration: duration,
      width: width,
      height: height
    )
    DiagnosticLogger.shared.log(
      .debug,
      .history,
      "Video queued for history",
      context: [
        "fileName": url.lastPathComponent,
        "type": captureType.rawValue,
        "duration": duration.map { "\($0)" } ?? "unknown",
        "width": width.map { "\($0)" } ?? "unknown",
        "height": height.map { "\($0)" } ?? "unknown",
      ]
    )
  }

  /// Re-run clipboard automation after an in-place edit save succeeds.
  /// Screenshots: decode/encode run off-main (serialized so rapid successive
  /// saves keep last-save-wins clipboard order); only the pasteboard write
  /// hops back to main. Videos stay on the cheap file-URL path.
  func copyEditedCaptureToClipboardIfEnabled(for captureType: CaptureType, url: URL) {
    guard preferences.isActionEnabled(.copyFile, for: captureType) else {
      DiagnosticLogger.shared.log(
        .debug,
        .clipboard,
        "Edited capture clipboard copy skipped by preference",
        context: ["captureType": captureType.rawValue, "fileName": url.lastPathComponent]
      )
      return
    }

    if captureType == .recording {
      copyToClipboard(url: url, isVideo: true)
    } else {
      let previous = editedClipboardTask
      editedClipboardTask = Task.detached(priority: .userInitiated) {
        await previous?.value
        await ClipboardHelper.copyImageOffMain(from: url)
      }
    }

    let label = captureType == .screenshot ? "screenshot" : "recording"
    logger.debug("Clipboard re-copy executed for edited \(url.lastPathComponent)")
    DiagnosticLogger.shared.log(
      .info,
      .clipboard,
      "Edited capture copied to clipboard",
      context: ["captureType": label, "fileName": url.lastPathComponent]
    )
  }

  /// Chained task serializing off-main edited-capture clipboard writes.
  private var editedClipboardTask: Task<Void, Never>?

  // MARK: - Default after-capture automation (milestone 6)

  /// Runs the default automation on a standard capture. Returns the Quick
  /// Access (or pinned) item the run created for the first file, if any.
  @discardableResult
  private func runDefaultAutomation(
    _ automation: Automation,
    type: CaptureType,
    urls: [URL],
    pinToScreen: Bool = false,
    skipQuickAccess: Bool = false
  ) async -> QuickAccessItem? {
    let scopedAccess = urls.map { fileAccess.beginAccessingURL($0) }
    defer { scopedAccess.forEach { $0.stop() } }

    guard let firstURL = urls.first, FileManager.default.fileExists(atPath: firstURL.path) else {
      DiagnosticLogger.shared.log(
        .error,
        .action,
        "Post-capture actions skipped; file missing",
        context: ["captureType": type.rawValue, "fileName": urls.first?.lastPathComponent ?? ""]
      )
      return nil
    }

    logParity(automation, type: type, pinToScreen: pinToScreen, skipQuickAccess: skipQuickAccess)
    let environment = StandardCaptureRunEnvironment(
      quickAccess: quickAccess,
      prepare: { [weak self] url in self?.applyDefaultPreset(toScreenshot: url) }
    )
    await AutomationRunner.shared.runDefault(
      automation,
      type: type,
      files: urls,
      pinToScreen: pinToScreen,
      skipQuickAccess: skipQuickAccess,
      environment: environment
    )
    return environment.item(for: firstURL)
  }

  /// Dual-run diagnostics (one beta): what the legacy matrix handler would have
  /// done vs. what the default automation runs. A plain default must match.
  private func logParity(_ automation: Automation, type: CaptureType, pinToScreen: Bool, skipQuickAccess: Bool) {
    var matrix: [AfterCaptureAction: Bool] = [:]
    for action in AfterCaptureAction.allCases {
      matrix[action] = preferences.isActionEnabled(action, for: type)
    }
    let legacy = AutomationSystemDefault.legacyEffects(
      type: type,
      matrix: matrix,
      pinToScreen: pinToScreen,
      skipQuickAccess: skipQuickAccess
    )
    let steps = AutomationSystemDefault.runtimeSteps(
      automation.steps,
      type: type,
      pinToScreen: pinToScreen,
      skipQuickAccess: skipQuickAccess
    )
    let actual = AutomationSystemDefault.effects(of: steps)
    guard legacy != actual else { return }
    // A custom pipeline differs on purpose; a simple one never should.
    DiagnosticLogger.shared.log(
      automation.isCustomizedSystemDefault ? .debug : .warning,
      .action,
      "After-capture parity mismatch",
      context: [
        "captureType": type.rawValue,
        "legacy": legacy.map(\.rawValue).joined(separator: ","),
        "automation": actual.map(\.rawValue).joined(separator: ","),
        "custom": automation.isCustomizedSystemDefault ? "true" : "false",
      ]
    )
  }

  // MARK: - Private

  @discardableResult
  private func executeActions(
    for captureType: CaptureType,
    url: URL,
    skipQuickAccess: Bool = false,
    pinToScreen: Bool = false
  ) async -> QuickAccessItem? {
    let scopedAccess = fileAccess.beginAccessingURL(url)
    defer { scopedAccess.stop() }

    // Validate file exists before processing
    guard FileManager.default.fileExists(atPath: url.path) else {
      logger.error("Capture file missing at \(url.lastPathComponent), skipping post-capture actions")
      DiagnosticLogger.shared.log(
        .error,
        .action,
        "Post-capture actions skipped; file missing",
        context: ["captureType": captureType.rawValue, "fileName": url.lastPathComponent]
      )
      return nil
    }

    logger.info("Executing post-capture actions for \(captureType == .screenshot ? "screenshot" : "recording"): \(url.lastPathComponent)")
    let screenshotSessionData = captureType == .screenshot
      ? screenshotPresetAutoApplier.applyDefaultPresetIfNeeded(to: url)
      : nil
    if let screenshotSessionData {
      persistAnnotationSessionIfNeeded(screenshotSessionData, for: url)
    }
    let isTempCapture = TempCaptureManager.shared.isTempFile(url)
    let locationLabel = isTempCapture ? "temp" : "export"
    let typeLabel = captureType == .screenshot ? "screenshot" : "recording"
    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Post-capture actions started",
      context: [
        "captureType": typeLabel,
        "fileName": url.lastPathComponent,
        "location": locationLabel,
        "skipQuickAccess": skipQuickAccess ? "true" : "false",
      ]
    )

    // Copy file to clipboard before slower UI actions. Auto-copy is expected
    // to update immediately after capture; it must not depend on thumbnail
    // generation, Quick Access animations, or editor opening.
    if preferences.isActionEnabled(.copyFile, for: captureType) {
      copyToClipboard(url: url, isVideo: captureType == .recording)
      let label = captureType == .screenshot ? "screenshot" : "recording"
      logger.debug("Clipboard copy executed for \(url.lastPathComponent)")
      DiagnosticLogger.shared.log(
        .info,
        .clipboard,
        "Post-capture clipboard action executed",
        context: ["captureType": label, "fileName": url.lastPathComponent]
      )
    }

    // Show Quick Access Overlay
    var quickAccessItem: QuickAccessItem?
    if !skipQuickAccess && preferences.isActionEnabled(.showQuickAccess, for: captureType) {
      switch captureType {
      case .screenshot:
        quickAccessItem = await quickAccess.addScreenshot(url: url)
        if let quickAccessItem, let screenshotSessionData {
          AnnotateManager.shared.saveSessionData(screenshotSessionData, for: quickAccessItem.id)
        }
      case .recording:
        quickAccessItem = await quickAccess.addVideo(url: url)
      }
      logger.debug("Quick access overlay shown for \(url.lastPathComponent)")
      DiagnosticLogger.shared.log(
        .info,
        .action,
        "Post-capture quick access action executed",
        context: ["captureType": typeLabel, "fileName": url.lastPathComponent]
      )
    } else {
      DiagnosticLogger.shared.log(
        .debug,
        .action,
        "Post-capture quick access action skipped",
        context: [
          "captureType": typeLabel,
          "fileName": url.lastPathComponent,
          "skipQuickAccess": skipQuickAccess ? "true" : "false",
        ]
      )
    }

    if captureType == .screenshot && pinToScreen {
      if let quickAccessItem {
        quickAccess.pinScreenshot(id: quickAccessItem.id)
      } else {
        quickAccessItem = await quickAccess.pinScreenshot(url: url)
      }
      DiagnosticLogger.shared.log(
        .info,
        .action,
        "Post-capture pin action executed",
        context: ["fileName": url.lastPathComponent]
      )
    }

    // Open Annotate Editor (screenshots only)
    if captureType == .screenshot && preferences.isActionEnabled(.openAnnotate, for: captureType) {
      if let quickAccessItem {
        AnnotateManager.shared.openAnnotation(for: quickAccessItem)
      } else {
        AnnotateManager.shared.openAnnotation(url: url, sessionData: screenshotSessionData)
      }
      logger.debug("Annotate editor opened for \(url.lastPathComponent)")
      DiagnosticLogger.shared.log(
        .info,
        .annotate,
        "Post-capture annotate action executed",
        context: ["fileName": url.lastPathComponent]
      )
    }

    return quickAccessItem
  }

  /// Copy file to clipboard (format-aware image data for screenshots, file URL for videos)
  private func copyToClipboard(url: URL, isVideo: Bool) {
    if isVideo {
      ClipboardHelper.copyMediaFile(from: url)
      DiagnosticLogger.shared.log(
        .debug,
        .clipboard,
        "File URL written to clipboard",
        context: ["fileName": url.lastPathComponent, "kind": "video"]
      )
    } else {
      ClipboardHelper.copyImage(from: url)
      DiagnosticLogger.shared.log(
        .debug,
        .clipboard,
        "Image written to clipboard",
        context: ["fileName": url.lastPathComponent]
      )
    }
  }

  private func persistAnnotationSessionIfNeeded(_ sessionData: AnnotationSessionData, for url: URL) {
    guard AnnotationSessionStore.shared.shouldPersist(for: url) else { return }
    AnnotationSessionStore.shared.persist(sessionData, for: url)
  }
}
