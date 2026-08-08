//
//  ScreenCaptureManager.swift
//  Snapzy
//
//  Core manager for screen capture functionality
//

import AppKit
import Combine
import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import ImageIO
import os.log
import ScreenCaptureKit

private let logger = Logger(subsystem: "Snapzy", category: "ScreenCaptureManager")
typealias ShareableContentPrefetchTask = Task<SCShareableContent, Error>

private enum ShareableContentCacheMode: String {
  case standard = "standard"
  case desktopInclusive = "desktop-inclusive"

  var includeDesktopWindows: Bool {
    self == .desktopInclusive
  }
}

private struct ShareableContentCacheEntry {
  let mode: ShareableContentCacheMode
  let task: ShareableContentPrefetchTask
}

/// Result type for capture operations
enum CaptureResult {
  case success(URL)
  case failure(CaptureError)
}

struct MultiDisplayScreenshotResult {
  let savedURLs: [URL]
  let failures: [CGDirectDisplayID: CaptureError]
  let acquisitionDurationMs: Int
  let saveDurationMs: Int

  var primaryCaptureResult: CaptureResult {
    if let firstURL = savedURLs.first {
      return .success(firstURL)
    }

    if let firstFailure = failures.values.first {
      return .failure(firstFailure)
    }

    return .failure(.noDisplayFound)
  }
}

/// Errors that can occur during capture
enum CaptureError: Error, LocalizedError {
  case permissionDenied
  case unavailable(String)
  case noDisplayFound
  case captureFailed(String)
  case saveFailed(String)
  case cancelled

  var errorDescription: String? {
    switch self {
    case .permissionDenied:
      return L10n.ScreenCapture.permissionDenied
    case .unavailable(let reason):
      return reason
    case .noDisplayFound:
      return L10n.ScreenCapture.noDisplayFound
    case .captureFailed(let reason):
      return L10n.ScreenCapture.captureFailed(reason)
    case .saveFailed(let reason):
      return L10n.ScreenCapture.saveFailed(reason)
    case .cancelled:
      return L10n.ScreenCapture.cancelled
    }
  }
}

enum ScreenRecordingPermissionStatus: Equatable {
  case notGranted
  case granted
  case grantedButUnavailableDueToAppIdentity(String)
}

/// Manager class handling all screen capture operations
@MainActor
final class ScreenCaptureManager: ObservableObject {

  struct PreparedAreaCaptureContext {
    let contentFilter: SCContentFilter
    let configuration: SCStreamConfiguration
    let pixelCropRect: CGRect
    let sourceRect: CGRect
    let outputWidth: Int
    let outputHeight: Int
    let scaleFactor: CGFloat
    // Logical (point-space) geometry used at crop time to reconcile against the
    // actually-returned image dimensions. Needed because SCStream may return an
    // image whose pixel size differs from screenFrame × scaleFactor on scaled
    // HiDPI / non-default-density displays (issue #308).
    let screenFrame: CGRect
    let logicalCropSize: CGSize
    let minimumOutputScaleFactor: CGFloat
    let assumedFullPixelSize: CGSize
    let displayID: CGDirectDisplayID
  }

  struct PreparedAreaCaptureResult {
    let image: CGImage
    let scaleFactor: CGFloat
  }

  private struct DisplayCaptureTarget {
    let displayID: CGDirectDisplayID
    let order: Int
    let screen: NSScreen
    let screenFrame: CGRect
    let display: SCDisplay?
    let scaleFactor: CGFloat
  }

  private struct DisplayCapturePayload {
    let displayID: CGDirectDisplayID
    let order: Int
    let image: CGImage
    let scaleFactor: CGFloat
  }

  private enum DisplayPayloadResult {
    case success(DisplayCapturePayload)
    case failure(CGDirectDisplayID, CaptureError)
  }

  static let shared = ScreenCaptureManager()

  @Published private(set) var permissionStatus: ScreenRecordingPermissionStatus = .notGranted
  @Published private(set) var hasPermission: Bool = false
  @Published private(set) var isCapturing: Bool = false

  /// Publisher for successful capture completions
  private let captureCompletedSubject = PassthroughSubject<URL, Never>()
  var captureCompletedPublisher: AnyPublisher<URL, Never> {
    captureCompletedSubject.eraseToAnyPublisher()
  }
  private var standardShareableContentCache: ShareableContentCacheEntry?
  private var desktopInclusiveShareableContentCache: ShareableContentCacheEntry?
  private var screenParametersObserver: NSObjectProtocol?
  private nonisolated static let minimumScreenshotOutputScaleFactor: CGFloat = 2.0

  private var preferredScreenshotOutputScaleFactor: CGFloat {
    max(
      NSScreen.screens.map(\.backingScaleFactor).max() ?? Self.minimumScreenshotOutputScaleFactor,
      Self.minimumScreenshotOutputScaleFactor
    )
  }

  private init() {
    screenParametersObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.invalidateShareableContentCache()
      }
    }

    Task {
      await checkPermission()
    }
  }

  // MARK: - Permission Handling

  /// Check if screen recording permission is granted
  func checkPermission() async {
    AppIdentityManager.shared.refresh()
    updatePermissionStatus(systemGranted: CGPreflightScreenCaptureAccess())
  }

  /// Request screen recording permission by triggering the system prompt.
  ///
  /// Strategy (macOS 13+):
  /// 1. Fast-path if already granted (`CGPreflightScreenCaptureAccess`).
  /// 2. Try `SCShareableContent.current` — on macOS 13–14 this triggers the
  ///    native system dialog that auto-adds the app to Screen Recording.
  /// 3. If SCShareableContent throws (not-permitted), fall back to
  ///    `CGRequestScreenCaptureAccess()` which opens System Settings on
  ///    macOS 15+ so the user can manually toggle the app on.
  func requestPermission() async -> Bool {
    AppIdentityManager.shared.refresh()

    // Fast path: already granted by the system.
    if CGPreflightScreenCaptureAccess() {
      updatePermissionStatus(systemGranted: true)
      return hasPermission
    }

    // Primary: ScreenCaptureKit triggers the native permission dialog (macOS 13-14)
    // and auto-adds the app to the Screen Recording list.
    do {
      _ = try await SCShareableContent.current
      // If we reach here, the system granted access.
      updatePermissionStatus(systemGranted: true)
      return hasPermission
    } catch {
      // SCShareableContent threw — permission not yet granted.
      // Fallback: CGRequestScreenCaptureAccess opens System Settings on macOS 15+.
      let granted = CGRequestScreenCaptureAccess()
      if !granted {
        openScreenRecordingPreferences()
      }
      await checkPermission()
      return hasPermission
    }
  }

  /// Open System Preferences to Screen Recording section
  func openScreenRecordingPreferences() {
    let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
    NSWorkspace.shared.open(url)
  }

  /// Start loading shareable content before the user finishes a selection so
  /// the actual screenshot can happen immediately on completion.
  func prefetchShareableContent(
    includeDesktopWindows: Bool = false,
    forceRefresh: Bool = false
  ) -> ShareableContentPrefetchTask? {
    guard hasPermission else { return nil }

    let cacheMode = shareableContentCacheMode(includeDesktopWindows: includeDesktopWindows)
    if !forceRefresh, let cached = shareableContentCacheEntry(for: cacheMode) {
      return cached.task
    }

    let task = makeShareableContentPrefetchTask(includeDesktopWindows: includeDesktopWindows)
    setShareableContentCacheEntry(
      ShareableContentCacheEntry(mode: cacheMode, task: task),
      for: cacheMode
    )
    return task
  }

  func captureFastDisplaySnapshot(
    displayID: CGDirectDisplayID,
    showCursor: Bool,
    excludeDesktopIcons: Bool,
    excludeDesktopWidgets: Bool,
    excludeOwnApplication: Bool = false,
    allowFastPathWhenOwnApplicationHidden: Bool = false
  ) -> FrozenDisplaySnapshot? {
    guard !excludeOwnApplication || allowFastPathWhenOwnApplicationHidden else { return nil }
    guard !showCursor else { return nil }
    guard !excludeDesktopIcons else { return nil }
    guard !excludeDesktopWidgets else { return nil }
    guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
      return nil
    }
    guard let image = CGDisplayCreateImage(displayID) else {
      return nil
    }

    let scaleFactor = Self.imageScaleFactor(
      for: image,
      screenFrame: screen.frame,
      fallback: screen.backingScaleFactor
    )

    return FrozenDisplaySnapshot(
      displayID: displayID,
      screenFrame: screen.frame,
      scaleFactor: scaleFactor,
      colorSpaceName: preferredCaptureColorSpaceName(for: screen),
      image: image
    )
  }

  /// Off-main-thread variant — caller must resolve NSScreen data on main thread first,
  /// then pass as value types so CGDisplayCreateImage can run on a background thread.
  nonisolated func captureFastDisplaySnapshotOffMain(
    displayID: CGDirectDisplayID,
    screenFrame: CGRect,
    backingScaleFactor: CGFloat,
    colorSpaceName: CFString?
  ) -> FrozenDisplaySnapshot? {
    guard let image = CGDisplayCreateImage(displayID) else {
      return nil
    }

    let scaleFactor = Self.imageScaleFactor(
      for: image,
      screenFrame: screenFrame,
      fallback: backingScaleFactor
    )

    return FrozenDisplaySnapshot(
      displayID: displayID,
      screenFrame: screenFrame,
      scaleFactor: scaleFactor,
      colorSpaceName: colorSpaceName,
      image: image
    )
  }

  func captureDisplaySnapshots(
    displayIDs: Set<CGDirectDisplayID>? = nil,
    showCursor: Bool = false,
    excludeDesktopIcons: Bool = false,
    excludeDesktopWidgets: Bool = false,
    excludeOwnApplication: Bool = false,
    prefetchedContentTask: ShareableContentPrefetchTask? = nil
  ) async throws -> [CGDirectDisplayID: FrozenDisplaySnapshot] {
    if let unavailableError = await ensureCaptureAvailability() {
      throw unavailableError
    }

    isCapturing = true
    defer { isCapturing = false }
    DiagnosticLogger.shared.log(.info, .capture, "Frozen display snapshot capture started")

    return try await captureDisplaySnapshotsCore(
      displayIDs: displayIDs,
      showCursor: showCursor,
      excludeDesktopIcons: excludeDesktopIcons,
      excludeDesktopWidgets: excludeDesktopWidgets,
      excludeOwnApplication: excludeOwnApplication,
      prefetchedContentTask: prefetchedContentTask
    )
  }

  /// Core display snapshot logic without `isCapturing` management. Callers that
  /// already manage their own `isCapturing` lifecycle (e.g. `captureArea` composite
  /// path) use this directly to avoid double-setting the flag.
  private func captureDisplaySnapshotsCore(
    displayIDs: Set<CGDirectDisplayID>? = nil,
    showCursor: Bool = false,
    excludeDesktopIcons: Bool = false,
    excludeDesktopWidgets: Bool = false,
    excludeOwnApplication: Bool = false,
    prefetchedContentTask: ShareableContentPrefetchTask? = nil
  ) async throws -> [CGDirectDisplayID: FrozenDisplaySnapshot] {
    let includeDesktopWindows = excludeDesktopIcons || excludeDesktopWidgets
    let content = try await loadShareableContent(
      prefetchedContentTask: prefetchedContentTask,
      includeDesktopWindows: includeDesktopWindows
    )

    let screensToCapture = NSScreen.screens.filter { screen in
      guard let displayID = screen.displayID else { return false }
      guard let displayIDs else { return true }
      return displayIDs.contains(displayID)
    }

    guard !screensToCapture.isEmpty else {
      throw CaptureError.noDisplayFound
    }

    let snapshots = try await withThrowingTaskGroup(
      of: (CGDirectDisplayID, FrozenDisplaySnapshot).self,
      returning: [CGDirectDisplayID: FrozenDisplaySnapshot].self
    ) { group in
      for screen in screensToCapture {
        guard let displayID = screen.displayID else { continue }
        guard let display = content.displays.first(where: { $0.displayID == Int(displayID) }) else {
          throw CaptureError.noDisplayFound
        }

        // Compute filter, scale factor, and configuration on the main actor
        // before entering the child task, since these methods are @MainActor-isolated.
        let filter = buildFilter(
          display: display,
          content: content,
          excludeDesktopIcons: excludeDesktopIcons,
          excludeDesktopWidgets: excludeDesktopWidgets,
          excludeOwnApplication: excludeOwnApplication
        )
        let scaleFactor = displaySnapshotScaleFactor(
          for: screen,
          display: display,
          contentFilter: filter
        )
        let configuration = makeDisplaySnapshotConfiguration(
          for: screen,
          scaleFactor: scaleFactor,
          showsCursor: showCursor
        )
        let screenFrame = screen.frame

        group.addTask {
          let image = try await Self.captureImageCompat(
            contentFilter: filter,
            configuration: configuration
          )
          let imageScaleFactor = Self.imageScaleFactor(
            for: image,
            screenFrame: screenFrame,
            fallback: scaleFactor
          )
          return (displayID, FrozenDisplaySnapshot(
            displayID: displayID,
            screenFrame: screenFrame,
            scaleFactor: imageScaleFactor,
            colorSpaceName: configuration.colorSpaceName,
            image: image
          ))
        }
      }

      var result: [CGDirectDisplayID: FrozenDisplaySnapshot] = [:]
      for try await (displayID, snapshot) in group {
        result[displayID] = snapshot
      }
      return result
    }

    guard !snapshots.isEmpty else {
      throw CaptureError.noDisplayFound
    }

    return snapshots
  }

  // MARK: - Capture Fullscreen

  /// Capture the entire screen and save to specified directory
  /// - Parameters:
  ///   - saveDirectory: Directory URL where the screenshot will be saved
  ///   - fileName: Optional custom filename (without extension). If nil, uses timestamp
  ///   - displayID: Optional specific display to capture. If nil, captures main display
  ///   - format: Image format for saving (default: PNG)
  ///   - showCursor: Whether the cursor should appear in the captured screenshot
  /// - Returns: CaptureResult with the saved file URL or error
  func captureFullscreen(
    saveDirectory: URL,
    fileName: String? = nil,
    displayID: CGDirectDisplayID? = nil,
    format: ImageFormat = .png,
    showCursor: Bool = false,
    excludeDesktopIcons: Bool = false,
    excludeDesktopWidgets: Bool = false,
    excludeOwnApplication: Bool = false,
    prefetchedContentTask: ShareableContentPrefetchTask? = nil,
    context: CaptureContext = .empty
  ) async -> CaptureResult {
    if let unavailableError = await ensureCaptureAvailability() {
      return .failure(unavailableError)
    }

    isCapturing = true
    defer { isCapturing = false }
    DiagnosticLogger.shared.log(.info, .capture, "Fullscreen capture started")

    do {
      let includeDesktopWindows = excludeDesktopIcons || excludeDesktopWidgets
      let content = try await loadShareableContent(
        prefetchedContentTask: prefetchedContentTask,
        includeDesktopWindows: includeDesktopWindows
      )

      // Get the target display
      let targetDisplayID = displayID ?? ScreenUtility.activeDisplayID()
      guard
        let display = content.displays.first(where: { $0.displayID == targetDisplayID })
          ?? content.displays.first
      else {
        return .failure(.noDisplayFound)
      }

      // Configure capture — exclude desktop icons/widgets if requested
      let filter = buildFilter(
        display: display,
        content: content,
        excludeDesktopIcons: excludeDesktopIcons,
        excludeDesktopWidgets: excludeDesktopWidgets,
        excludeOwnApplication: excludeOwnApplication
      )
      // Get the display's backing scale factor dynamically
      let matchedScreen = NSScreen.screens.first(where: {
        Int($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0)
          == display.displayID
      })
      let nativeScaleFactor = displaySnapshotScaleFactor(
        for: matchedScreen,
        display: display,
        contentFilter: filter
      )
      let outputScaleFactor = max(nativeScaleFactor, preferredScreenshotOutputScaleFactor)

      let config = SCStreamConfiguration()
      let includeWindowShadow = UserDefaults.standard.object(forKey: PreferencesKeys.captureIncludeWindowShadow) as? Bool ?? WindowShadowPreference.defaultIncludeShadow
      if #available(macOS 14.0, *) { config.ignoreShadowsSingleWindow = WindowShadowPreference.ignoreShadowsSingleWindow(includeShadow: includeWindowShadow) }
      if #available(macOS 14.2, *) { config.captureResolution = .best }
      let captureFrame = matchedScreen?.frame ?? display.frame
      config.width = max(1, Int((captureFrame.width * nativeScaleFactor).rounded()))
      config.height = max(1, Int((captureFrame.height * nativeScaleFactor).rounded()))
      config.pixelFormat = kCVPixelFormatType_32BGRA
      config.showsCursor = showCursor
      if let matchedScreen, let colorSpaceName = preferredCaptureColorSpaceName(for: matchedScreen) {
        config.colorSpaceName = colorSpaceName
      }

      // Capture the image (compat: SCScreenshotManager requires macOS 14+)
      let image = try await Self.captureImageCompat(
        contentFilter: filter,
        configuration: config
      )

      DiagnosticLogger.shared.log(
        .debug,
        .capture,
        "Fullscreen captured image",
        context: [
          "displayID": "\(display.displayID)",
          "actualFull": "\(image.width)x\(image.height)",
          "configFull": "\(config.width)x\(config.height)",
          "nativeScale": String(format: "%.3f", Double(nativeScaleFactor)),
          "outputScale": String(format: "%.3f", Double(outputScaleFactor)),
        ]
      )

      let imageScaleFactor = matchedScreen.map {
        Self.imageScaleFactor(for: image, screenFrame: $0.frame, fallback: nativeScaleFactor)
      } ?? nativeScaleFactor
      let promotedImage = Self.promoteScreenshotImageIfNeeded(
        image,
        logicalSize: captureFrame.size,
        sourceScaleFactor: imageScaleFactor,
        minimumOutputScaleFactor: outputScaleFactor,
        colorSpaceName: config.colorSpaceName
      )

      // Save the image
      return await saveImage(
        promotedImage.image,
        to: saveDirectory,
        fileName: fileName,
        format: format,
        scaleFactor: promotedImage.scaleFactor,
        context: context
      )

    } catch {
      DiagnosticLogger.shared.log(.error, .capture, "Fullscreen capture failed: \(error.localizedDescription)")
      return .failure(.captureFailed(error.localizedDescription))
    }
  }

  func captureAllDisplays(
    saveDirectory: URL,
    fileName: String? = nil,
    format: ImageFormat = .png,
    showCursor: Bool = false,
    excludeDesktopIcons: Bool = false,
    excludeDesktopWidgets: Bool = false,
    excludeOwnApplication: Bool = false,
    allowFastPathWhenOwnApplicationHidden: Bool = false,
    prefetchedContentTask: ShareableContentPrefetchTask? = nil,
    targetDisplayIDs: Set<CGDirectDisplayID>? = nil,
    context: CaptureContext = .empty
  ) async -> MultiDisplayScreenshotResult {
    let fallbackDisplayID = targetDisplayIDs?.first ?? CGMainDisplayID()

    if let unavailableError = await ensureCaptureAvailability() {
      return MultiDisplayScreenshotResult(
        savedURLs: [],
        failures: [fallbackDisplayID: unavailableError],
        acquisitionDurationMs: 0,
        saveDurationMs: 0
      )
    }

    isCapturing = true
    defer { isCapturing = false }

    do {
      let canUseFastPath = canUseFastDisplayCapturePath(
        showCursor: showCursor,
        excludeDesktopIcons: excludeDesktopIcons,
        excludeDesktopWidgets: excludeDesktopWidgets,
        excludeOwnApplication: excludeOwnApplication,
        allowFastPathWhenOwnApplicationHidden: allowFastPathWhenOwnApplicationHidden
      )
      let content: SCShareableContent?
      let targets: [DisplayCaptureTarget]

      if canUseFastPath {
        content = nil
        targets = makeFastDisplayCaptureTargets(targetDisplayIDs: targetDisplayIDs)
      } else {
        let includeDesktopWindows = excludeDesktopIcons || excludeDesktopWidgets
        let loadedContent = try await loadShareableContent(
          prefetchedContentTask: prefetchedContentTask,
          includeDesktopWindows: includeDesktopWindows
        )
        content = loadedContent
        targets = makeDisplayCaptureTargets(
          content: loadedContent,
          targetDisplayIDs: targetDisplayIDs
        )
      }

      guard !targets.isEmpty else {
        return MultiDisplayScreenshotResult(
          savedURLs: [],
          failures: [fallbackDisplayID: .noDisplayFound],
          acquisitionDurationMs: 0,
          saveDurationMs: 0
        )
      }

      let acquisitionStartedAt = Date()
      let payloads = await captureDisplayPayloads(
        targets: targets,
        content: content,
        canUseFastPath: canUseFastPath,
        showCursor: showCursor,
        excludeDesktopIcons: excludeDesktopIcons,
        excludeDesktopWidgets: excludeDesktopWidgets,
        excludeOwnApplication: excludeOwnApplication
      )
      let acquisitionDurationMs = Int(Date().timeIntervalSince(acquisitionStartedAt) * 1000)

      let savedPayloads = payloads.compactMap { result -> DisplayCapturePayload? in
        if case .success(let payload) = result { return payload }
        return nil
      }
      var failures: [CGDirectDisplayID: CaptureError] = [:]
      for result in payloads {
        if case .failure(let displayID, let error) = result {
          failures[displayID] = error
        }
      }

      let saveStartedAt = Date()
      let saveResult = await saveDisplayPayloads(
        savedPayloads,
        to: saveDirectory,
        baseFileName: fileName,
        format: format,
        context: context
      )
      let savedURLs = saveResult.savedURLs
      for (displayID, error) in saveResult.failures {
        failures[displayID] = error
      }
      let saveDurationMs = Int(Date().timeIntervalSince(saveStartedAt) * 1000)
      let captureScope = targetDisplayIDs == nil ? "all-displays" : "selected-displays"
      let completionMessage = targetDisplayIDs == nil
        ? "Multi-display fullscreen capture completed"
        : "Selected-display fullscreen capture completed"

      DiagnosticLogger.shared.log(
        acquisitionDurationMs <= 50 ? .info : .warning,
        .capture,
        completionMessage,
        context: [
          "captureScope": captureScope,
          "displayCount": "\(targets.count)",
          "savedCount": "\(savedURLs.count)",
          "failureCount": "\(failures.count)",
          "acquisition_ms": "\(acquisitionDurationMs)",
          "save_ms": "\(saveDurationMs)",
          "target_ms": "50",
          "perfect_ms": "30",
        ]
      )

      return MultiDisplayScreenshotResult(
        savedURLs: savedURLs,
        failures: failures,
        acquisitionDurationMs: acquisitionDurationMs,
        saveDurationMs: saveDurationMs
      )
    } catch {
      DiagnosticLogger.shared.logError(.capture, error, "Multi-display fullscreen capture failed")
      return MultiDisplayScreenshotResult(
        savedURLs: [],
        failures: [fallbackDisplayID: .captureFailed(error.localizedDescription)],
        acquisitionDurationMs: 0,
        saveDurationMs: 0
      )
    }
  }

  private func makeDisplayCaptureTargets(
    content: SCShareableContent,
    targetDisplayIDs: Set<CGDirectDisplayID>? = nil
  ) -> [DisplayCaptureTarget] {
    NSScreen.screens.enumerated().compactMap { order, screen in
      guard let displayID = screen.displayID,
            targetDisplayIDs?.contains(displayID) ?? true,
            let display = content.displays.first(where: { $0.displayID == Int(displayID) }) else {
        return nil
      }

      return DisplayCaptureTarget(
        displayID: displayID,
        order: order,
        screen: screen,
        screenFrame: screen.frame,
        display: display,
        scaleFactor: displaySnapshotScaleFactor(for: screen, display: display)
      )
    }
  }

  private func makeFastDisplayCaptureTargets(
    targetDisplayIDs: Set<CGDirectDisplayID>? = nil
  ) -> [DisplayCaptureTarget] {
    NSScreen.screens.enumerated().compactMap { order, screen in
      guard let displayID = screen.displayID,
            targetDisplayIDs?.contains(displayID) ?? true else { return nil }
      return DisplayCaptureTarget(
        displayID: displayID,
        order: order,
        screen: screen,
        screenFrame: screen.frame,
        display: nil,
        scaleFactor: screen.backingScaleFactor
      )
    }
  }

  private func canUseFastDisplayCapturePath(
    showCursor: Bool,
    excludeDesktopIcons: Bool,
    excludeDesktopWidgets: Bool,
    excludeOwnApplication: Bool,
    allowFastPathWhenOwnApplicationHidden: Bool
  ) -> Bool {
    !showCursor
      && !excludeDesktopIcons
      && !excludeDesktopWidgets
      && (!excludeOwnApplication || allowFastPathWhenOwnApplicationHidden)
  }

  private func captureDisplayPayloads(
    targets: [DisplayCaptureTarget],
    content: SCShareableContent?,
    canUseFastPath: Bool,
    showCursor: Bool,
    excludeDesktopIcons: Bool,
    excludeDesktopWidgets: Bool,
    excludeOwnApplication: Bool
  ) async -> [DisplayPayloadResult] {
    if canUseFastPath {
      return await captureDisplayPayloadsUsingCoreGraphics(targets: targets)
    }

    guard let content else {
      return targets.map { .failure($0.displayID, .noDisplayFound) }
    }

    let requests = targets.compactMap {
      target -> (
        displayID: CGDirectDisplayID,
        order: Int,
        screenFrame: CGRect,
        filter: SCContentFilter,
        configuration: SCStreamConfiguration,
        captureScale: CGFloat,
        outputScale: CGFloat
      )? in
      guard let display = target.display else { return nil }
      let filter = buildFilter(
        display: display,
        content: content,
        excludeDesktopIcons: excludeDesktopIcons,
        excludeDesktopWidgets: excludeDesktopWidgets,
        excludeOwnApplication: excludeOwnApplication
      )
      let nativeScaleFactor = displaySnapshotScaleFactor(
        for: target.screen,
        display: display,
        contentFilter: filter
      )
      let captureScale = nativeScaleFactor
      let outputScale = max(nativeScaleFactor, preferredScreenshotOutputScaleFactor)
      let configuration = makeDisplaySnapshotConfiguration(
        for: target.screen,
        scaleFactor: captureScale,
        showsCursor: showCursor
      )
      return (target.displayID, target.order, target.screenFrame, filter, configuration, captureScale, outputScale)
    }

    return await withTaskGroup(of: DisplayPayloadResult.self) { group in
      for request in requests {
        group.addTask {
          do {
            let image = try await Self.captureImageCompat(
              contentFilter: request.filter,
              configuration: request.configuration
            )
            let imageScaleFactor = Self.imageScaleFactor(
              for: image,
              screenFrame: request.screenFrame,
              fallback: request.captureScale
            )
            let promotedImage = Self.promoteScreenshotImageIfNeeded(
              image,
              logicalSize: request.screenFrame.size,
              sourceScaleFactor: imageScaleFactor,
              minimumOutputScaleFactor: request.outputScale,
              colorSpaceName: request.configuration.colorSpaceName
            )
            return .success(
              DisplayCapturePayload(
                displayID: request.displayID,
                order: request.order,
                image: promotedImage.image,
                scaleFactor: promotedImage.scaleFactor
              )
            )
          } catch {
            return .failure(request.displayID, .captureFailed(error.localizedDescription))
          }
        }
      }

      var results: [DisplayPayloadResult] = []
      for await result in group {
        results.append(result)
      }
      return results.sorted(by: Self.displayPayloadResultOrder)
    }
  }

  private nonisolated func captureDisplayPayloadsUsingCoreGraphics(
    targets: [DisplayCaptureTarget]
  ) async -> [DisplayPayloadResult] {
    let requests = targets.map {
      (
        displayID: $0.displayID,
        order: $0.order,
        screenFrame: $0.screenFrame,
        scaleFactor: $0.scaleFactor
      )
    }

    return await withTaskGroup(of: DisplayPayloadResult.self) { group in
      for request in requests {
        group.addTask {
          guard let image = CGDisplayCreateImage(request.displayID) else {
            return .failure(request.displayID, .captureFailed(L10n.ScreenCapture.unableToCaptureSelectedArea))
          }

          let imageScaleFactor = Self.imageScaleFactor(
            for: image,
            screenFrame: request.screenFrame,
            fallback: request.scaleFactor
          )
          let promotedImage = Self.promoteScreenshotImageIfNeeded(
            image,
            logicalSize: request.screenFrame.size,
            sourceScaleFactor: imageScaleFactor,
            minimumOutputScaleFactor: Self.minimumScreenshotOutputScaleFactor,
            colorSpaceName: nil
          )

          return .success(
            DisplayCapturePayload(
              displayID: request.displayID,
              order: request.order,
              image: promotedImage.image,
              scaleFactor: promotedImage.scaleFactor
            )
          )
        }
      }

      var results: [DisplayPayloadResult] = []
      for await result in group {
        results.append(result)
      }
      return results.sorted(by: Self.displayPayloadResultOrder)
    }
  }

  private nonisolated static func displayPayloadResultOrder(_ lhs: DisplayPayloadResult, _ rhs: DisplayPayloadResult) -> Bool {
    func order(_ result: DisplayPayloadResult) -> Int {
      switch result {
      case .success(let payload):
        return payload.order
      case .failure:
        return Int.max
      }
    }
    return order(lhs) < order(rhs)
  }

  private func saveDisplayPayloads(
    _ payloads: [DisplayCapturePayload],
    to directory: URL,
    baseFileName: String?,
    format: ImageFormat,
    context: CaptureContext = .empty
  ) async -> (savedURLs: [URL], failures: [CGDirectDisplayID: CaptureError]) {
    guard !payloads.isEmpty else {
      return ([], [:])
    }

    let baseName = CaptureOutputNaming.resolveBaseName(
      customName: baseFileName,
      kind: .screenshot,
      context: context
    )
    let needsDisplaySuffix = payloads.count > 1

    return await withTaskGroup(of: (order: Int, displayID: CGDirectDisplayID, result: CaptureResult).self) { group in
      for payload in payloads {
        let outputName = needsDisplaySuffix ? "\(baseName)_Display-\(payload.order + 1)" : baseName
        group.addTask { [weak self] in
          guard let self else {
            return (payload.order, payload.displayID, .failure(.captureFailed(L10n.ScreenCapture.unableToCaptureSelectedArea)))
          }

          let result = await self.saveImage(
            payload.image,
            to: directory,
            fileName: outputName,
            format: format,
            scaleFactor: payload.scaleFactor,
            emitCompletion: false,
            context: context
          )
          return (payload.order, payload.displayID, result)
        }
      }

      var saved: [(order: Int, url: URL)] = []
      var failures: [CGDirectDisplayID: CaptureError] = [:]
      for await item in group {
        switch item.result {
        case .success(let url):
          saved.append((item.order, url))
        case .failure(let error):
          failures[item.displayID] = error
        }
      }

      let urls = saved.sorted { $0.order < $1.order }.map(\.url)
      return (urls, failures)
    }
  }

  // MARK: - Capture Specific Area

  /// Capture a specific rectangular area of the screen
  /// - Parameters:
  ///   - rect: The rectangle area to capture (in screen coordinates)
  ///   - saveDirectory: Directory URL where the screenshot will be saved
  ///   - fileName: Optional custom filename (without extension)
  ///   - format: Image format for saving
  ///   - showCursor: Whether the cursor should appear in the captured screenshot
  /// - Returns: CaptureResult with the saved file URL or error
  func captureArea(
    rect: CGRect,
    saveDirectory: URL,
    fileName: String? = nil,
    format: ImageFormat = .png,
    showCursor: Bool = false,
    excludeDesktopIcons: Bool = false,
    excludeDesktopWidgets: Bool = false,
    excludeOwnApplication: Bool = false,
    prefetchedContentTask: ShareableContentPrefetchTask? = nil,
    context: CaptureContext = .empty
  ) async -> CaptureResult {
    if let unavailableError = await ensureCaptureAvailability() {
      return .failure(unavailableError)
    }

    isCapturing = true
    defer { isCapturing = false }
    DiagnosticLogger.shared.log(.info, .capture, "Area capture started \(Int(rect.width))x\(Int(rect.height))")

    do {
      let intersectingDisplayIDs = Self.displayIDsIntersecting(rect)

      // Multi-display composite path: when the selection spans ≥2 displays,
      // capture all intersecting displays in parallel and composite them using
      // the frozen path's battle-tested algorithm (DRY).
      if intersectingDisplayIDs.count > 1 {
        DiagnosticLogger.shared.log(
          .info,
          .capture,
          "Area capture spans multiple displays, using composite path",
          context: [
            "displayCount": "\(intersectingDisplayIDs.count)",
            "rect": "\(Int(rect.origin.x)),\(Int(rect.origin.y)) \(Int(rect.width))x\(Int(rect.height))",
          ]
        )

        let compositeResult = try await captureAreaComposite(
          rect: rect,
          displayIDs: intersectingDisplayIDs,
          showCursor: showCursor,
          excludeDesktopIcons: excludeDesktopIcons,
          excludeDesktopWidgets: excludeDesktopWidgets,
          excludeOwnApplication: excludeOwnApplication,
          prefetchedContentTask: prefetchedContentTask
        )

        return await saveImage(
          compositeResult.image,
          to: saveDirectory,
          fileName: fileName,
          format: format,
          scaleFactor: compositeResult.scaleFactor,
          context: context
        )
      }

      // Single-display optimized path (existing behavior, unchanged).
      let preparedContext = try await makePreparedAreaCaptureContext(
        rect: rect,
        showCursor: showCursor,
        excludeDesktopIcons: excludeDesktopIcons,
        excludeDesktopWidgets: excludeDesktopWidgets,
        excludeOwnApplication: excludeOwnApplication,
        prefetchedContentTask: prefetchedContentTask,
        minimumOutputScaleFactor: preferredScreenshotOutputScaleFactor
      )

      guard let captured = try await capturePreparedArea(preparedContext) else {
        return .failure(.captureFailed(L10n.ScreenCapture.failedToCropCapturedImage))
      }

      // Save the cropped image. Use the post-reconciliation scale so DPI metadata
      // matches the actual returned pixels (may be promoted to min-2x baseline).
      return await saveImage(
        captured.image,
        to: saveDirectory,
        fileName: fileName,
        format: format,
        scaleFactor: captured.scaleFactor,
        context: context
      )

    } catch {
      DiagnosticLogger.shared.log(.error, .capture, "Area capture failed: \(error.localizedDescription)")
      return .failure(.captureFailed(error.localizedDescription))
    }
  }

  func captureWindow(
    target: WindowCaptureTarget,
    saveDirectory: URL,
    fileName: String? = nil,
    format: ImageFormat = .png,
    showCursor: Bool = false,
    excludeDesktopIcons: Bool = false,
    excludeDesktopWidgets: Bool = false,
    excludeOwnApplication: Bool = false,
    prefetchedContentTask: ShareableContentPrefetchTask? = nil,
    immediateMenuBarPopoverCapture: ImmediateMenuBarPopoverCapture? = nil,
    context: CaptureContext = .empty
  ) async -> CaptureResult {
    if let unavailableError = await ensureCaptureAvailability() {
      return .failure(unavailableError)
    }

    isCapturing = true
    defer { isCapturing = false }
    DiagnosticLogger.shared.log(
      .info,
      .capture,
      "Window capture started",
      context: ["windowID": "\(target.windowID)"]
    )

    let shareableWindow = await WindowSelectionQueryService.resolveWindow(
      windowID: target.windowID,
      prefetchedContentTask: prefetchedContentTask
    )
    let imagePath = WindowCaptureImagePath.resolve(
      targetKind: target.kind,
      hasShareableWindow: shareableWindow != nil,
      hasRetainedMenuBarPopover: immediateMenuBarPopoverCapture != nil
    )

    switch imagePath {
    case .screenCaptureKit:
      guard let shareableWindow else {
        assertionFailure("ScreenCaptureKit path selected without a shareable window")
        return .failure(.captureFailed(L10n.ScreenCapture.failedToCropCapturedImage))
      }

      do {
        let windowImage = try await captureWindowImage(
          shareableWindow,
          fallbackTarget: target,
          showCursor: showCursor
        )
        return await saveImage(
          windowImage.image,
          to: saveDirectory,
          fileName: fileName,
          format: format,
          scaleFactor: windowImage.scaleFactor,
          context: context
        )
      } catch {
        DiagnosticLogger.shared.logError(
          .capture,
          error,
          "Exact window capture failed; falling back to rect capture"
        )
      }

    case .retainedMenuBarPopover:
      guard let immediateMenuBarPopoverCapture else {
        assertionFailure("Retained popover path selected without an image")
        return .failure(.captureFailed(L10n.ScreenCapture.failedToCropCapturedImage))
      }
      return await saveImage(
        immediateMenuBarPopoverCapture.image,
        to: saveDirectory,
        fileName: fileName,
        format: format,
        scaleFactor: immediateMenuBarPopoverCapture.scaleFactor,
        context: context
      )

    case .coreGraphicsWindow:
      if let windowImage = await captureMenuBarPopoverImage(target: target) {
        return await saveImage(
          windowImage.image,
          to: saveDirectory,
          fileName: fileName,
          format: format,
          scaleFactor: windowImage.scaleFactor,
          context: context
        )
      }
      DiagnosticLogger.shared.log(
        .info,
        .capture,
        "Menu bar popover Core Graphics capture failed; falling back to area capture",
        context: ["windowID": "\(target.windowID)"]
      )

    case .areaFallback:
      DiagnosticLogger.shared.log(
        .info,
        .capture,
        "Window missing from shareable content; falling back to area capture",
        context: ["windowID": "\(target.windowID)"]
      )
    }

    return await captureArea(
      rect: target.frame,
      saveDirectory: saveDirectory,
      fileName: fileName,
      format: format,
      showCursor: showCursor,
      excludeDesktopIcons: excludeDesktopIcons,
      excludeDesktopWidgets: excludeDesktopWidgets,
      excludeOwnApplication: excludeOwnApplication,
      prefetchedContentTask: prefetchedContentTask,
      context: context
    )
  }

  private func captureMenuBarPopoverImage(
    target: WindowCaptureTarget
  ) async -> (image: CGImage, scaleFactor: CGFloat)? {
    let image = await Task.detached(priority: .userInitiated) {
      CGImage(
        windowListFromArrayScreenBounds: .null,
        windowArray: [target.windowID] as CFArray,
        imageOption: [.bestResolution]
      )
    }.value

    guard let image else { return nil }
    let scaleFactor = max(
      Self.imageScaleFactor(
        for: image,
        screenFrame: target.frame,
        fallback: preferredScreenshotOutputScaleFactor
      ),
      preferredScreenshotOutputScaleFactor
    )
    return (image, scaleFactor)
  }

  // MARK: - Image Saving

  /// Save a CGImage to disk with write verification
  private func saveImage(
    _ image: CGImage,
    to directory: URL,
    fileName: String?,
    format: ImageFormat,
    scaleFactor: CGFloat? = nil,
    emitCompletion: Bool = true,
    context: CaptureContext = .empty
  ) async -> CaptureResult {
    let directoryAccess = SandboxFileAccessManager.shared.beginAccessingURL(directory)
    defer { directoryAccess.stop() }
    let scopedDirectory = directoryAccess.url

    // Resolve filename using user-configurable template (with legacy fallback).
    let baseName = CaptureOutputNaming.resolveBaseName(
      customName: fileName,
      kind: .screenshot,
      context: context
    )
    let fileExtension = format.fileExtension

    logger.info("Saving capture to \(scopedDirectory.lastPathComponent)/\(baseName).\(fileExtension)")

    // Capture format properties before entering detached task
    let utType = format.utType

    // Move file I/O to background thread to avoid blocking main thread
    let isWebP = fileExtension == "webp"
    let destinationProperties = Self.imageDestinationProperties(for: format, scaleFactor: scaleFactor)
    let fileURL = CaptureOutputNaming.makeUniqueFileURL(
      in: scopedDirectory,
      baseName: baseName,
      fileExtension: fileExtension
    )
    let writeResult: Result<URL, CaptureError> = await Task.detached {
      // Create directory if needed
      do {
        try FileManager.default.createDirectory(
          at: fileURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
      } catch {
        return .failure(.saveFailed(L10n.ScreenCapture.couldNotCreateDirectory(error.localizedDescription)))
      }

      if isWebP {
        // WebP: use WebPEncoder (cwebp CLI) since ImageIO doesn't support WebP encoding
        guard WebPEncoderService.write(image, to: fileURL) else {
          return .failure(.saveFailed(L10n.ScreenCapture.webpEncodingFailed))
        }
      } else {
        // PNG/JPEG: use CGImageDestination
        guard
          let destination = CGImageDestinationCreateWithURL(
            fileURL as CFURL,
            utType,
            1,
            nil
          )
        else {
          return .failure(.saveFailed(L10n.ScreenCapture.couldNotCreateImageDestination))
        }

        CGImageDestinationAddImage(destination, image, destinationProperties)

        guard CGImageDestinationFinalize(destination) else {
          return .failure(.saveFailed(L10n.ScreenCapture.failedToWriteImageToDisk))
        }
      }

      // Verify file is fully written
      let verified = await Self.verifyFileWritten(at: fileURL)
      if verified {
        return .success(fileURL)
      } else {
        return .failure(.saveFailed(L10n.ScreenCapture.fileWriteVerificationFailed(fileURL.lastPathComponent)))
      }
    }.value

    switch writeResult {
    case .success(let url):
      DiagnosticLogger.shared.log(.info, .capture, "Capture saved: \(url.lastPathComponent)")
      if emitCompletion {
        captureCompletedSubject.send(url)
      }
      return .success(url)
    case .failure(let error):
      DiagnosticLogger.shared.log(.error, .capture, "Save failed: \(error.localizedDescription)")
      logger.error("Save failed: \(error.localizedDescription)")
      return .failure(error)
    }
  }

  /// Save an already-processed image (for example OCR/cutout post-processing flows)
  /// using the same naming, sandbox access, verification, and post-capture pipeline.
  func saveProcessedImage(
    _ image: CGImage,
    to directory: URL,
    fileName: String? = nil,
    format: ImageFormat = .png,
    scaleFactor: CGFloat? = nil,
    emitCompletion: Bool = true,
    context: CaptureContext = .empty
  ) async -> CaptureResult {
    await saveImage(
      image,
      to: directory,
      fileName: fileName,
      format: format,
      scaleFactor: scaleFactor,
      emitCompletion: emitCompletion,
      context: context
    )
  }

  /// Verify file exists on disk with non-zero size, retrying up to maxAttempts.
  /// Runs on caller's thread (designed for background execution).
  private nonisolated static func verifyFileWritten(at url: URL, maxAttempts: Int = 3, delayMs: UInt64 = 50) async -> Bool {
    let logger = Logger(subsystem: "Snapzy", category: "ScreenCaptureManager")
    for attempt in 1...maxAttempts {
      if FileManager.default.fileExists(atPath: url.path) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs?[.size] as? UInt64 ?? 0
        if size > 0 {
          logger.debug("File verified on attempt \(attempt): \(url.lastPathComponent) (\(size) bytes)")
          return true
        }
      }
      if attempt < maxAttempts {
        try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
      }
    }
    logger.error("File verification failed after \(maxAttempts) attempts: \(url.lastPathComponent)")
    return false
  }

  private nonisolated static func imageDestinationProperties(
    for format: ImageFormat,
    scaleFactor: CGFloat?
  ) -> CFDictionary? {
    let resolvedScale = max(Double(scaleFactor ?? 1.0), 1.0)
    let dpi = resolvedScale * 72.0
    var properties: [CFString: Any] = [
      kCGImagePropertyDPIWidth: dpi,
      kCGImagePropertyDPIHeight: dpi
    ]

    switch format {
    case .png:
      let pixelsPerMeter = Int((dpi / 0.0254).rounded())
      properties[kCGImagePropertyPNGDictionary] = [
        kCGImagePropertyPNGXPixelsPerMeter: pixelsPerMeter,
        kCGImagePropertyPNGYPixelsPerMeter: pixelsPerMeter
      ] as CFDictionary
    case .jpeg(let quality):
      properties[kCGImageDestinationLossyCompressionQuality] = quality
    case .webp:
      break
    }

    return properties as CFDictionary
  }

  // MARK: - Utility

  /// Get list of available displays
  func getAvailableDisplays() async -> [SCDisplay] {
    do {
      let content = try await SCShareableContent.current
      return content.displays
    } catch {
      DiagnosticLogger.shared.log(.warning, .capture, "Failed to get available displays", context: ["error": error.localizedDescription])
      return []
    }
  }

  /// Capture a specific area and return as CGImage (for OCR)
  func captureAreaAsImage(
    rect: CGRect,
    excludeDesktopIcons: Bool = false,
    excludeDesktopWidgets: Bool = false,
    excludeOwnApplication: Bool = false,
    prefetchedContentTask: ShareableContentPrefetchTask? = nil
  ) async throws -> CGImage? {
    if let unavailableError = await ensureCaptureAvailability() {
      throw unavailableError
    }

    // Multi-display composite path for OCR/cutout: when the selection spans
    // ≥2 displays, capture and composite all intersecting displays.
    let intersectingDisplayIDs = Self.displayIDsIntersecting(rect)
    if intersectingDisplayIDs.count > 1 {
      let compositeResult = try await captureAreaComposite(
        rect: rect,
        displayIDs: intersectingDisplayIDs,
        showCursor: false,
        excludeDesktopIcons: excludeDesktopIcons,
        excludeDesktopWidgets: excludeDesktopWidgets,
        excludeOwnApplication: excludeOwnApplication,
        prefetchedContentTask: prefetchedContentTask
      )
      return compositeResult.image
    }

    let context = try await makePreparedAreaCaptureContext(
      rect: rect,
      showCursor: false,
      excludeDesktopIcons: excludeDesktopIcons,
      excludeDesktopWidgets: excludeDesktopWidgets,
      excludeOwnApplication: excludeOwnApplication,
      prefetchedContentTask: prefetchedContentTask
    )

    return try await capturePreparedArea(context)?.image
  }

  func prepareAreaCapture(
    rect: CGRect,
    showCursor: Bool = false,
    excludeDesktopIcons: Bool = false,
    excludeDesktopWidgets: Bool = false,
    excludeOwnApplication: Bool = false,
    prefetchedContentTask: ShareableContentPrefetchTask? = nil
  ) async throws -> PreparedAreaCaptureContext {
    if let unavailableError = await ensureCaptureAvailability() {
      throw unavailableError
    }

    return try await makePreparedAreaCaptureContext(
      rect: rect,
      showCursor: showCursor,
      excludeDesktopIcons: excludeDesktopIcons,
      excludeDesktopWidgets: excludeDesktopWidgets,
      excludeOwnApplication: excludeOwnApplication,
      prefetchedContentTask: prefetchedContentTask
    )
  }

  func capturePreparedArea(_ context: PreparedAreaCaptureContext) async throws -> PreparedAreaCaptureResult? {
    let fullImage = try await Self.captureImageCompat(
      contentFilter: context.contentFilter,
      configuration: context.configuration
    )

    // Reconcile assumed-vs-actual: SCStream can return an image whose pixel
    // size differs from `screenFrame × assumedScale` on scaled HiDPI displays.
    // Trusting the pre-computed `pixelCropRect` against the actual image clamps
    // the crop to upper-left when the image is smaller than assumed (issue #308).
    let reconciled = Self.reconciledPixelCrop(
      fullImagePixelWidth: fullImage.width,
      fullImagePixelHeight: fullImage.height,
      screenFrame: context.screenFrame,
      logicalSourceRect: context.sourceRect,
      logicalCropSize: context.logicalCropSize,
      fallbackScale: context.scaleFactor
    )

    let assumedWidth = Int(context.assumedFullPixelSize.width.rounded())
    let assumedHeight = Int(context.assumedFullPixelSize.height.rounded())
    let mismatch =
      abs(fullImage.width - assumedWidth) > 1 ||
      abs(fullImage.height - assumedHeight) > 1

    DiagnosticLogger.shared.log(
      .debug,
      .capture,
      "Area captured image",
      context: [
        "displayID": "\(context.displayID)",
        "actualFull": "\(fullImage.width)x\(fullImage.height)",
        "assumedFull": "\(assumedWidth)x\(assumedHeight)",
        "actualScale": String(format: "%.3f", Double(reconciled.actualScale)),
        "assumedScale": String(format: "%.3f", Double(context.scaleFactor)),
        "rebuiltCrop": "\(Int(reconciled.pixelCrop.origin.x))x\(Int(reconciled.pixelCrop.origin.y))+\(Int(reconciled.pixelCrop.width))x\(Int(reconciled.pixelCrop.height))",
      ]
    )

    if mismatch {
      DiagnosticLogger.shared.log(
        .info,
        .capture,
        "#308 dimension mismatch (actual≠assumed) — rebuilt crop from actual pixels",
        context: [
          "displayID": "\(context.displayID)",
          "actualFull": "\(fullImage.width)x\(fullImage.height)",
          "assumedFull": "\(assumedWidth)x\(assumedHeight)",
          "actualScale": String(format: "%.3f", Double(reconciled.actualScale)),
        ]
      )
    }

    let fullImageBounds = CGRect(
      x: 0,
      y: 0,
      width: fullImage.width,
      height: fullImage.height
    )
    let capturedImage: CGImage?
    if reconciled.pixelCrop.integral == fullImageBounds.integral {
      capturedImage = fullImage
    } else if reconciled.pixelCrop.isEmpty {
      capturedImage = nil
    } else {
      capturedImage = fullImage.cropping(to: reconciled.pixelCrop)
    }

    guard let capturedImage else {
      return nil
    }

    // Promote low-density slices to the minimum screenshot output baseline
    // (mirrors fullscreen + frozen paths). Native-density images pass through
    // unchanged; the sharpener only runs when an actual upscale happened.
    let promoted = FrozenAreaCaptureSession.imageByPromotingScaleIfNeeded(
      capturedImage,
      logicalSize: context.logicalCropSize,
      sourceScaleFactor: reconciled.actualScale,
      minimumOutputScaleFactor: context.minimumOutputScaleFactor,
      colorSpaceName: context.configuration.colorSpaceName
    )

    let didPromote = promoted.scaleFactor > reconciled.actualScale + 0.0001
    let outputImage = didPromote
      ? FrozenAreaCaptureSession.sharpenPromotedImageIfUseful(
        promoted.image,
        colorSpaceName: context.configuration.colorSpaceName
      )
      : promoted.image

    return PreparedAreaCaptureResult(image: outputImage, scaleFactor: promoted.scaleFactor)
  }

  /// Pure geometry helper — given the actually-returned pixel dimensions, the
  /// logical screen frame, and the logical (point-space, top-left, screen-local)
  /// source rect, returns the pixel crop rect and the derived actual scale.
  /// Exposed (internal) for unit-testing scale-mismatch without SCStream.
  nonisolated static func reconciledPixelCrop(
    fullImagePixelWidth: Int,
    fullImagePixelHeight: Int,
    screenFrame: CGRect,
    logicalSourceRect: CGRect,
    logicalCropSize: CGSize,
    fallbackScale: CGFloat
  ) -> (pixelCrop: CGRect, actualScale: CGFloat) {
    let actualScale = dimensionScale(
      pixelWidth: fullImagePixelWidth,
      pixelHeight: fullImagePixelHeight,
      frame: screenFrame
    ) ?? max(fallbackScale, 1)

    let originX = (logicalSourceRect.origin.x * actualScale).rounded()
    let originY = (logicalSourceRect.origin.y * actualScale).rounded()
    let width = CGFloat(max(1, Int((logicalCropSize.width * actualScale).rounded())))
    let height = CGFloat(max(1, Int((logicalCropSize.height * actualScale).rounded())))

    let rawCrop = CGRect(x: originX, y: originY, width: width, height: height)
    let imageBounds = CGRect(
      x: 0,
      y: 0,
      width: CGFloat(fullImagePixelWidth),
      height: CGFloat(fullImagePixelHeight)
    )
    return (rawCrop.intersection(imageBounds), actualScale)
  }

  /// Pure straddle picker — index of the frame in `frames` with the LARGEST area
  /// intersection with `rect`, or `nil` if no frame intersects. Mirrors the
  /// pattern in `AreaSelectionWindow.primaryDisplayID`. Exposed (internal) for
  /// unit-testing the phase-03 selection without `NSScreen`.
  nonisolated static func indexOfLargestIntersectingFrame(
    frames: [CGRect],
    rect: CGRect
  ) -> Int? {
    var bestIndex: Int?
    var bestArea: CGFloat = 0
    for (index, frame) in frames.enumerated() {
      let intersection = frame.intersection(rect)
      guard !intersection.isEmpty else { continue }
      let area = intersection.width * intersection.height
      if area > bestArea {
        bestArea = area
        bestIndex = index
      }
    }
    return bestIndex
  }

  /// Returns all display IDs whose screen frame intersects with the given rect.
  /// When only one display intersects, the caller can use the optimized
  /// single-display path; when ≥2 intersect, the caller switches to the
  /// multi-display composite path. Exposed (internal) for unit-testing.
  nonisolated static func displayIDsIntersecting(_ rect: CGRect) -> Set<CGDirectDisplayID> {
    var result = Set<CGDirectDisplayID>()
    for screen in NSScreen.screens {
      guard let displayID = screen.displayID else { continue }
      if screen.frame.intersects(rect) {
        result.insert(displayID)
      }
    }
    return result
  }

  // MARK: - Multi-Display Area Composite

  /// Captures all intersecting displays in parallel and composites them into a
  /// single image using `FrozenAreaCaptureSession.cropCompositeImage`. This
  /// reuses the frozen path's battle-tested multi-display composite algorithm
  /// (DRY) for the live area capture path when a selection spans ≥2 displays.
  ///
  /// The caller (`captureArea` / `captureAreaAsImage`) already manages
  /// `isCapturing`, so this method uses `captureDisplaySnapshotsCore` to avoid
  /// double-setting the flag.
  private func captureAreaComposite(
    rect: CGRect,
    displayIDs: Set<CGDirectDisplayID>,
    showCursor: Bool,
    excludeDesktopIcons: Bool,
    excludeDesktopWidgets: Bool,
    excludeOwnApplication: Bool,
    prefetchedContentTask: ShareableContentPrefetchTask?
  ) async throws -> FrozenAreaCropResult {
    // 1. Capture all intersecting displays in parallel (uses core method to
    //    avoid isCapturing double-set since our caller already manages it).
    let snapshots = try await captureDisplaySnapshotsCore(
      displayIDs: displayIDs,
      showCursor: showCursor,
      excludeDesktopIcons: excludeDesktopIcons,
      excludeDesktopWidgets: excludeDesktopWidgets,
      excludeOwnApplication: excludeOwnApplication,
      prefetchedContentTask: prefetchedContentTask
    )

    // 2. Create a temporary session from the captured snapshots (DRY: reuses
    //    the frozen path's FrozenAreaCaptureSession without any freeze UI).
    let session = FrozenAreaCaptureSession.fromSnapshots(Array(snapshots.values))

    // 3. Determine the primary display (largest intersection) for the
    //    AreaSelectionResult. This mirrors how AreaSelectionWindow picks the
    //    primary display during selection.
    let screens = NSScreen.screens
    let frames = screens.map(\.frame)
    let primaryIndex = Self.indexOfLargestIntersectingFrame(frames: frames, rect: rect)
    let primaryDisplayID: CGDirectDisplayID
    if let primaryIndex, let displayID = screens[primaryIndex].displayID {
      primaryDisplayID = displayID
    } else {
      primaryDisplayID = displayIDs.first ?? CGMainDisplayID()
    }

    // 4. Build the selection result that the composite algorithm expects.
    let selectionResult = AreaSelectionResult(
      target: .rect(rect),
      displayID: primaryDisplayID,
      mode: .screenshot,
      displayIDs: displayIDs
    )

    // 5. Composite using the frozen path's algorithm: per-display intersection,
    //    coordinate transforms, pixel alignment, scale normalization, vImage
    //    promotion, sharpening, and CGContext compositing.
    let compositeResult = try session.cropCompositeImage(
      for: selectionResult,
      minimumOutputScaleFactor: preferredScreenshotOutputScaleFactor
    )

    DiagnosticLogger.shared.log(
      .info,
      .capture,
      "Area composite completed",
      context: [
        "displays": "\(displayIDs.count)",
        "outputSize": "\(compositeResult.image.width)x\(compositeResult.image.height)",
        "scaleFactor": String(format: "%.2f", Double(compositeResult.scaleFactor)),
      ]
    )

    return compositeResult
  }

  func makeAreaStreamConfiguration(
    from context: PreparedAreaCaptureContext,
    maximumFrameRate: Int = 30,
    showsCursor: Bool = false
  ) -> SCStreamConfiguration {
    let configuration = SCStreamConfiguration()
    configuration.width = context.outputWidth
    configuration.height = context.outputHeight
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    configuration.showsCursor = showsCursor
    configuration.sourceRect = context.sourceRect
    configuration.queueDepth = maximumFrameRate >= 60 ? 3 : 2
    configuration.minimumFrameInterval = CMTime(
      value: 1,
      timescale: CMTimeScale(max(1, maximumFrameRate))
    )
    let includeWindowShadow = UserDefaults.standard.object(forKey: PreferencesKeys.captureIncludeWindowShadow) as? Bool ?? WindowShadowPreference.defaultIncludeShadow
    if #available(macOS 14.0, *) {
      configuration.ignoreShadowsSingleWindow = WindowShadowPreference.ignoreShadowsSingleWindow(includeShadow: includeWindowShadow)
    }
    if #available(macOS 14.2, *) {
      configuration.captureResolution = .best
    }
    configuration.colorSpaceName = context.configuration.colorSpaceName
    return configuration
  }

  private func makePreparedAreaCaptureContext(
    rect: CGRect,
    showCursor: Bool,
    excludeDesktopIcons: Bool,
    excludeDesktopWidgets: Bool,
    excludeOwnApplication: Bool,
    prefetchedContentTask: ShareableContentPrefetchTask?,
    minimumOutputScaleFactor: CGFloat = ScreenCaptureManager.minimumScreenshotOutputScaleFactor
  ) async throws -> PreparedAreaCaptureContext {
    let includeDesktopWindows = excludeDesktopIcons || excludeDesktopWidgets
    let content = try await loadShareableContent(
      prefetchedContentTask: prefetchedContentTask,
      includeDesktopWindows: includeDesktopWindows
    )

    // Pick the display with the LARGEST intersection (phase-03). Order-dependent
    // `first` pick was wrong for straddling selections — see issue #308 notes and
    // `AreaSelectionWindow.primaryDisplayID` for the mirrored pattern.
    let targetScreen: NSScreen?
    if let bestIndex = Self.indexOfLargestIntersectingFrame(
      frames: NSScreen.screens.map(\.frame),
      rect: rect
    ) {
      targetScreen = NSScreen.screens[bestIndex]
    } else {
      targetScreen = nil
    }

    let targetDisplayID: CGDirectDisplayID
    if let screen = targetScreen,
       let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
      targetDisplayID = displayID
    } else {
      targetDisplayID = CGMainDisplayID()
    }

    guard let display = content.displays.first(where: { $0.displayID == Int(targetDisplayID) })
            ?? content.displays.first
    else {
      throw CaptureError.noDisplayFound
    }

    let contentFilter = buildFilter(
      display: display,
      content: content,
      excludeDesktopIcons: excludeDesktopIcons,
      excludeDesktopWidgets: excludeDesktopWidgets,
      excludeOwnApplication: excludeOwnApplication
    )
    guard let matchingScreen = targetScreen ?? NSScreen.screens.first(where: {
      Int($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0)
        == display.displayID
    }) else {
      throw CaptureError.noDisplayFound
    }

    let screenFrame = matchingScreen.frame
    let nativeScaleFactor = displaySnapshotScaleFactor(
      for: matchingScreen,
      display: display,
      contentFilter: contentFilter
    )
    let captureScale = nativeScaleFactor
    let outputScale = max(nativeScaleFactor, minimumOutputScaleFactor)

    let relativeRect = CGRect(
      x: rect.origin.x - screenFrame.origin.x,
      y: rect.origin.y - screenFrame.origin.y,
      width: rect.width,
      height: rect.height
    )

    let screenBounds = CGRect(x: 0, y: 0, width: screenFrame.width, height: screenFrame.height)
    let clampedRect = relativeRect.intersection(screenBounds)

    guard !clampedRect.isEmpty else {
      throw CaptureError.captureFailed(L10n.ScreenCapture.selectionOutsideDisplayBounds)
    }

    let alignedRect = pixelAlignedRect(clampedRect, scaleFactor: captureScale, bounds: screenBounds)
    guard !alignedRect.isEmpty else {
      throw CaptureError.captureFailed(L10n.ScreenCapture.selectionOutsideDisplayBounds)
    }

    let flippedY = screenFrame.height - alignedRect.origin.y - alignedRect.height
    let sourceRect = CGRect(
      x: alignedRect.origin.x,
      y: flippedY,
      width: alignedRect.width,
      height: alignedRect.height
    )
    let outputWidth = max(1, Int((alignedRect.width * captureScale).rounded()))
    let outputHeight = max(1, Int((alignedRect.height * captureScale).rounded()))
    let fullCaptureWidth = max(1, Int((screenFrame.width * captureScale).rounded()))
    let fullCaptureHeight = max(1, Int((screenFrame.height * captureScale).rounded()))

    let config = SCStreamConfiguration()
    let includeWindowShadow = UserDefaults.standard.object(forKey: PreferencesKeys.captureIncludeWindowShadow) as? Bool ?? WindowShadowPreference.defaultIncludeShadow
    if #available(macOS 14.0, *) { config.ignoreShadowsSingleWindow = WindowShadowPreference.ignoreShadowsSingleWindow(includeShadow: includeWindowShadow) }
    if #available(macOS 14.2, *) { config.captureResolution = .best }
    config.width = fullCaptureWidth
    config.height = fullCaptureHeight
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.showsCursor = showCursor
    if let colorSpaceName = preferredCaptureColorSpaceName(for: matchingScreen) {
      config.colorSpaceName = colorSpaceName
    }

    let pixelCropRect = CGRect(
      x: (sourceRect.origin.x * captureScale).rounded(),
      y: (sourceRect.origin.y * captureScale).rounded(),
      width: CGFloat(outputWidth),
      height: CGFloat(outputHeight)
    ).intersection(
      CGRect(x: 0, y: 0, width: CGFloat(fullCaptureWidth), height: CGFloat(fullCaptureHeight))
    )

    let context = PreparedAreaCaptureContext(
      contentFilter: contentFilter,
      configuration: config,
      pixelCropRect: pixelCropRect,
      sourceRect: sourceRect,
      outputWidth: outputWidth,
      outputHeight: outputHeight,
      scaleFactor: captureScale,
      screenFrame: screenFrame,
      logicalCropSize: alignedRect.size,
      minimumOutputScaleFactor: outputScale,
      assumedFullPixelSize: CGSize(width: fullCaptureWidth, height: fullCaptureHeight),
      displayID: targetDisplayID
    )

    DiagnosticLogger.shared.log(
      .debug,
      .capture,
      "Area prepared context",
      context: [
        "displayID": "\(targetDisplayID)",
        "screenFrame": "\(Int(screenFrame.width))x\(Int(screenFrame.height))",
        "nativeScale": String(format: "%.3f", Double(nativeScaleFactor)),
        "scale": String(format: "%.3f", Double(captureScale)),
        "outputScale": String(format: "%.3f", Double(outputScale)),
        "assumedFull": "\(fullCaptureWidth)x\(fullCaptureHeight)",
        "assumedPixelCrop": "\(Int(pixelCropRect.origin.x))x\(Int(pixelCropRect.origin.y))+\(Int(pixelCropRect.width))x\(Int(pixelCropRect.height))",
      ]
    )

    return context
  }

  private func captureWindowImage(
    _ window: SCWindow,
    fallbackTarget: WindowCaptureTarget,
    showCursor: Bool
  ) async throws -> (image: CGImage, scaleFactor: CGFloat) {
    let contentFilter = SCContentFilter(desktopIndependentWindow: window)
    let scaleFactor = max(
      resolvedWindowScaleFactor(window: window, fallbackDisplayID: fallbackTarget.displayID),
      preferredScreenshotOutputScaleFactor
    )
    let contentRect: CGRect
    if #available(macOS 14.0, *) {
      contentRect = contentFilter.contentRect.isEmpty ? window.frame : contentFilter.contentRect
    } else {
      contentRect = window.frame
    }

    let configuration = SCStreamConfiguration()
    let includeWindowShadow = UserDefaults.standard.object(forKey: PreferencesKeys.captureIncludeWindowShadow) as? Bool ?? WindowShadowPreference.defaultIncludeShadow
    if #available(macOS 14.0, *) { configuration.ignoreShadowsSingleWindow = WindowShadowPreference.ignoreShadowsSingleWindow(includeShadow: includeWindowShadow) }
    if #available(macOS 14.2, *) { configuration.captureResolution = .best }
    configuration.width = max(1, Int((contentRect.width * scaleFactor).rounded()))
    configuration.height = max(1, Int((contentRect.height * scaleFactor).rounded()))
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    configuration.showsCursor = showCursor

    if let screen = screenContainingWindow(window, fallbackDisplayID: fallbackTarget.displayID),
       let colorSpaceName = preferredCaptureColorSpaceName(for: screen) {
      configuration.colorSpaceName = colorSpaceName
    }

    let image = try await Self.captureImageCompat(
      contentFilter: contentFilter,
      configuration: configuration
    )
    let normalizedImage = await Task.detached(priority: .userInitiated) {
      Self.trimTransparentWindowFringe(from: image)
    }.value
    if normalizedImage.didTrim {
      DiagnosticLogger.shared.log(
        .debug,
        .capture,
        "Trimmed transparent window capture fringe",
        context: [
          "input": "\(image.width)x\(image.height)",
          "output": "\(normalizedImage.image.width)x\(normalizedImage.image.height)"
        ]
      )
    }
    return (normalizedImage.image, scaleFactor)
  }

  private func resolvedWindowScaleFactor(
    window: SCWindow,
    fallbackDisplayID: CGDirectDisplayID
  ) -> CGFloat {
    if #available(macOS 14.0, *) {
      let filter = SCContentFilter(desktopIndependentWindow: window)
      let pointPixelScale = CGFloat(filter.pointPixelScale)
      if pointPixelScale > 0 {
        return pointPixelScale
      }
    }

    if let screen = screenContainingWindow(window, fallbackDisplayID: fallbackDisplayID) {
      return screen.backingScaleFactor
    }

    return NSScreen.main?.backingScaleFactor ?? 2.0
  }

  private func screenContainingWindow(
    _ window: SCWindow,
    fallbackDisplayID: CGDirectDisplayID
  ) -> NSScreen? {
    let midpoint = CGPoint(x: window.frame.midX, y: window.frame.midY)
    if let screen = NSScreen.screens.first(where: { $0.frame.contains(midpoint) }) {
      return screen
    }
    if let screen = NSScreen.screens.first(where: { $0.displayID == fallbackDisplayID }) {
      return screen
    }
    return NSScreen.screens.max {
      $0.frame.intersection(window.frame).width * $0.frame.intersection(window.frame).height
        < $1.frame.intersection(window.frame).width * $1.frame.intersection(window.frame).height
    }
  }

  private nonisolated static func trimTransparentWindowFringe(
    from image: CGImage,
    alphaThreshold: UInt8 = 1
  ) -> (image: CGImage, didTrim: Bool) {
    guard let alphaBounds = transparentFringeBounds(in: image, alphaThreshold: alphaThreshold) else {
      return (image, false)
    }

    let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let cropRect = alphaBounds.integral.intersection(imageBounds)
    guard
      !cropRect.isEmpty,
      cropRect.integral != imageBounds.integral,
      let croppedImage = image.cropping(to: cropRect)
    else {
      return (image, false)
    }

    return (croppedImage, true)
  }

  private nonisolated static func transparentFringeBounds(
    in image: CGImage,
    alphaThreshold: UInt8
  ) -> CGRect? {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }

    if let directBounds = directTransparentFringeBounds(in: image, alphaThreshold: alphaThreshold) {
      return directBounds
    }

    return redrawTransparentFringeBounds(in: image, alphaThreshold: alphaThreshold)
  }

  private nonisolated static func directTransparentFringeBounds(
    in image: CGImage,
    alphaThreshold: UInt8
  ) -> CGRect? {
    guard
      image.bitsPerComponent == 8,
      image.bitsPerPixel == 32,
      let providerData = image.dataProvider?.data,
      let baseAddress = CFDataGetBytePtr(providerData),
      let alphaOffset = alphaByteOffset(for: image)
    else {
      return nil
    }

    let width = image.width
    let height = image.height
    let bytesPerPixel = 4
    let bytesPerRow = image.bytesPerRow
    let dataLength = CFDataGetLength(providerData)
    guard bytesPerRow >= width * bytesPerPixel, dataLength >= height * bytesPerRow else {
      return nil
    }

    let pixels = UnsafeRawBufferPointer(start: baseAddress, count: dataLength)
    return scanTransparentFringeBounds(
      pixels: pixels,
      width: width,
      height: height,
      bytesPerRow: bytesPerRow,
      bytesPerPixel: bytesPerPixel,
      alphaOffset: alphaOffset,
      alphaThreshold: alphaThreshold
    )
  }

  private nonisolated static func redrawTransparentFringeBounds(
    in image: CGImage,
    alphaThreshold: UInt8
  ) -> CGRect? {
    let width = image.width
    let height = image.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    let didDraw = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
      guard let baseAddress = rawBuffer.baseAddress else { return false }
      guard let context = CGContext(
        data: baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      ) else {
        return false
      }

      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard didDraw else { return nil }

    return pixels.withUnsafeBytes { rawBuffer in
      scanTransparentFringeBounds(
        pixels: rawBuffer,
        width: width,
        height: height,
        bytesPerRow: bytesPerRow,
        bytesPerPixel: bytesPerPixel,
        alphaOffset: 3,
        alphaThreshold: alphaThreshold
      )
    }
  }

  private nonisolated static func scanTransparentFringeBounds(
    pixels: UnsafeRawBufferPointer,
    width: Int,
    height: Int,
    bytesPerRow: Int,
    bytesPerPixel: Int,
    alphaOffset: Int,
    alphaThreshold: UInt8
  ) -> CGRect? {
    guard width > 0, height > 0, bytesPerPixel > alphaOffset else { return nil }

    func rowHasContent(_ y: Int) -> Bool {
      let rowStart = y * bytesPerRow
      var offset = rowStart + alphaOffset
      let rowEnd = rowStart + (width * bytesPerPixel)
      while offset < rowEnd {
        if pixels[offset] > alphaThreshold {
          return true
        }
        offset += bytesPerPixel
      }
      return false
    }

    func columnHasContent(_ x: Int, minY: Int, maxY: Int) -> Bool {
      var offset = minY * bytesPerRow + x * bytesPerPixel + alphaOffset
      for _ in minY...maxY {
        if pixels[offset] > alphaThreshold {
          return true
        }
        offset += bytesPerRow
      }
      return false
    }

    var minY = 0
    while minY < height && !rowHasContent(minY) {
      minY += 1
    }
    guard minY < height else { return nil }

    var maxY = height - 1
    while maxY > minY && !rowHasContent(maxY) {
      maxY -= 1
    }

    var minX = 0
    while minX < width && !columnHasContent(minX, minY: minY, maxY: maxY) {
      minX += 1
    }

    var maxX = width - 1
    while maxX > minX && !columnHasContent(maxX, minY: minY, maxY: maxY) {
      maxX -= 1
    }

    return CGRect(
      x: minX,
      y: minY,
      width: maxX - minX + 1,
      height: maxY - minY + 1
    )
  }

  private nonisolated static func alphaByteOffset(for image: CGImage) -> Int? {
    guard image.bitsPerComponent == 8, image.bitsPerPixel == 32 else {
      return nil
    }

    guard let alphaInfo = CGImageAlphaInfo(rawValue: image.bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue) else {
      return nil
    }
    let byteOrder = CGBitmapInfo(rawValue: image.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue)

    switch alphaInfo {
    case .first, .premultipliedFirst:
      return byteOrder == .byteOrder32Little ? 3 : 0
    case .last, .premultipliedLast:
      return byteOrder == .byteOrder32Little ? 0 : 3
    default:
      return nil
    }
  }

  private func displaySnapshotScaleFactor(
    for screen: NSScreen?,
    display: SCDisplay,
    contentFilter: SCContentFilter? = nil
  ) -> CGFloat {
    if #available(macOS 14.0, *), let contentFilter {
      let pointPixelScale = CGFloat(contentFilter.pointPixelScale)
      if pointPixelScale.isFinite, pointPixelScale > 0 {
        return pointPixelScale
      }
    }

    if let screen,
       let displayScale = Self.dimensionScale(
        pixelWidth: display.width,
        pixelHeight: display.height,
        frame: screen.frame
       ) {
      return displayScale
    }

    if let displayScale = Self.dimensionScale(
      pixelWidth: display.width,
      pixelHeight: display.height,
      frame: display.frame
    ) {
      return displayScale
    }

    if let screen {
      return max(screen.backingScaleFactor, 1)
    }

    return 2
  }

  private nonisolated static func imageScaleFactor(
    for image: CGImage,
    screenFrame: CGRect,
    fallback: CGFloat
  ) -> CGFloat {
    dimensionScale(
      pixelWidth: image.width,
      pixelHeight: image.height,
      frame: screenFrame
    ) ?? max(fallback, 1)
  }

  private nonisolated static func promoteScreenshotImageIfNeeded(
    _ image: CGImage,
    logicalSize: CGSize,
    sourceScaleFactor: CGFloat,
    minimumOutputScaleFactor: CGFloat,
    colorSpaceName: CFString?
  ) -> (image: CGImage, scaleFactor: CGFloat) {
    FrozenAreaCaptureSession.imageByPromotingScaleIfNeeded(
      image,
      logicalSize: logicalSize,
      sourceScaleFactor: sourceScaleFactor,
      minimumOutputScaleFactor: max(minimumOutputScaleFactor, Self.minimumScreenshotOutputScaleFactor),
      colorSpaceName: colorSpaceName
    )
  }

  private nonisolated static func dimensionScale(
    pixelWidth: Int,
    pixelHeight: Int,
    frame: CGRect
  ) -> CGFloat? {
    let widthScale = frame.width > 0 ? CGFloat(pixelWidth) / frame.width : 0
    let heightScale = frame.height > 0 ? CGFloat(pixelHeight) / frame.height : 0
    let candidates = [widthScale, heightScale].filter { $0.isFinite && $0 > 0 }
    return candidates.max()
  }

  private func pixelAlignedRect(_ rect: CGRect, scaleFactor: CGFloat, bounds: CGRect) -> CGRect {
    guard scaleFactor > 0 else { return rect.intersection(bounds) }

    let minX = floor(rect.minX * scaleFactor) / scaleFactor
    let minY = floor(rect.minY * scaleFactor) / scaleFactor
    let maxX = ceil(rect.maxX * scaleFactor) / scaleFactor
    let maxY = ceil(rect.maxY * scaleFactor) / scaleFactor

    let alignedRect = CGRect(
      x: minX,
      y: minY,
      width: max(0, maxX - minX),
      height: max(0, maxY - minY)
    )

    return alignedRect.intersection(bounds)
  }

  private func makeDisplaySnapshotConfiguration(
    for screen: NSScreen,
    scaleFactor: CGFloat,
    showsCursor: Bool
  ) -> SCStreamConfiguration {
    let configuration = SCStreamConfiguration()
    let includeWindowShadow = UserDefaults.standard.object(forKey: PreferencesKeys.captureIncludeWindowShadow) as? Bool ?? WindowShadowPreference.defaultIncludeShadow
    if #available(macOS 14.0, *) { configuration.ignoreShadowsSingleWindow = WindowShadowPreference.ignoreShadowsSingleWindow(includeShadow: includeWindowShadow) }
    if #available(macOS 14.2, *) { configuration.captureResolution = .best }
    configuration.width = max(1, Int((screen.frame.width * scaleFactor).rounded()))
    configuration.height = max(1, Int((screen.frame.height * scaleFactor).rounded()))
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    configuration.showsCursor = showsCursor
    if let colorSpaceName = preferredCaptureColorSpaceName(for: screen) {
      configuration.colorSpaceName = colorSpaceName
    }
    return configuration
  }

  func preferredCaptureColorSpaceName(for screen: NSScreen) -> CFString? {
    guard let colorSpaceName = screen.colorSpace?.cgColorSpace?.name else {
      return nil
    }

    if CFEqual(colorSpaceName, CGColorSpace.displayP3) {
      return CGColorSpace.displayP3
    }

    if CFEqual(colorSpaceName, CGColorSpace.sRGB) {
      return CGColorSpace.sRGB
    }

    return nil
  }

  // MARK: - Filter Builder

  private func loadShareableContent(
    prefetchedContentTask: ShareableContentPrefetchTask?,
    includeDesktopWindows: Bool = false
  ) async throws -> SCShareableContent {
    let cacheMode = shareableContentCacheMode(includeDesktopWindows: includeDesktopWindows)
    let loadStartedAt = Date()

    if let prefetchedContentTask {
      do {
        let content = try await prefetchedContentTask.value
        logShareableContentLoad(mode: cacheMode, source: "prefetched", startedAt: loadStartedAt)
        return content
      } catch {
        invalidateShareableContentCache(mode: cacheMode)
        logger.debug("Prefetched shareable content failed; refetching current content")
      }
    }

    if let cachedTask = prefetchShareableContent(includeDesktopWindows: includeDesktopWindows) {
      do {
        let content = try await cachedTask.value
        logShareableContentLoad(mode: cacheMode, source: "cached", startedAt: loadStartedAt)
        return content
      } catch {
        invalidateShareableContentCache(mode: cacheMode)
        logger.debug("Cached shareable content failed; forcing refresh")
      }
    }

    guard let refreshedTask = prefetchShareableContent(
      includeDesktopWindows: includeDesktopWindows,
      forceRefresh: true
    ) else {
      let content = try await fetchShareableContent(includeDesktopWindows: includeDesktopWindows)
      logShareableContentLoad(mode: cacheMode, source: "direct", startedAt: loadStartedAt)
      return content
    }

    do {
      let content = try await refreshedTask.value
      logShareableContentLoad(mode: cacheMode, source: "refreshed", startedAt: loadStartedAt)
      return content
    } catch {
      invalidateShareableContentCache(mode: cacheMode)
      throw error
    }
  }

  private func ensureCaptureAvailability() async -> CaptureError? {
    await checkPermission()

    switch permissionStatus {
    case .granted:
      return nil
    case .notGranted:
      let granted = await requestPermission()
      if granted {
        return nil
      }
      return .permissionDenied
    case .grantedButUnavailableDueToAppIdentity(let reason):
      return .unavailable(reason)
    }
  }

  private func updatePermissionStatus(systemGranted: Bool) {
    if !systemGranted {
      permissionStatus = .notGranted
      hasPermission = false
      invalidateShareableContentCache()
      return
    }

    let identityHealth = AppIdentityManager.shared.health
    if !identityHealth.isHealthy {
      permissionStatus = .grantedButUnavailableDueToAppIdentity(identityHealth.summary)
      hasPermission = false
      invalidateShareableContentCache()
      return
    }

    permissionStatus = .granted
    hasPermission = true
    _ = prefetchShareableContent()
    if DesktopIconManager.shared.isIconHidingEnabled || DesktopIconManager.shared.isWidgetHidingEnabled {
      _ = prefetchShareableContent(includeDesktopWindows: true)
    }
  }

  private func shareableContentCacheMode(includeDesktopWindows: Bool) -> ShareableContentCacheMode {
    includeDesktopWindows ? .desktopInclusive : .standard
  }

  private func shareableContentCacheEntry(for mode: ShareableContentCacheMode) -> ShareableContentCacheEntry? {
    switch mode {
    case .standard:
      standardShareableContentCache
    case .desktopInclusive:
      desktopInclusiveShareableContentCache
    }
  }

  private func setShareableContentCacheEntry(
    _ entry: ShareableContentCacheEntry?,
    for mode: ShareableContentCacheMode
  ) {
    switch mode {
    case .standard:
      standardShareableContentCache = entry
    case .desktopInclusive:
      desktopInclusiveShareableContentCache = entry
    }
  }

  private func fetchShareableContent(includeDesktopWindows: Bool) async throws -> SCShareableContent {
    if includeDesktopWindows {
      return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }
    return try await SCShareableContent.current
  }

  private func makeShareableContentPrefetchTask(includeDesktopWindows: Bool) -> ShareableContentPrefetchTask {
    Task(priority: .userInitiated) {
      try await self.fetchShareableContent(includeDesktopWindows: includeDesktopWindows)
    }
  }

  private func logShareableContentLoad(
    mode: ShareableContentCacheMode,
    source: String,
    startedAt: Date
  ) {
    let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
    DiagnosticLogger.shared.log(
      .debug,
      .capture,
      "Shareable content loaded",
      context: [
        "mode": mode.rawValue,
        "source": source,
        "duration_ms": "\(durationMs)",
      ]
    )
  }

  private func invalidateShareableContentCache(mode: ShareableContentCacheMode? = nil) {
    switch mode {
    case .standard:
      standardShareableContentCache = nil
    case .desktopInclusive:
      desktopInclusiveShareableContentCache = nil
    case nil:
      standardShareableContentCache = nil
      desktopInclusiveShareableContentCache = nil
    }
  }

  /// Compatibility wrapper: uses SCScreenshotManager on macOS 14+, falls back to SCStream single-frame capture on macOS 13.
  private static func captureImageCompat(
    contentFilter: SCContentFilter,
    configuration: SCStreamConfiguration
  ) async throws -> CGImage {
    if #available(macOS 14.0, *) {
      return try await SCScreenshotManager.captureImage(
        contentFilter: contentFilter,
        configuration: configuration
      )
    } else {
      // Fallback: use SCStream to capture a single frame. The session keeps the
      // stream/output/delegate alive, surfaces stream errors, and bounds the wait
      // with a timeout so the capture can never hang forever (issue #286).
      return try await SingleFrameStreamCaptureSession.capture(
        contentFilter: contentFilter,
        configuration: configuration
      )
    }
  }

  /// Build SCContentFilter, optionally excluding Finder (desktop icons) and/or widgets.
  /// Open Finder windows are preserved via exceptingWindows.
  /// Wallpaper is preserved because it's rendered by Dock/WallpaperAgent, not Finder.
  private func buildFilter(
    display: SCDisplay,
    content: SCShareableContent,
    excludeDesktopIcons: Bool,
    excludeDesktopWidgets: Bool,
    excludeOwnApplication: Bool
  ) -> SCContentFilter {
    let iconManager = DesktopIconManager.shared
    var excludedApps: [SCRunningApplication] = []
    var exceptedWindows: [SCWindow] = []

    if excludeOwnApplication, let bundleID = Bundle.main.bundleIdentifier {
      excludedApps += content.applications.filter { $0.bundleIdentifier == bundleID }
    }

    if excludeDesktopIcons {
      excludedApps += iconManager.getFinderApps(from: content)
      exceptedWindows += iconManager.getVisibleFinderWindows(from: content)
    }

    if excludeDesktopWidgets {
      excludedApps += iconManager.getWidgetApps(from: content)
    }

    if !excludedApps.isEmpty {
      return SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: exceptedWindows)
    }
    return SCContentFilter(display: display, excludingWindows: [])
  }
}

// MARK: - Image Format

enum ImageFormat {
  case png
  case jpeg(quality: CGFloat)
  case webp

  var fileExtension: String {
    switch self {
    case .png: return "png"
    case .jpeg: return "jpg"
    case .webp: return "webp"
    }
  }

  var utType: CFString {
    switch self {
    case .png: return "public.png" as CFString
    case .jpeg: return "public.jpeg" as CFString
    case .webp: return "org.webmproject.webp" as CFString
    }
  }
}
