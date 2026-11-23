//
//  RecordingModels.swift
//  SnapzyCLIProtocol
//
//  Params and results for `record.*`. Like captures, the app writes the video
//  into its staging folder and the CLI moves it to `--output`. A recording can
//  be stopped by a different `snapzy` process than the one that started it, so
//  the app keeps the starter's `--output` and hands it back with the file.
//

import Foundation

public enum CLIVideoFormat: String, Codable, Sendable, CaseIterable {
  case mov
  case mp4

  public init?(fileExtension: String) {
    self.init(rawValue: fileExtension.lowercased())
  }

  public var fileExtension: String { rawValue }
}

public enum CLIVideoQuality: String, Codable, Sendable, CaseIterable {
  case high
  case medium
  case low
}

public struct RecordingOptions: Codable, Sendable, Equatable {
  public static let supportedFrameRates = [30, 60]

  public let format: CLIVideoFormat
  public let quality: CLIVideoQuality
  public let fps: Int
  public let showCursor: Bool
  /// Audio the Mac plays (ScreenCaptureKit), not the microphone.
  public let systemAudio: Bool
  /// The system default input. Needs Microphone access already granted to Snapzy.
  public let microphone: Bool

  public init(
    format: CLIVideoFormat = .mov,
    quality: CLIVideoQuality = .high,
    fps: Int = 30,
    showCursor: Bool = true,
    systemAudio: Bool = false,
    microphone: Bool = false
  ) {
    self.format = format
    self.quality = quality
    self.fps = fps
    self.showCursor = showCursor
    self.systemAudio = systemAudio
    self.microphone = microphone
  }
}

/// Where the CLI should put the finished video. The app never writes there; it
/// only stores the value and returns it with the result so any `snapzy record stop`
/// delivers the file where the starter asked.
public struct CLIRecordingOutput: Codable, Sendable, Equatable {
  /// Absolute path. A trailing `/` means a directory (the staging file name is kept).
  public let path: String
  /// Overwrite an existing file at `path`.
  public let force: Bool

  public init(path: String, force: Bool = false) {
    self.path = path
    self.force = force
  }
}

public struct RecordScreenParams: Codable, Sendable, Equatable {
  /// `main` or a display ID; `all` is rejected (one stream records one display).
  public let display: DisplaySelector
  public let options: RecordingOptions
  public let output: CLIRecordingOutput?

  public init(display: DisplaySelector = .main, options: RecordingOptions = RecordingOptions(),
              output: CLIRecordingOutput? = nil) {
    self.display = display
    self.options = options
    self.output = output
  }
}

public struct RecordWindowParams: Codable, Sendable, Equatable {
  public let window: WindowSelector
  public let options: RecordingOptions
  public let output: CLIRecordingOutput?

  public init(window: WindowSelector, options: RecordingOptions = RecordingOptions(),
              output: CLIRecordingOutput? = nil) {
    self.window = window
    self.options = options
    self.output = output
  }
}

public struct RecordAreaParams: Codable, Sendable, Equatable {
  public let rect: CLIRect
  public let options: RecordingOptions
  public let output: CLIRecordingOutput?

  public init(rect: CLIRect, options: RecordingOptions = RecordingOptions(), output: CLIRecordingOutput? = nil) {
    self.rect = rect
    self.options = options
    self.output = output
  }
}

public struct RecordStopParams: Codable, Sendable, Equatable {
  /// The recording to stop or collect; `nil` means the current one.
  public let id: String?

  public init(id: String? = nil) {
    self.id = id
  }
}

public enum CLIRecordingState: String, Codable, Sendable {
  case recording
  case paused
  case stopping

  /// A newer app may add states; read them as `recording`.
  public init(from decoder: Decoder) throws {
    let rawValue = try decoder.singleValueContainer().decode(String.self)
    self = CLIRecordingState(rawValue: rawValue) ?? .recording
  }
}

/// A recording started by `snapzy`. `record.screen|window|area` return it at start.
public struct CLIRecordingInfo: Codable, Sendable, Equatable {
  public let id: String
  public let state: CLIRecordingState
  public let format: CLIVideoFormat
  /// The recorded region in global top-left points (clamped to one display).
  public let rect: CLIRect
  public let displayID: UInt32?
  public let window: CLIWindow?
  public let matchedCandidates: Int?
  /// Wall clock minus pauses.
  public let elapsedSeconds: Int
  public let output: CLIRecordingOutput?

  public init(
    id: String,
    state: CLIRecordingState,
    format: CLIVideoFormat,
    rect: CLIRect,
    displayID: UInt32? = nil,
    window: CLIWindow? = nil,
    matchedCandidates: Int? = nil,
    elapsedSeconds: Int = 0,
    output: CLIRecordingOutput? = nil
  ) {
    self.id = id
    self.state = state
    self.format = format
    self.rect = rect
    self.displayID = displayID
    self.window = window
    self.matchedCandidates = matchedCandidates
    self.elapsedSeconds = elapsedSeconds
    self.output = output
  }
}

public struct CLIRecordingStatus: Codable, Sendable, Equatable {
  /// The recording `snapzy` started, if one is running.
  public let recording: CLIRecordingInfo?
  /// A recording started from Snapzy itself (toolbar, shortcut, menu bar) is running;
  /// `snapzy record` cannot start or stop it.
  public let interactiveRecordingActive: Bool

  public init(recording: CLIRecordingInfo?, interactiveRecordingActive: Bool = false) {
    self.recording = recording
    self.interactiveRecordingActive = interactiveRecordingActive
  }
}

public struct CLIRecordedFile: Codable, Sendable, Equatable {
  public var path: String
  public let format: CLIVideoFormat
  /// Pixel size of the video track.
  public let width: Int
  public let height: Int
  public let durationSeconds: Double
  public let bytes: Int

  public init(path: String, format: CLIVideoFormat, width: Int, height: Int, durationSeconds: Double, bytes: Int) {
    self.path = path
    self.format = format
    self.width = width
    self.height = height
    self.durationSeconds = durationSeconds
    self.bytes = bytes
  }
}

/// `record.stop`. Each finished recording is handed out once: to whoever stops it,
/// or, when it ended some other way (menu bar, stream error), to the next `record.stop`.
public struct CLIRecordingResult: Codable, Sendable, Equatable {
  public let id: String
  public var file: CLIRecordedFile
  /// The starter's `--output`; the CLI clears it after delivering the file.
  public var output: CLIRecordingOutput?

  public init(id: String, file: CLIRecordedFile, output: CLIRecordingOutput? = nil) {
    self.id = id
    self.file = file
    self.output = output
  }
}
