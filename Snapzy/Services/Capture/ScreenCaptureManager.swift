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

/// Result type for capture operations
enum CaptureResult {
  case success(URL)
  case failure(CaptureError)
}

/// Errors that can occur during capture
enum CaptureError: Error, LocalizedError {
  case permissionDenied
  case noDisplayFound
  case captureFailed(String)
  case saveFailed(String)
  case cancelled

  var errorDescription: String? {
    switch self {
    case .permissionDenied:
      return "Screen capture permission denied"
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

/// Manager class handling all screen capture operations
@MainActor
final class ScreenCaptureManager: ObservableObject {

  static let shared = ScreenCaptureManager()

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
    do {
      // Try to get shareable content - this will fail if permission not granted
      _ = try await SCShareableContent.current
      hasPermission = true
    } catch {
      hasPermission = false
    }
  }

  /// Request screen recording permission by triggering the system prompt
  func requestPermission() async -> Bool {
    // On macOS, we need to try to capture to trigger the permission dialog
    // The system will show a dialog asking for permission
    do {
      _ = try await SCShareableContent.current
      hasPermission = true
      return true
    } catch {
      hasPermission = false
      // Open System Preferences to the Screen Recording section
      openScreenRecordingPreferences()
      return false
    }
  }

  /// Open System Preferences to Screen Recording section
  func openScreenRecordingPreferences() {
    let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
    NSWorkspace.shared.open(url)
  }

  // MARK: - Capture Fullscreen

  /// Capture the entire screen and save to specified directory
  /// - Parameters:
  ///   - saveDirectory: Directory URL where the screenshot will be saved
  ///   - fileName: Optional custom filename (without extension). If nil, uses timestamp
  ///   - displayID: Optional specific display to capture. If nil, captures main display
  ///   - format: Image format for saving (default: PNG)
  /// - Returns: CaptureResult with the saved file URL or error
  func captureFullscreen(
    saveDirectory: URL,
    fileName: String? = nil,
    displayID: CGDirectDisplayID? = nil,
    format: ImageFormat = .png,
    excludeDesktopIcons: Bool = false,
    excludeDesktopWidgets: Bool = false
  ) async -> CaptureResult {

    if !hasPermission {
      let granted = await requestPermission()
      if !granted {
        return .failure(.permissionDenied)
      }
    }

    isCapturing = true
    defer { isCapturing = false }
    DiagnosticLogger.shared.log(.info, .capture, "Fullscreen capture started")

    do {
      let content = try await SCShareableContent.current

      // Get the target display
      let targetDisplayID = displayID ?? CGMainDisplayID()
      guard
        let display = content.displays.first(where: { $0.displayID == targetDisplayID })
          ?? content.displays.first
      else {
        return .failure(.noDisplayFound)
      }

      // Configure capture — exclude desktop icons/widgets if requested
      let filter = buildFilter(display: display, content: content, excludeDesktopIcons: excludeDesktopIcons, excludeDesktopWidgets: excludeDesktopWidgets)
      let config = SCStreamConfiguration()
      config.width = display.width * 2  // Retina resolution
      config.height = display.height * 2
      config.pixelFormat = kCVPixelFormatType_32BGRA
      config.showsCursor = true

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
  /// - Returns: CaptureResult with the saved file URL or error
  func captureArea(
    rect: CGRect,
    saveDirectory: URL,
    fileName: String? = nil,
    format: ImageFormat = .png,
    excludeDesktopIcons: Bool = false,
    excludeDesktopWidgets: Bool = false
  ) async -> CaptureResult {

    if !hasPermission {
      let granted = await requestPermission()
      if !granted {
        return .failure(.permissionDenied)
      }
    }

    isCapturing = true
    defer { isCapturing = false }
    DiagnosticLogger.shared.log(.info, .capture, "Area capture started \(Int(rect.width))x\(Int(rect.height))")

    do {
      let content = try await SCShareableContent.current

      // Get total screen height for coordinate conversion (Cocoa uses bottom-left, CG uses top-left)
      let totalScreenHeight = NSScreen.screens.map { $0.frame.maxY }.max() ?? 0
      let totalScreenMinY = NSScreen.screens.map { $0.frame.minY }.min() ?? 0

      // Convert input rect from Cocoa coordinates (bottom-left origin) to CG coordinates (top-left origin)
      let cgRect = CGRect(
        x: rect.origin.x,
        y: totalScreenHeight - rect.origin.y - rect.height,
        width: rect.width,
        height: rect.height
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
      let filter = buildFilter(display: display, content: content, excludeDesktopIcons: excludeDesktopIcons, excludeDesktopWidgets: excludeDesktopWidgets)
      let config = SCStreamConfiguration()
      config.pixelFormat = kCVPixelFormatType_32BGRA
      config.showsCursor = false

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

      // ScreenCaptureKit uses top-left origin for sourceRect
      // Convert from bottom-left (Cocoa) to top-left coordinate system
      let flippedY = screenFrame.height - clampedRect.origin.y - clampedRect.height
      let sourceRect = CGRect(
        x: clampedRect.origin.x,
        y: flippedY,
        width: clampedRect.width,
        height: clampedRect.height
      )
      config.sourceRect = sourceRect

      // Output dimensions in pixels (Retina resolution) - use clamped rect
      config.width = Int(ceil(clampedRect.width * scaleFactor))
      config.height = Int(ceil(clampedRect.height * scaleFactor))

      // Capture the image (compat: SCScreenshotManager requires macOS 14+)
      let image = try await captureImageCompat(
        contentFilter: filter,
        configuration: config
      )

      // Save the image
      return await saveImage(image, to: saveDirectory, fileName: fileName, format: format)

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

    // Generate filename on main actor (uses Date())
    let name = fileName ?? generateFileName()
    let fileURL = directory.appendingPathComponent("\(name).\(format.fileExtension)")

    logger.info("Saving capture to \(directory.lastPathComponent)/\(name).\(format.fileExtension)")

    // Capture format properties before entering detached task
    let utType = format.utType

    // Move file I/O to background thread to avoid blocking main thread
    let writeResult: Result<URL, CaptureError> = await Task.detached {
      // Create directory if needed
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      } catch {
        return .failure(.saveFailed("Could not create directory: \(error.localizedDescription)"))
      }

      // Create image destination
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

      // Add image and write
      CGImageDestinationAddImage(destination, image, nil)

      guard CGImageDestinationFinalize(destination) else {
        return .failure(.saveFailed("Failed to write image to disk"))
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

  /// Verify file exists on disk with non-zero size, retrying up to maxAttempts.
  /// Runs on caller's thread (designed for background execution).
  private nonisolated static func verifyFileWritten(at url: URL, maxAttempts: Int = 3, delayMs: UInt64 = 50) async -> Bool {
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

  /// Generate a timestamp-based filename
  private func generateFileName() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
    return "Snapzy_\(formatter.string(from: Date()))"
  }

  // MARK: - Utility

  /// Get list of available displays
  func getAvailableDisplays() async -> [SCDisplay] {
    do {
      let content = try await SCShareableContent.current
      return content.displays
    } catch {
      return []
    }
  }

  /// Capture a specific area and return as CGImage (for OCR)
  func captureAreaAsImage(rect: CGRect, excludeDesktopIcons: Bool = false, excludeDesktopWidgets: Bool = false) async throws -> CGImage? {
    if !hasPermission {
      let granted = await requestPermission()
      if !granted {
        throw CaptureError.permissionDenied
      }
    }

    let content = try await SCShareableContent.current

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

    let filter = buildFilter(display: display, content: content, excludeDesktopIcons: excludeDesktopIcons, excludeDesktopWidgets: excludeDesktopWidgets)
    let config = SCStreamConfiguration()
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

    let flippedY = screenFrame.height - clampedRect.origin.y - clampedRect.height
    let sourceRect = CGRect(
      x: clampedRect.origin.x,
      y: flippedY,
      width: clampedRect.width,
      height: clampedRect.height
    )
    config.sourceRect = sourceRect
    config.width = Int(ceil(clampedRect.width * scaleFactor))
    config.height = Int(ceil(clampedRect.height * scaleFactor))

    return try await captureImageCompat(
      contentFilter: filter,
      configuration: config
    )
  }

  // MARK: - Filter Builder

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
          try stream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.snapzy.screenshot"))
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
    excludeDesktopWidgets: Bool
  ) -> SCContentFilter {
    let iconManager = DesktopIconManager.shared
    var excludedApps: [SCRunningApplication] = []
    var exceptedWindows: [SCWindow] = []

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
  case tiff

  var fileExtension: String {
    switch self {
    case .png: return "png"
    case .jpeg: return "jpg"
    case .tiff: return "tiff"
    }
  }

  var utType: CFString {
    switch self {
    case .png: return "public.png" as CFString
    case .jpeg: return "public.jpeg" as CFString
    case .tiff: return "public.tiff" as CFString
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
