//
//  HeadlessCaptureService.swift
//  Snapzy
//
//  Captures a display, window or area with no user interaction: no overlay,
//  no permission prompt, no shutter sound, and no post-capture actions
//  (Quick Access, clipboard, history, presets). Files land in
//  `HeadlessCaptureStaging`; callers decide where they go next.
//

import AppKit

@MainActor
final class HeadlessCaptureService {
  static let shared = HeadlessCaptureService(captureManager: .shared)

  private let captureManager: ScreenCaptureManager
  private var isCapturing = false

  init(captureManager: ScreenCaptureManager) {
    self.captureManager = captureManager
  }

  func capture(_ request: HeadlessCaptureRequest) async throws -> HeadlessCaptureResult {
    // One headless capture at a time, and never on top of an interactive one.
    guard !isCapturing, !captureManager.isCapturing else { throw HeadlessCaptureError.busy }
    isCapturing = true
    defer { isCapturing = false }

    let start = Date()
    try await checkReadiness()
    do {
      try HeadlessCaptureStaging.prepare()
    } catch {
      throw HeadlessCaptureError.captureFailed("Could not create the capture folder: \(error.localizedDescription)")
    }

    let files: [HeadlessCaptureResult.File] = switch request.target {
    case .screen(let selection):
      try await captureScreens(selection, options: request.options)
    case .window(let selection):
      try await [captureWindow(selection, options: request.options)]
    case .area(let rect):
      try await [captureArea(rect, options: request.options)]
    }

    let durationMs = Int(Date().timeIntervalSince(start) * 1000)
    DiagnosticLogger.shared.log(
      .info,
      .capture,
      "Headless capture completed",
      context: ["files": "\(files.count)", "durationMs": "\(durationMs)"]
    )
    return HeadlessCaptureResult(files: files, durationMs: durationMs)
  }

  // MARK: - Targets

  private func captureScreens(
    _ selection: HeadlessCaptureRequest.DisplaySelection,
    options: HeadlessCaptureRequest.Options
  ) async throws -> [HeadlessCaptureResult.File] {
    let screens = NSScreen.screens
    let displayIDs = try CaptureTargetResolver.displays(
      selection,
      available: screens.compactMap(\.displayID),
      mainDisplayID: CGMainDisplayID()
    )

    // One display at a time so each file maps to its display ID. If any
    // display fails, nothing is returned, so don't leave the others staged.
    var files: [HeadlessCaptureResult.File] = []
    do {
      for displayID in displayIDs {
        let result = await captureManager.captureFullscreen(
          saveDirectory: HeadlessCaptureStaging.directory,
          fileName: HeadlessCaptureStaging.makeFileName(),
          displayID: displayID,
          format: options.format,
          showCursor: options.showCursor,
          excludeOwnApplication: true,
          invocation: invocation(options)
        )
        try await files.append(finish(
          result,
          options: options,
          displayID: displayID,
          displayScale: Self.backingScale(of: [displayID])
        ))
      }
    } catch {
      files.forEach { try? FileManager.default.removeItem(at: $0.url) }
      throw error
    }
    return files
  }

  private func captureWindow(
    _ selection: HeadlessCaptureRequest.WindowSelection,
    options: HeadlessCaptureRequest.Options
  ) async throws -> HeadlessCaptureResult.File {
    let window = try await resolveWindow(selection)
    let result = await captureManager.captureWindow(
      target: window.target,
      saveDirectory: HeadlessCaptureStaging.directory,
      fileName: HeadlessCaptureStaging.makeFileName(),
      format: options.format,
      showCursor: options.showCursor,
      excludeOwnApplication: true,
      invocation: invocation(options)
    )
    return try await finish(
      result,
      options: options,
      displayID: window.target.displayID,
      displayScale: Self.backingScale(of: [window.target.displayID]),
      window: window
    )
  }

  private func captureArea(
    _ rect: CGRect,
    options: HeadlessCaptureRequest.Options
  ) async throws -> HeadlessCaptureResult.File {
    try CaptureTargetResolver.validateArea(rect, screenFrames: NSScreen.screens.map(\.frame))
    let result = await captureManager.captureArea(
      rect: rect,
      saveDirectory: HeadlessCaptureStaging.directory,
      fileName: HeadlessCaptureStaging.makeFileName(),
      format: options.format,
      showCursor: options.showCursor,
      excludeOwnApplication: true,
      invocation: invocation(options)
    )
    let displayIDs = ScreenCaptureManager.displayIDsIntersecting(rect)
    return try await finish(
      result,
      options: options,
      displayID: displayIDs.count == 1 ? displayIDs.first : nil,
      // Multi-display composites are rendered at the highest scale involved.
      displayScale: Self.backingScale(of: displayIDs)
    )
  }

  private func resolveWindow(
    _ selection: HeadlessCaptureRequest.WindowSelection
  ) async throws -> HeadlessCaptureResult.CapturedWindow {
    if selection == .active {
      guard let target = await ActiveWindowResolver.resolveActiveWindowTarget() else {
        throw HeadlessCaptureError.targetNotFound("There is no active window to capture")
      }
      let ownerName = target.ownerPID.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName } ?? ""
      return HeadlessCaptureResult.CapturedWindow(
        target: target,
        ownerName: ownerName,
        isActive: true,
        matchedCandidates: nil
      )
    }

    guard
      let snapshot = await WindowSelectionQueryService.prepareSnapshot(
        prefetchedContentTask: nil,
        excludeOwnApplication: true
      )
    else {
      throw HeadlessCaptureError.captureFailed("Could not read the window list")
    }

    let resolved = try CaptureTargetResolver.window(selection, in: snapshot.orderedCandidates)
    let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let activeWindowID = snapshot.orderedCandidates.first { $0.target.ownerPID == frontmostPID }?.target.windowID
    return HeadlessCaptureResult.CapturedWindow(
      target: resolved.candidate.target,
      ownerName: resolved.candidate.ownerName,
      isActive: resolved.candidate.target.windowID == activeWindowID,
      matchedCandidates: resolved.matchedCandidates
    )
  }

  // MARK: - Helpers

  private func checkReadiness() async throws {
    guard OnboardingFlowView.hasCompletedOnboarding else { throw HeadlessCaptureError.onboardingIncomplete }
    guard !Self.isScreenLocked else { throw HeadlessCaptureError.screenLocked }

    await captureManager.checkPermission()
    switch captureManager.permissionStatus {
    case .granted where captureManager.requiresRelaunchToActivate:
      throw HeadlessCaptureError.permissionUnavailable(
        "Screen Recording was granted while Snapzy was running; relaunch Snapzy to use it"
      )
    case .granted:
      return
    case .notGranted:
      throw HeadlessCaptureError.permissionDenied
    case .grantedButUnavailableDueToAppIdentity(let reason):
      throw HeadlessCaptureError.permissionUnavailable(reason)
    }
  }

  private func invocation(_ options: HeadlessCaptureRequest.Options) -> CaptureInvocation {
    .headless(includeWindowShadow: options.includeWindowShadow)
  }

  private func finish(
    _ result: CaptureResult,
    options: HeadlessCaptureRequest.Options,
    displayID: CGDirectDisplayID?,
    displayScale: Double,
    window: HeadlessCaptureResult.CapturedWindow? = nil
  ) async throws -> HeadlessCaptureResult.File {
    let url: URL
    switch result {
    case .success(let savedURL):
      url = savedURL
    case .failure(.permissionDenied):
      throw HeadlessCaptureError.permissionDenied
    case .failure(.unavailable(let reason)):
      throw HeadlessCaptureError.permissionUnavailable(reason)
    case .failure(.noDisplayFound):
      throw HeadlessCaptureError.targetNotFound("The display is no longer available")
    case .failure(let error):
      throw HeadlessCaptureError.captureFailed(error.localizedDescription)
    }

    // Decoding and re-encoding a 5K capture takes long enough to stall the UI.
    let format = Self.postProcessorFormat(options.format)
    let maxDimension = options.maxDimension
    let info = try await Task.detached(priority: .userInitiated) {
      try HeadlessCapturePostProcessor.process(
        fileAt: url,
        format: format,
        maxDimension: maxDimension,
        displayScale: displayScale
      )
    }.value

    return HeadlessCaptureResult.File(
      url: url,
      pixelWidth: info.pixelWidth,
      pixelHeight: info.pixelHeight,
      scale: info.scale,
      byteCount: info.byteCount,
      displayID: displayID,
      window: window
    )
  }

  private static func backingScale(of displayIDs: some Collection<CGDirectDisplayID>) -> Double {
    let scales = NSScreen.screens
      .filter { screen in screen.displayID.map(displayIDs.contains) ?? false }
      .map(\.backingScaleFactor)
    return Double(scales.max() ?? NSScreen.main?.backingScaleFactor ?? 2)
  }

  /// A locked session (or asleep displays) leaves ScreenCaptureKit with no
  /// displays; say so instead of "display not found".
  nonisolated static var isScreenLocked: Bool {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    let isLocked = (session?["CGSSessionScreenIsLocked"] as? Bool) ?? false
    return isLocked || CGDisplayIsAsleep(CGMainDisplayID()) != 0
  }

  static func postProcessorFormat(_ format: ImageFormat) -> HeadlessCapturePostProcessor.Format {
    switch format {
    case .png: .png
    case .jpeg(let quality): .jpeg(quality: Double(quality))
    case .webp: .webp
    }
  }
}
