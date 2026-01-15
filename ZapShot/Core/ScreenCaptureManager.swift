//
//  ScreenCaptureManager.swift
//  ZapShot
//
//  Core manager for screen capture functionality
//

import Foundation
import ScreenCaptureKit
import AppKit
import CoreGraphics
import Combine

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
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
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
    format: ImageFormat = .png
  ) async -> CaptureResult {
    
    if !hasPermission {
      let granted = await requestPermission()
      if !granted {
        return .failure(.permissionDenied)
      }
    }
    
    isCapturing = true
    defer { isCapturing = false }
    
    do {
      let content = try await SCShareableContent.current
      
      // Get the target display
      let targetDisplayID = displayID ?? CGMainDisplayID()
      guard let display = content.displays.first(where: { $0.displayID == targetDisplayID })
              ?? content.displays.first else {
        return .failure(.noDisplayFound)
      }
      
      // Configure capture
      let filter = SCContentFilter(display: display, excludingWindows: [])
      let config = SCStreamConfiguration()
      config.width = display.width * 2  // Retina resolution
      config.height = display.height * 2
      config.pixelFormat = kCVPixelFormatType_32BGRA
      config.showsCursor = true
      
      // Capture the image
      let image = try await SCScreenshotManager.captureImage(
        contentFilter: filter,
        configuration: config
      )
      
      // Save the image
      return saveImage(image, to: saveDirectory, fileName: fileName, format: format)
      
    } catch {
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
    format: ImageFormat = .png
  ) async -> CaptureResult {
    
    if !hasPermission {
      let granted = await requestPermission()
      if !granted {
        return .failure(.permissionDenied)
      }
    }
    
    isCapturing = true
    defer { isCapturing = false }
    
    do {
      let content = try await SCShareableContent.current
      
      // Find the display containing the rect using actual display frames
      guard let display = content.displays.first(where: { display in
        let displayFrame = CGRect(
          x: CGFloat(display.frame.origin.x),
          y: CGFloat(display.frame.origin.y),
          width: CGFloat(display.width),
          height: CGFloat(display.height)
        )
        return displayFrame.intersects(rect)
      }) ?? content.displays.first else {
        return .failure(.noDisplayFound)
      }
      
      // Configure capture for the full display first
      let filter = SCContentFilter(display: display, excludingWindows: [])
      let config = SCStreamConfiguration()
      config.pixelFormat = kCVPixelFormatType_32BGRA
      config.showsCursor = false
      
      // Get the display's backing scale factor (2.0 for Retina displays)
      let scaleFactor: CGFloat
      if let screen = NSScreen.screens.first(where: {
        Int($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0) == display.displayID
      }) {
        scaleFactor = screen.backingScaleFactor
      } else {
        // Fallback: calculate from display dimensions
        scaleFactor = display.frame.width > 0 ? CGFloat(display.width) / display.frame.width : 2.0
      }
      
      // Convert rect from global screen coordinates to display-relative coordinates
      let displayFrame = display.frame
      let displayOrigin = displayFrame.origin
      
      // Calculate relative rect in points (display-local coordinates)
      let relativeRect = CGRect(
        x: rect.origin.x - displayOrigin.x,
        y: rect.origin.y - displayOrigin.y,
        width: rect.width,
        height: rect.height
      )
      
      // ScreenCaptureKit uses top-left origin for sourceRect
      // Convert from bottom-left (macOS) to top-left coordinate system
      let flippedY = displayFrame.height - relativeRect.origin.y - relativeRect.height
      let sourceRect = CGRect(
        x: relativeRect.origin.x,
        y: flippedY,
        width: relativeRect.width,
        height: relativeRect.height
      )
      
      config.sourceRect = sourceRect
      
      // Output dimensions in pixels (Retina resolution)
      config.width = Int(ceil(rect.width * scaleFactor))
      config.height = Int(ceil(rect.height * scaleFactor))
      
      // Capture the image
      let image = try await SCScreenshotManager.captureImage(
        contentFilter: filter,
        configuration: config
      )
      
      // Save the image
      return saveImage(image, to: saveDirectory, fileName: fileName, format: format)
      
    } catch {
      return .failure(.captureFailed(error.localizedDescription))
    }
  }
  
  // MARK: - Image Saving
  
  /// Save a CGImage to disk
  private func saveImage(
    _ image: CGImage,
    to directory: URL,
    fileName: String?,
    format: ImageFormat
  ) -> CaptureResult {
    
    // Create directory if needed
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      return .failure(.saveFailed("Could not create directory: \(error.localizedDescription)"))
    }
    
    // Generate filename
    let name = fileName ?? generateFileName()
    let fileURL = directory.appendingPathComponent("\(name).\(format.fileExtension)")
    
    // Create image destination
    guard let destination = CGImageDestinationCreateWithURL(
      fileURL as CFURL,
      format.utType,
      1,
      nil
    ) else {
      return .failure(.saveFailed("Could not create image destination"))
    }
    
    // Add image and write
    CGImageDestinationAddImage(destination, image, nil)
    
    if CGImageDestinationFinalize(destination) {
      return .success(fileURL)
    } else {
      return .failure(.saveFailed("Failed to write image to disk"))
    }
  }
  
  /// Generate a timestamp-based filename
  private func generateFileName() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    return "ZapShot_\(formatter.string(from: Date()))"
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
