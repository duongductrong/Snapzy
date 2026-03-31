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
import os.log
import ScreenCaptureKit

private let logger = Logger(subsystem: "Snapzy", category: "ScreenCaptureManager")
typealias ShareableContentPrefetchTask = Task<SCShareableContent, Error>

/// Result type for capture operations
enum CaptureResult {
  case success(URL)
  case failure(CaptureError)
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
      return "Screen capture permission denied"
    case .unavailable(let reason):
      return reason
    case .noDisplayFound:
      return "No display found to capture"
    case .captureFailed(let reason):
      return "Capture failed: \(reason)"
    case .saveFailed(let reason):
      return "Failed to save screenshot: \(reason)"
    case .cancelled:
      return "Capture was cancelled"
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

  static let shared = ScreenCaptureManager()

  @Published private(set) var permissionStatus: ScreenRecordingPermissionStatus = .notGranted
  @Published private(set) var hasPermission: Bool = false
  @Published private(set) var isCapturing: Bool = false

  /// Publisher for successful capture completions
  private let captureCompletedSubject = PassthroughSubject<URL, Never>()
  var captureCompletedPublisher: AnyPublisher<URL, Never> {
    captureCompletedSubject.eraseToAnyPublisher()
  }

  private init() {
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
  func prefetchShareableContent() -> ShareableContentPrefetchTask? {
    guard hasPermission else { return nil }

    return Task(priority: .userInitiated) {
      try await SCShareableContent.current
    }
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
    prefetchedContentTask: ShareableContentPrefetchTask? = nil
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
      let scaleFactor: CGFloat
      if let screen = NSScreen.screens.first(where: {
        Int($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0)
          == display.displayID
      }) {
        scaleFactor = screen.backingScaleFactor
      } else {
        scaleFactor = display.frame.width > 0 ? CGFloat(display.width) / display.frame.width : 2.0
      }

      let config = SCStreamConfiguration()
      if #available(macOS 14.0, *) { config.ignoreShadowsSingleWindow = false }
      if #available(macOS 14.2, *) { config.captureResolution = .best }
      config.width = Int(CGFloat(display.width) * scaleFactor)
      config.height = Int(CGFloat(display.height) * scaleFactor)
      config.pixelFormat = kCVPixelFormatType_32BGRA
      config.showsCursor = showCursor

      // Capture the image (compat: SCScreenshotManager requires macOS 14+)
      let image = try await captureImageCompat(
        contentFilter: filter,
        configuration: config
      )

      // Save the image
      return await saveImage(image, to: saveDirectory, fileName: fileName, format: format)

    } catch {
      DiagnosticLogger.shared.log(.error, .capture, "Fullscreen capture failed: \(error.localizedDescription)")
      return .failure(.captureFailed(error.localizedDescription))
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
    prefetchedContentTask: ShareableContentPrefetchTask? = nil
  ) async -> CaptureResult {
    if let unavailableError = await ensureCaptureAvailability() {
      return .failure(unavailableError)
    }

    isCapturing = true
    defer { isCapturing = false }
    DiagnosticLogger.shared.log(.info, .capture, "Area capture started \(Int(rect.width))x\(Int(rect.height))")

    do {
      let includeDesktopWindows = excludeDesktopIcons || excludeDesktopWidgets
      let content = try await loadShareableContent(
        prefetchedContentTask: prefetchedContentTask,
        includeDesktopWindows: includeDesktopWindows
      )

      // Find the display containing the rect using NSScreen frames (same coordinate system as input)
      // Then get the matching SCDisplay
      var targetScreen: NSScreen?
      for screen in NSScreen.screens {
        if screen.frame.intersects(rect) {
          targetScreen = screen
          break
        }
      }

      // Get the display ID from NSScreen
      let targetDisplayID: CGDirectDisplayID
      if let screen = targetScreen,
         let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
        targetDisplayID = displayID
      } else {
        targetDisplayID = CGMainDisplayID()
      }

      // Find matching SCDisplay
      guard let display = content.displays.first(where: { $0.displayID == Int(targetDisplayID) })
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
      let config = SCStreamConfiguration()
      if #available(macOS 14.0, *) { config.ignoreShadowsSingleWindow = false }
      if #available(macOS 14.2, *) { config.captureResolution = .best }
      config.pixelFormat = kCVPixelFormatType_32BGRA
      config.showsCursor = showCursor

      // Get the display's backing scale factor (2.0 for Retina displays)
      let scaleFactor: CGFloat
      if let screen = targetScreen {
        scaleFactor = screen.backingScaleFactor
      } else if let screen = NSScreen.screens.first(where: {
        Int($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0)
          == display.displayID
      }) {
        scaleFactor = screen.backingScaleFactor
      } else {
        scaleFactor = display.frame.width > 0 ? CGFloat(display.width) / display.frame.width : 2.0
      }

      // Get the NSScreen frame for coordinate conversion (Cocoa coordinates)
      guard let matchingScreen = targetScreen ?? NSScreen.screens.first(where: {
        Int($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0)
          == display.displayID
      }) else {
        return .failure(.noDisplayFound)
      }

      let screenFrame = matchingScreen.frame

      // Calculate relative rect within the screen (in Cocoa coordinates)
      let relativeRect = CGRect(
        x: rect.origin.x - screenFrame.origin.x,
        y: rect.origin.y - screenFrame.origin.y,
        width: rect.width,
        height: rect.height
      )

      // Clamp to screen bounds
      let screenBounds = CGRect(x: 0, y: 0, width: screenFrame.width, height: screenFrame.height)
      let clampedRect = relativeRect.intersection(screenBounds)

      // Guard against empty intersection
      guard !clampedRect.isEmpty else {
        return .failure(.captureFailed("Selection area is outside display bounds"))
      }

      // Capture full display at native pixel resolution (avoid sourceRect interpolation blur)
      config.width = Int(CGFloat(display.width) * scaleFactor)
      config.height = Int(CGFloat(display.height) * scaleFactor)

      // Capture the full display image
      let fullImage = try await captureImageCompat(
        contentFilter: filter,
        configuration: config
      )

      // Post-capture crop: convert clamped rect to pixel coordinates (top-left origin)
      // and crop the CGImage directly — no resampling, pixel-perfect quality
      let flippedY = screenFrame.height - clampedRect.origin.y - clampedRect.height
      let pixelCropRect = CGRect(
        x: ceil(clampedRect.origin.x * scaleFactor),
        y: ceil(flippedY * scaleFactor),
        width: ceil(clampedRect.width * scaleFactor),
        height: ceil(clampedRect.height * scaleFactor)
      )

      guard let croppedImage = fullImage.cropping(to: pixelCropRect) else {
        return .failure(.captureFailed("Failed to crop captured image"))
      }

      // Save the cropped image
      return await saveImage(croppedImage, to: saveDirectory, fileName: fileName, format: format)

    } catch {
      DiagnosticLogger.shared.log(.error, .capture, "Area capture failed: \(error.localizedDescription)")
      return .failure(.captureFailed(error.localizedDescription))
    }
  }

  // MARK: - Image Saving

  /// Save a CGImage to disk with write verification
  private func saveImage(
    _ image: CGImage,
    to directory: URL,
    fileName: String?,
    format: ImageFormat
  ) async -> CaptureResult {
    let directoryAccess = SandboxFileAccessManager.shared.beginAccessingURL(directory)
    defer { directoryAccess.stop() }
    let scopedDirectory = directoryAccess.url

    // Resolve filename using user-configurable template (with legacy fallback).
    let baseName = CaptureOutputNaming.resolveBaseName(
      customName: fileName,
      kind: .screenshot
    )
    let fileExtension = format.fileExtension

    logger.info("Saving capture to \(scopedDirectory.lastPathComponent)/\(baseName).\(fileExtension)")

    // Capture format properties before entering detached task
    let utType = format.utType

    // Move file I/O to background thread to avoid blocking main thread
    let isWebP = fileExtension == "webp"
    let writeResult: Result<URL, CaptureError> = await Task.detached {
      // Create directory if needed
      do {
        try FileManager.default.createDirectory(at: scopedDirectory, withIntermediateDirectories: true)
      } catch {
        return .failure(.saveFailed("Could not create directory: \(error.localizedDescription)"))
      }

      let fileURL = CaptureOutputNaming.makeUniqueFileURL(
        in: scopedDirectory,
        baseName: baseName,
        fileExtension: fileExtension
      )

      if isWebP {
        // WebP: use WebPEncoder (cwebp CLI) since ImageIO doesn't support WebP encoding
        guard WebPEncoderService.write(image, to: fileURL) else {
          return .failure(.saveFailed("WebP encoding failed"))
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
          return .failure(.saveFailed("Could not create image destination"))
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
          return .failure(.saveFailed("Failed to write image to disk"))
        }
      }

      // Verify file is fully written
      let verified = await Self.verifyFileWritten(at: fileURL)
      if verified {
        return .success(fileURL)
      } else {
        return .failure(.saveFailed("File write verification failed for \(fileURL.lastPathComponent)"))
      }
    }.value

    switch writeResult {
    case .success(let url):
      DiagnosticLogger.shared.log(.info, .capture, "Capture saved: \(url.lastPathComponent)")
      captureCompletedSubject.send(url)
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
    format: ImageFormat = .png
  ) async -> CaptureResult {
    await saveImage(image, to: directory, fileName: fileName, format: format)
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

    let includeDesktopWindows = excludeDesktopIcons || excludeDesktopWidgets
    let content = try await loadShareableContent(
      prefetchedContentTask: prefetchedContentTask,
      includeDesktopWindows: includeDesktopWindows
    )

    // Find the display containing the rect
    var targetScreen: NSScreen?
    for screen in NSScreen.screens {
      if screen.frame.intersects(rect) {
        targetScreen = screen
        break
      }
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

    let filter = buildFilter(
      display: display,
      content: content,
      excludeDesktopIcons: excludeDesktopIcons,
      excludeDesktopWidgets: excludeDesktopWidgets,
      excludeOwnApplication: excludeOwnApplication
    )
    let config = SCStreamConfiguration()
    if #available(macOS 14.0, *) { config.ignoreShadowsSingleWindow = false }
    if #available(macOS 14.2, *) { config.captureResolution = .best }
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.showsCursor = false

    let scaleFactor: CGFloat
    if let screen = targetScreen {
      scaleFactor = screen.backingScaleFactor
    } else {
      scaleFactor = 2.0
    }

    guard let matchingScreen = targetScreen ?? NSScreen.screens.first(where: {
      Int($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0)
        == display.displayID
    }) else {
      throw CaptureError.noDisplayFound
    }

    let screenFrame = matchingScreen.frame

    let relativeRect = CGRect(
      x: rect.origin.x - screenFrame.origin.x,
      y: rect.origin.y - screenFrame.origin.y,
      width: rect.width,
      height: rect.height
    )

    let screenBounds = CGRect(x: 0, y: 0, width: screenFrame.width, height: screenFrame.height)
    let clampedRect = relativeRect.intersection(screenBounds)

    guard !clampedRect.isEmpty else {
      throw CaptureError.captureFailed("Selection area is outside display bounds")
    }

    // Capture full display at native pixel resolution (avoid sourceRect interpolation blur)
    config.width = Int(CGFloat(display.width) * scaleFactor)
    config.height = Int(CGFloat(display.height) * scaleFactor)

    let fullImage = try await captureImageCompat(
      contentFilter: filter,
      configuration: config
    )

    // Post-capture crop: pixel-perfect, no resampling
    let flippedY = screenFrame.height - clampedRect.origin.y - clampedRect.height
    let pixelCropRect = CGRect(
      x: ceil(clampedRect.origin.x * scaleFactor),
      y: ceil(flippedY * scaleFactor),
      width: ceil(clampedRect.width * scaleFactor),
      height: ceil(clampedRect.height * scaleFactor)
    )

    return fullImage.cropping(to: pixelCropRect)
  }

  // MARK: - Filter Builder

  private func loadShareableContent(
    prefetchedContentTask: ShareableContentPrefetchTask?,
    includeDesktopWindows: Bool = false
  ) async throws -> SCShareableContent {
    if includeDesktopWindows {
      // Desktop icon/widget exclusion requires desktop windows/apps to be present in the shareable content snapshot.
      return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    if let prefetchedContentTask {
      do {
        return try await prefetchedContentTask.value
      } catch {
        logger.debug("Prefetched shareable content failed; refetching current content")
      }
    }

    return try await SCShareableContent.current
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
      return
    }

    let identityHealth = AppIdentityManager.shared.health
    if !identityHealth.isHealthy {
      permissionStatus = .grantedButUnavailableDueToAppIdentity(identityHealth.summary)
      hasPermission = false
      return
    }

    permissionStatus = .granted
    hasPermission = true
  }

  /// Compatibility wrapper: uses SCScreenshotManager on macOS 14+, falls back to SCStream single-frame capture on macOS 13.
  private func captureImageCompat(
    contentFilter: SCContentFilter,
    configuration: SCStreamConfiguration
  ) async throws -> CGImage {
    if #available(macOS 14.0, *) {
      return try await SCScreenshotManager.captureImage(
        contentFilter: contentFilter,
        configuration: configuration
      )
    } else {
      // Fallback: use SCStream to capture a single frame
      return try await withCheckedThrowingContinuation { continuation in
        let handler = SingleFrameStreamOutput(continuation: continuation)
        let stream = SCStream(filter: contentFilter, configuration: configuration, delegate: nil)
        do {
          try stream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.trongduong.snapzy.screenshot"))
        } catch {
          continuation.resume(throwing: error)
          return
        }
        handler.stream = stream
        Task {
          do {
            try await stream.startCapture()
          } catch {
            continuation.resume(throwing: error)
          }
        }
      }
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

// MARK: - Single Frame Stream Output (macOS 13 fallback)

/// Helper class for capturing a single frame via SCStream (used on macOS 13 where SCScreenshotManager is unavailable)
private final class SingleFrameStreamOutput: NSObject, SCStreamOutput {
  private let continuation: CheckedContinuation<CGImage, Error>
  private var hasResumed = false
  var stream: SCStream?

  init(continuation: CheckedContinuation<CGImage, Error>) {
    self.continuation = continuation
  }

  func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .screen, !hasResumed else { return }

    // Check that the sample buffer contains a valid image
    guard let imageBuffer = sampleBuffer.imageBuffer else { return }

    // Check for valid frame status via attachments
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
       let statusRaw = attachments.first?[.status] as? Int,
       let status = SCFrameStatus(rawValue: statusRaw),
       status != .complete {
      return
    }

    hasResumed = true

    // Convert CVPixelBuffer to CGImage
    let ciImage = CIImage(cvPixelBuffer: imageBuffer)
    let context = CIContext()
    let rect = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(imageBuffer), height: CVPixelBufferGetHeight(imageBuffer))

    guard let cgImage = context.createCGImage(ciImage, from: rect) else {
      continuation.resume(throwing: CaptureError.captureFailed("Failed to create CGImage from stream frame"))
      stopStream()
      return
    }

    continuation.resume(returning: cgImage)
    stopStream()
  }

  private func stopStream() {
    Task {
      try? await stream?.stopCapture()
    }
  }
}
