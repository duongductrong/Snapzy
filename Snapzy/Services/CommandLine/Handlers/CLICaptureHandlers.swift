//
//  CLICaptureHandlers.swift
//  Snapzy
//
//  `capture.screen`, `capture.window`, `capture.area`: translate CLI params
//  into a `HeadlessCaptureRequest` and the result back into wire models.
//  Capture logic lives in `HeadlessCaptureService`, not here.
//

import AppKit
import SnapzyCLIProtocol

nonisolated struct CLICaptureScreenHandler: CLIRequestHandling {
  func handle(_ params: CaptureScreenParams, context: CLIRequestContext) async throws -> CLICaptureResult {
    try await CLICaptureBridge.captureScreen(params, caller: context.caller)
  }
}

nonisolated struct CLICaptureWindowHandler: CLIRequestHandling {
  func handle(_ params: CaptureWindowParams, context: CLIRequestContext) async throws -> CLICaptureResult {
    try await CLICaptureBridge.captureWindow(params, caller: context.caller)
  }
}

nonisolated struct CLICaptureAreaHandler: CLIRequestHandling {
  func handle(_ params: CaptureAreaParams, context: CLIRequestContext) async throws -> CLICaptureResult {
    try await CLICaptureBridge.captureArea(params, caller: context.caller)
  }
}

@MainActor
enum CLICaptureBridge {
  static func captureScreen(_ params: CaptureScreenParams,
                            caller: CLICallerIdentity?) async throws -> CLICaptureResult {
    let selection: HeadlessCaptureRequest.DisplaySelection = switch params.display {
    case .main: .main
    case .all: .all
    case .id(let displayID): .id(displayID)
    }
    return try await capture(.screen(selection), options: params.options, caller: caller)
  }

  static func captureWindow(_ params: CaptureWindowParams,
                            caller: CLICallerIdentity?) async throws -> CLICaptureResult {
    let selection: HeadlessCaptureRequest.WindowSelection = switch params.window {
    case .id(let windowID): .id(windowID)
    case .app(let query): .app(query.app, titlePattern: query.titlePattern, index: query.index)
    case .active: .active
    }
    return try await capture(.window(selection), options: params.options, caller: caller)
  }

  static func captureArea(_ params: CaptureAreaParams, caller: CLICallerIdentity?) async throws -> CLICaptureResult {
    let rect = CLICoordinateSpace.appKitRect(
      fromTopLeft: params.rect,
      mainDisplayHeight: CLICoordinateSpace.mainDisplayHeight
    )
    return try await capture(.area(rect), options: params.options, caller: caller)
  }

  private static func capture(
    _ target: HeadlessCaptureRequest.Target,
    options: CaptureOptions,
    caller: CLICallerIdentity?
  ) async throws -> CLICaptureResult {
    let request = try HeadlessCaptureRequest(target: target, options: headlessOptions(options))
    CLIActivityIndicator.shared.begin(caller: caller)
    defer { CLIActivityIndicator.shared.end() }
    do {
      let result = try await HeadlessCaptureService.shared.capture(request)
      return cliResult(result, format: options.format, mainDisplayHeight: CLICoordinateSpace.mainDisplayHeight)
    } catch let error as HeadlessCaptureError {
      throw cliError(error)
    }
  }

  // MARK: - Mapping

  static func headlessOptions(_ options: CaptureOptions) throws -> HeadlessCaptureRequest.Options {
    if let quality = options.quality, !(0 ... 1).contains(quality) {
      throw CLIError(.invalidArguments, "quality must be between 0 and 1")
    }
    if let maxDimension = options.maxDimension, maxDimension <= 0 {
      throw CLIError(.invalidArguments, "maxDimension must be greater than 0")
    }

    let format: ImageFormat = switch options.format {
    case .png: .png
    case .jpeg: .jpeg(quality: CGFloat(options.quality ?? 0.9))
    case .webp: .webp
    }
    return HeadlessCaptureRequest.Options(
      format: format,
      maxDimension: options.maxDimension,
      showCursor: options.showCursor,
      includeWindowShadow: options.windowShadow
    )
  }

  static func cliResult(
    _ result: HeadlessCaptureResult,
    format: CLIImageFormat,
    mainDisplayHeight: CGFloat
  ) -> CLICaptureResult {
    let files = result.files.map { file in
      CLICapturedFile(
        path: file.url.path,
        format: format,
        width: file.pixelWidth,
        height: file.pixelHeight,
        scale: file.scale,
        bytes: file.byteCount,
        displayID: file.displayID,
        window: file.window.map { cliWindow($0, mainDisplayHeight: mainDisplayHeight) },
        matchedCandidates: file.window?.matchedCandidates
      )
    }
    return CLICaptureResult(files: files, durationMs: result.durationMs)
  }

  private static func cliWindow(
    _ window: HeadlessCaptureResult.CapturedWindow,
    mainDisplayHeight: CGFloat
  ) -> CLIWindow {
    CLIWindow(
      id: window.target.windowID,
      title: window.target.title,
      app: CLIWindowOwner(
        name: window.ownerName,
        bundleID: window.target.bundleIdentifier,
        pid: window.target.ownerPID ?? 0
      ),
      frame: CLICoordinateSpace.topLeftRect(fromAppKit: window.target.frame, mainDisplayHeight: mainDisplayHeight),
      displayID: window.target.displayID,
      isOnScreen: true,
      isActive: window.isActive
    )
  }

  static func cliError(_ error: HeadlessCaptureError) -> CLIError {
    switch error {
    case .permissionDenied:
      CLIWindowSource.permissionError
    case .permissionUnavailable(let reason):
      CLIError(.permissionDenied, reason, hint: "Check Snapzy → Settings → Permissions, then retry")
    case .onboardingIncomplete:
      CLIError(.onboardingIncomplete, "Snapzy setup is not finished", hint: "Open Snapzy and finish onboarding")
    case .targetNotFound(let message):
      CLIError(.targetNotFound, message)
    case .invalidRequest(let message):
      CLIError(.invalidArguments, message)
    case .screenLocked:
      CLIError(.appUnavailable, "The screen is locked or asleep", hint: "Unlock the Mac, then retry")
    case .busy:
      CLIError(.busy, "Another capture is in progress", hint: "Retry in a moment")
    case .captureFailed(let message):
      CLIError(.internal, message)
    }
  }
}
