//
//  HeadlessRecordingService.swift
//  Snapzy
//
//  Records a display, window or area with no user interaction: no toolbar,
//  region overlay, camera, permission prompt, sound or post-capture actions
//  (Quick Access, clipboard, history, GIF, Studio flatten). The video lands in
//  `HeadlessCaptureStaging`; callers decide where it goes next.
//
//  One recording at a time, sharing `ScreenRecordingManager` with the
//  interactive flow. It can end three ways: `stop(id:)` (the caller gets the
//  file), or the menu bar / recording shortcut / a stream failure through
//  `stopFromUser()` (the file waits, unclaimed, for the next `stop(id:)`).
//

import AppKit
import AVFoundation

@MainActor
final class HeadlessRecordingService {
  static let shared = HeadlessRecordingService(recorder: .shared)

  struct Request {
    enum Target: Equatable {
      /// `.all` is rejected: one stream records one display.
      case screen(HeadlessCaptureRequest.DisplaySelection)
      case window(HeadlessCaptureRequest.WindowSelection)
      /// AppKit global coordinates (bottom-left origin).
      case area(CGRect)
    }

    let target: Target
    var format: VideoFormat = .mov
    var quality: VideoQuality = .high
    var fps = 30
    var showCursor = true
    var systemAudio = false
    var microphone = false
  }

  struct Started {
    /// Also the staging file's base name.
    let id: String
    /// Region being recorded, AppKit global coordinates, clamped to the recorded display.
    let rect: CGRect
    let displayID: CGDirectDisplayID?
    let window: HeadlessCaptureResult.CapturedWindow?
    let format: VideoFormat
  }

  struct Finished: Equatable {
    let id: String
    let url: URL
    let format: VideoFormat
    let pixelWidth: Int
    let pixelHeight: Int
    let durationSeconds: Double
    let byteCount: Int
  }

  private struct Active {
    let started: Started
    let onEnd: @MainActor () -> Void
  }

  private let recorder: ScreenRecordingManager
  private var isStarting = false
  /// Stop was pressed in Snapzy while the recording was still starting.
  private var stopRequestedWhileStarting = false
  private var active: Active?
  private var stopTask: Task<Finished?, Never>?
  /// Finished recordings nobody has collected yet, newest last.
  private var unclaimed: [Finished] = []

  init(recorder: ScreenRecordingManager) {
    self.recorder = recorder
  }

  /// A `snapzy` recording is starting, running, or stopping.
  var isActive: Bool {
    isStarting || active != nil
  }

  var current: Started? {
    active?.started
  }

  var recorderState: RecordingState {
    recorder.state
  }

  var elapsedSeconds: Int {
    recorder.elapsedSeconds
  }

  /// A recording that Snapzy's own UI started (or is about to start) is running.
  var isInteractiveRecordingActive: Bool {
    !isActive && (recorder.isActive || RecordingCoordinator.shared.isActive)
  }

  // MARK: - Start

  /// `onEnd` runs once when the recording stops, however it stops.
  func start(_ request: Request, onEnd: @escaping @MainActor () -> Void = {}) async throws -> Started {
    guard !isActive, !recorder.isActive, !RecordingCoordinator.shared.isActive else {
      throw HeadlessCaptureError.busy
    }
    isStarting = true
    stopRequestedWhileStarting = false
    defer { isStarting = false }

    try Self.validate(request)
    try await HeadlessCaptureService.shared.checkReadiness()
    if request.microphone, AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
      throw HeadlessCaptureError.permissionUnavailable(
        "Snapzy does not have Microphone access; record once with the microphone from Snapzy to grant it"
      )
    }
    do {
      try HeadlessCaptureStaging.prepare()
    } catch {
      throw HeadlessCaptureError.captureFailed("Could not create the capture folder: \(error.localizedDescription)")
    }

    let target = try await resolve(request.target)
    let id = HeadlessCaptureStaging.makeFileName()
    do {
      try await recorder.prepareRecording(
        rect: target.rect,
        windowTarget: target.window?.target,
        format: request.format,
        quality: request.quality,
        fps: request.fps,
        maxResolution: .auto,
        captureSystemAudio: request.systemAudio,
        captureMicrophone: request.microphone,
        showCursor: request.showCursor,
        studioRecording: false,
        saveDirectory: HeadlessCaptureStaging.directory,
        fileName: id,
        excludeOwnApplication: true
      )
      try await recorder.startRecording()
    } catch let error as RecordingError {
      // prepareRecording leaves the recorder `.preparing` only when it succeeded.
      if recorder.state == .preparing { await recorder.cancelRecording() }
      throw Self.captureError(error)
    }

    let started = Started(
      id: id,
      rect: target.rect,
      displayID: target.displayID,
      window: target.window,
      format: request.format
    )
    active = Active(started: started, onEnd: onEnd)
    if stopRequestedWhileStarting {
      stopFromUser()
    }
    DiagnosticLogger.shared.log(.info, .recording, "Headless recording started", context: [
      "id": id,
      "rect": "\(Int(target.rect.width))x\(Int(target.rect.height))",
      "fps": "\(request.fps)",
      "format": request.format.rawValue,
    ])
    return started
  }

  static func validate(_ request: Request) throws {
    guard RecordingOptionsLimits.frameRates.contains(request.fps) else {
      throw HeadlessCaptureError.invalidRequest(
        "fps must be one of \(RecordingOptionsLimits.frameRates.map(String.init).joined(separator: ", "))"
      )
    }
    if case .screen(.all) = request.target {
      throw HeadlessCaptureError.invalidRequest("A recording covers one display; pass main or a display ID")
    }
  }

  private struct ResolvedTarget {
    let rect: CGRect
    let displayID: CGDirectDisplayID?
    let window: HeadlessCaptureResult.CapturedWindow?
  }

  private func resolve(_ target: Request.Target) async throws -> ResolvedTarget {
    let screens = NSScreen.screens
    switch target {
    case .screen(let selection):
      let displayIDs = try CaptureTargetResolver.displays(
        selection,
        available: screens.compactMap(\.displayID),
        mainDisplayID: CGMainDisplayID()
      )
      guard let displayID = displayIDs.first, let screen = screens.first(where: { $0.displayID == displayID }) else {
        throw HeadlessCaptureError.targetNotFound("The display is no longer available")
      }
      return ResolvedTarget(rect: screen.frame, displayID: displayID, window: nil)
    case .window(let selection):
      let window = try await HeadlessCaptureService.shared.resolveWindow(selection)
      let rect = Self.clampToBestDisplay(window.target.frame, screenFrames: screens.map(\.frame))
      return ResolvedTarget(rect: rect, displayID: window.target.displayID, window: window)
    case .area(let rect):
      try CaptureTargetResolver.validateArea(rect, screenFrames: screens.map(\.frame))
      let clamped = Self.clampToBestDisplay(rect, screenFrames: screens.map(\.frame))
      let displayID = screens.first { $0.frame.intersects(clamped) && $0.frame.contains(clamped) }?.displayID
      return ResolvedTarget(rect: clamped, displayID: displayID, window: nil)
    }
  }

  /// ScreenCaptureKit records a single display: the one overlapping `rect` the most
  /// (the rule `ScreenRecordingManager` applies), so report the part on it.
  nonisolated static func clampToBestDisplay(_ rect: CGRect, screenFrames: [CGRect]) -> CGRect {
    let best = screenFrames
      .map { (frame: $0, overlap: $0.intersection(rect)) }
      .filter { !$0.overlap.isNull }
      .max { $0.overlap.width * $0.overlap.height < $1.overlap.width * $1.overlap.height }
    return best?.overlap ?? rect
  }

  // MARK: - Stop

  /// Stops the current recording (or collects a finished one) and hands its file out.
  /// Each finished recording is handed out once.
  func stop(id: String?) async throws -> Finished {
    if let current = active?.started, id == nil || id == current.id {
      guard await finishActive() != nil else {
        throw HeadlessCaptureError.captureFailed("The recording stopped without producing a file")
      }
      return try claim(current.id)
    }
    if let id {
      return try claim(id)
    }
    guard let latest = unclaimed.popLast() else {
      throw HeadlessCaptureError.targetNotFound("No snapzy recording is in progress")
    }
    return latest
  }

  /// Menu bar Stop, the recording shortcut, or ScreenCaptureKit ending the stream.
  /// The file waits for the next `stop(id:)`.
  func stopFromUser() {
    if isStarting, active == nil {
      stopRequestedWhileStarting = true
      return
    }
    guard active != nil else { return }
    DiagnosticLogger.shared.log(.info, .recording, "Headless recording stop requested from Snapzy")
    Task { _ = await finishActive() }
  }

  private func claim(_ id: String) throws -> Finished {
    guard let index = unclaimed.firstIndex(where: { $0.id == id }) else {
      throw HeadlessCaptureError.targetNotFound(
        "Recording \(id) is not in progress and its file was already collected"
      )
    }
    return unclaimed.remove(at: index)
  }

  /// Concurrent stops share one `stopRecording()`. The bookkeeping runs inside the
  /// shared task, so the file is in `unclaimed` before any waiter resumes.
  private func finishActive() async -> Finished? {
    if let stopTask { return await stopTask.value }
    guard let active else { return nil }

    let task = Task { @MainActor [weak self, recorder] () -> Finished? in
      let url = await recorder.stopRecording()
      var finished: Finished?
      if let url {
        // The file leaves Snapzy: drop the editor metadata (mouse samples, audio sidecar).
        try? RecordingMetadataStore.delete(for: url)
        finished = await Self.describe(url, id: active.started.id, format: active.started.format)
      }
      if let self {
        self.active = nil
        stopTask = nil
        if let finished {
          unclaimed.append(finished)
        }
      }
      active.onEnd()
      DiagnosticLogger.shared.log(.info, .recording, "Headless recording finished", context: [
        "id": active.started.id,
        "hasFile": "\(finished != nil)",
      ])
      return finished
    }
    stopTask = task
    return await task.value
  }

  private static func describe(_ url: URL, id: String, format: VideoFormat) async -> Finished {
    let asset = AVURLAsset(url: url)
    let duration = await (try? asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
    var size = CGSize.zero
    if let track = try? await asset.loadTracks(withMediaType: .video).first,
       let naturalSize = try? await track.load(.naturalSize) {
      size = naturalSize
    }
    let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    return Finished(
      id: id,
      url: url,
      format: format,
      pixelWidth: Int(size.width.rounded()),
      pixelHeight: Int(size.height.rounded()),
      durationSeconds: duration.isFinite ? duration : 0,
      byteCount: bytes
    )
  }

  static func captureError(_ error: RecordingError) -> HeadlessCaptureError {
    switch error {
    case .permissionDenied:
      .permissionDenied
    case .microphonePermissionDenied:
      .permissionUnavailable("Snapzy does not have Microphone access")
    case .cameraPermissionDenied:
      .permissionUnavailable("Snapzy does not have Camera access")
    case .noDisplayFound:
      .targetNotFound("The display is no longer available")
    case .alreadyActive:
      .busy
    case .setupFailed(let message), .writeFailed(let message):
      .captureFailed(message)
    case .cancelled:
      .captureFailed("The recording was cancelled")
    }
  }
}

enum RecordingOptionsLimits {
  /// The frame rates Settings offers.
  static let frameRates = [30, 60]
}
