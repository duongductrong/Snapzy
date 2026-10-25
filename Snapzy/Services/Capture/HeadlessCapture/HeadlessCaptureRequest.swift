//
//  HeadlessCaptureRequest.swift
//  Snapzy
//
//  Inputs and outputs of a capture with no user interaction. Independent of
//  the CLI wire format so other callers (MCP, App Intents) can reuse it.
//

import AppKit

struct HeadlessCaptureRequest {
  enum DisplaySelection: Equatable {
    case main
    case all
    case id(CGDirectDisplayID)
  }

  enum WindowSelection: Equatable {
    case id(CGWindowID)
    /// Name or bundle ID, see `AppNameMatcher`. `index` is 0-based, front to back.
    case app(String, titlePattern: String?, index: Int?)
    case active
  }

  enum Target: Equatable {
    case screen(DisplaySelection)
    case window(WindowSelection)
    /// AppKit global coordinates (bottom-left origin).
    case area(CGRect)
  }

  struct Options {
    var format: ImageFormat = .png
    /// Longest edge in pixels; never upscales.
    var maxDimension: Int?
    var showCursor = false
    var includeWindowShadow = true
  }

  let target: Target
  var options = Options()
}

struct HeadlessCaptureResult {
  struct File {
    let url: URL
    let pixelWidth: Int
    let pixelHeight: Int
    /// Pixels per point of the written file.
    let scale: Double
    let byteCount: Int
    let displayID: CGDirectDisplayID?
    let window: CapturedWindow?
  }

  struct CapturedWindow {
    let target: WindowCaptureTarget
    let ownerName: String
    let isActive: Bool
    /// How many windows matched an app selector.
    let matchedCandidates: Int?
  }

  let files: [File]
  let durationMs: Int
}

enum HeadlessCaptureError: Error, Equatable {
  case permissionDenied
  /// Granted in System Settings but not usable yet (needs a relaunch, or the
  /// app identity changed). The reason is shown to the caller.
  case permissionUnavailable(String)
  case onboardingIncomplete
  /// The session is locked or the displays are asleep; ScreenCaptureKit sees no displays.
  case screenLocked
  case targetNotFound(String)
  case invalidRequest(String)
  case busy
  case captureFailed(String)
}
