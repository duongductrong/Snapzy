//
//  CLIRecordHandlers.swift
//  Snapzy
//
//  `record.screen|window|area|stop|status`: translate CLI params into a
//  `HeadlessRecordingService` request and its results back into wire models.
//  Recording logic lives in `HeadlessRecordingService`, not here.
//

import AppKit
import SnapzyCLIProtocol

nonisolated struct CLIRecordScreenHandler: CLIRequestHandling {
  func handle(_ params: RecordScreenParams, context: CLIRequestContext) async throws -> CLIRecordingInfo {
    try await CLIRecordBridge.recordScreen(params, caller: context.caller)
  }
}

nonisolated struct CLIRecordWindowHandler: CLIRequestHandling {
  func handle(_ params: RecordWindowParams, context: CLIRequestContext) async throws -> CLIRecordingInfo {
    try await CLIRecordBridge.recordWindow(params, caller: context.caller)
  }
}

nonisolated struct CLIRecordAreaHandler: CLIRequestHandling {
  func handle(_ params: RecordAreaParams, context: CLIRequestContext) async throws -> CLIRecordingInfo {
    try await CLIRecordBridge.recordArea(params, caller: context.caller)
  }
}

nonisolated struct CLIRecordStopHandler: CLIRequestHandling {
  func handle(_ params: RecordStopParams, context _: CLIRequestContext) async throws -> CLIRecordingResult {
    try await CLIRecordBridge.stop(params)
  }
}

nonisolated struct CLIRecordStatusHandler: CLIRequestHandling {
  func handle(_: CLIEmpty, context _: CLIRequestContext) async throws -> CLIRecordingStatus {
    await CLIRecordBridge.status()
  }
}

@MainActor
enum CLIRecordBridge {
  /// The starter's `--output`, by recording ID, until someone collects the file.
  private static var outputs: [String: CLIRecordingOutput] = [:]

  static func recordScreen(_ params: RecordScreenParams, caller: CLICallerIdentity?) async throws -> CLIRecordingInfo {
    let selection: HeadlessCaptureRequest.DisplaySelection = switch params.display {
    case .main: .main
    case .all: .all
    case .id(let displayID): .id(displayID)
    }
    return try await start(.screen(selection), options: params.options, output: params.output, caller: caller)
  }

  static func recordWindow(_ params: RecordWindowParams, caller: CLICallerIdentity?) async throws -> CLIRecordingInfo {
    let selection: HeadlessCaptureRequest.WindowSelection = switch params.window {
    case .id(let windowID): .id(windowID)
    case .app(let query): .app(query.app, titlePattern: query.titlePattern, index: query.index)
    case .active: .active
    }
    return try await start(.window(selection), options: params.options, output: params.output, caller: caller)
  }

  static func recordArea(_ params: RecordAreaParams, caller: CLICallerIdentity?) async throws -> CLIRecordingInfo {
    let rect = CLICoordinateSpace.appKitRect(
      fromTopLeft: params.rect,
      mainDisplayHeight: CLICoordinateSpace.mainDisplayHeight
    )
    return try await start(.area(rect), options: params.options, output: params.output, caller: caller)
  }

  static func stop(_ params: RecordStopParams) async throws -> CLIRecordingResult {
    let finished: HeadlessRecordingService.Finished
    do {
      finished = try await HeadlessRecordingService.shared.stop(id: params.id)
    } catch let error as HeadlessCaptureError {
      throw stopError(error)
    }
    return CLIRecordingResult(id: finished.id, file: cliFile(finished), output: outputs.removeValue(forKey: finished.id))
  }

  static func status() -> CLIRecordingStatus {
    let service = HeadlessRecordingService.shared
    return CLIRecordingStatus(
      recording: service.current.map { started in
        info(
          started,
          state: cliState(service.recorderState),
          elapsedSeconds: service.elapsedSeconds,
          output: outputs[started.id]
        )
      },
      interactiveRecordingActive: service.isInteractiveRecordingActive
    )
  }

  private static func start(
    _ target: HeadlessRecordingService.Request.Target,
    options: RecordingOptions,
    output: CLIRecordingOutput?,
    caller: CLICallerIdentity?
  ) async throws -> CLIRecordingInfo {
    let request = request(target, options: options)
    let service = HeadlessRecordingService.shared
    let started: HeadlessRecordingService.Started
    CLIActivityIndicator.shared.begin(caller: caller)
    do {
      started = try await service.start(request) {
        CLIActivityIndicator.shared.end()
      }
    } catch {
      CLIActivityIndicator.shared.end()
      if let error = error as? HeadlessCaptureError {
        throw startError(error, service: service)
      }
      throw error
    }
    if let output {
      outputs[started.id] = output
    }
    return info(started, state: .recording, elapsedSeconds: 0, output: output)
  }

  // MARK: - Mapping

  static func request(
    _ target: HeadlessRecordingService.Request.Target,
    options: RecordingOptions
  ) -> HeadlessRecordingService.Request {
    let quality: VideoQuality = switch options.quality {
    case .high: .high
    case .medium: .medium
    case .low: .low
    }
    return HeadlessRecordingService.Request(
      target: target,
      format: options.format == .mp4 ? .mp4 : .mov,
      quality: quality,
      fps: options.fps,
      showCursor: options.showCursor,
      systemAudio: options.systemAudio,
      microphone: options.microphone
    )
  }

  static func info(
    _ started: HeadlessRecordingService.Started,
    state: CLIRecordingState,
    elapsedSeconds: Int,
    output: CLIRecordingOutput?,
    mainDisplayHeight: CGFloat? = nil
  ) -> CLIRecordingInfo {
    let mainDisplayHeight = mainDisplayHeight ?? CLICoordinateSpace.mainDisplayHeight
    return CLIRecordingInfo(
      id: started.id,
      state: state,
      format: started.format == .mp4 ? .mp4 : .mov,
      rect: CLICoordinateSpace.topLeftRect(fromAppKit: started.rect, mainDisplayHeight: mainDisplayHeight),
      displayID: started.displayID,
      window: started.window.map { CLICaptureBridge.cliWindow($0, mainDisplayHeight: mainDisplayHeight) },
      matchedCandidates: started.window?.matchedCandidates,
      elapsedSeconds: elapsedSeconds,
      output: output
    )
  }

  static func cliState(_ state: RecordingState) -> CLIRecordingState {
    switch state {
    case .paused: .paused
    case .stopping: .stopping
    case .idle, .preparing, .recording: .recording
    }
  }

  static func cliFile(_ finished: HeadlessRecordingService.Finished) -> CLIRecordedFile {
    CLIRecordedFile(
      path: finished.url.path,
      format: finished.format == .mp4 ? .mp4 : .mov,
      width: finished.pixelWidth,
      height: finished.pixelHeight,
      durationSeconds: (finished.durationSeconds * 1000).rounded() / 1000,
      bytes: finished.byteCount
    )
  }

  static func startError(_ error: HeadlessCaptureError, service: HeadlessRecordingService) -> CLIError {
    guard error == .busy else { return CLICaptureBridge.cliError(error) }
    if service.isActive {
      return CLIError(.busy, "A snapzy recording is already in progress", hint: "Stop it with `snapzy record stop`")
    }
    return CLIError(
      .busy,
      "Snapzy is already recording",
      hint: "Stop the recording in Snapzy (menu bar → Stop Recording), then retry"
    )
  }

  static func stopError(_ error: HeadlessCaptureError) -> CLIError {
    switch error {
    case .targetNotFound(let message):
      CLIError(.targetNotFound, message, hint: "Start one with `snapzy record screen|window|area`")
    default:
      CLICaptureBridge.cliError(error)
    }
  }
}
