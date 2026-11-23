//
//  RecordCommand.swift
//  SnapzyCLICore
//
//  `record screen|window|area|stop|status`. A recording runs in Snapzy with no
//  toolbar or overlay. By default the command stays attached and stops on
//  Ctrl-C, SIGTERM or `--duration`; `--detach` returns at once and
//  `snapzy record stop` ends it later. The finished file is moved to `--output`
//  by whichever `snapzy` process collects it.
//

import ArgumentParser
import Foundation
import SnapzyCLIClient
import SnapzyCLIProtocol

struct RecordCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "record",
    abstract: "Record a display, a window or an area to a video file.",
    discussion: """
    Recording stays attached until Ctrl-C, SIGTERM or --duration, then prints the \
    file. With --detach it returns at once; stop it with `snapzy record stop`.
    """,
    subcommands: [
      RecordScreenCommand.self,
      RecordWindowCommand.self,
      RecordAreaCommand.self,
      RecordStopCommand.self,
      RecordStatusCommand.self,
    ]
  )

  /// `record.stop` waits for Snapzy to finish writing the file, which grows with the recording.
  static let minimumStopTimeout: TimeInterval = 120

  static func start(
    _ method: CLIMethod,
    options: RecordingOutputOptions,
    global: GlobalOptions,
    params makeParams: (RecordingOptions, CLIRecordingOutput?) throws -> some Codable & Sendable
  ) async throws {
    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let destination = OutputDestination.resolve(options.output, currentDirectory: currentDirectory)
    let writer = OutputWriter()
    try await CommandRunner.reportingErrors(global.renderer) {
      try writer.preflight(destination, force: options.force)
    }
    let params = try makeParams(options.recordingOptions(), destination.recordingOutput(force: options.force))

    let stopRequest = StopRequest()
    if !options.detach {
      // Before starting, so a Ctrl-C during the start request still stops cleanly.
      stopRequest.install()
    }
    defer { stopRequest.uninstall() }

    try await CommandRunner.run(global) { client, renderer in
      let info = try client.call(method, params: params, as: CLIRecordingInfo.self)
      if options.detach {
        try StandardStreams.write(renderer.render(info))
        if renderer.mode == .human {
          StandardStreams.writeError("Stop it with `snapzy record stop`.\n")
        }
        return
      }

      if renderer.mode == .human {
        let until = options.duration.map { "for \(RecordingDuration.text($0)) or " } ?? ""
        StandardStreams.writeError("Recording \(info.id) \(until)until Ctrl-C…\n")
      }
      let reason = try RecordingWaiter(id: info.id, duration: options.duration, stopRequest: stopRequest) {
        try client.call(.recordStatus, as: CLIRecordingStatus.self)
      }.wait()

      let result: CLIRecordingResult
      do {
        result = try client.call(
          .recordStop,
          params: RecordStopParams(id: info.id),
          as: CLIRecordingResult.self,
          timeout: max(client.requestTimeout, minimumStopTimeout)
        )
      } catch let error as CLIError where error.code == .targetNotFound && reason == .stoppedElsewhere {
        // Another `snapzy record stop` collected the file and moved it to --output.
        StandardStreams.writeError(renderer.mode == .human
          ? "Recording \(info.id) was stopped and saved by another snapzy command.\n"
          : renderer.render(error: CLIError(.targetNotFound, error.message)))
        throw ExitCode(error.code.exitCode)
      }
      try StandardStreams.write(renderer.render(deliver(result, override: nil, writer: writer,
                                                        currentDirectory: currentDirectory)))
    }
  }

  /// Moves the staged video to `override` (from `record stop -o`) or the starter's `--output`.
  static func deliver(
    _ result: CLIRecordingResult,
    override: CLIRecordingOutput?,
    writer: OutputWriter,
    currentDirectory: URL
  ) throws -> CLIRecordingResult {
    let output = override ?? result.output
    let destination = output.map { OutputDestination.resolve($0.path, currentDirectory: currentDirectory) } ?? .staging
    var delivered = result
    delivered.file.path = try writer.deliver(
      stagedPath: result.file.path,
      to: destination,
      force: output?.force ?? false
    )
    delivered.output = nil
    return delivered
  }
}

extension OutputDestination {
  /// What the app stores for whoever collects the recording; `nil` keeps it in staging.
  func recordingOutput(force: Bool) -> CLIRecordingOutput? {
    switch self {
    case .staging, .standardOutput:
      nil
    case .directory(let url):
      CLIRecordingOutput(path: url.path.hasSuffix("/") ? url.path : url.path + "/", force: force)
    case .file(let url):
      CLIRecordingOutput(path: url.path, force: force)
    }
  }
}

struct RecordingOutputOptions: ParsableArguments {
  @Option(
    name: [.short, .long],
    help: ArgumentHelp(
      "Where to write the video: a .mov/.mp4 file, or a directory (trailing /).",
      discussion: "Without it the file stays in Snapzy's staging folder for 24 hours."
    )
  )
  var output: String?

  @Flag(help: "Overwrite an existing file at --output.")
  var force = false

  @Option(help: "Video format. Defaults to the --output extension, else mov.")
  var format: CLIVideoFormat?

  @Option(help: "Video quality: high, medium or low.")
  var quality: CLIVideoQuality = .high

  @Option(help: "Frames per second: 30 or 60.")
  var fps = 30

  @Flag(name: .customLong("no-cursor"), help: "Leave the mouse cursor out of the video.")
  var noCursor = false

  @Flag(name: .customLong("system-audio"), help: "Record the audio the Mac plays.")
  var systemAudio = false

  @Flag(name: .customLong("mic"), help: "Record the default microphone (Snapzy needs Microphone access already).")
  var microphone = false

  @Option(help: "Stop after this many seconds.")
  var duration: Double?

  @Flag(help: "Return once recording starts; stop it with `snapzy record stop`.")
  var detach = false

  mutating func validate() throws {
    _ = try resolvedFormat()
    guard RecordingOptions.supportedFrameRates.contains(fps) else {
      throw ValidationError("--fps must be 30 or 60.")
    }
    if let duration {
      guard duration > 0, duration.isFinite else { throw ValidationError("--duration must be greater than 0.") }
      guard !detach else { throw ValidationError("--duration needs the command to stay attached; drop --detach.") }
    }
  }

  func resolvedFormat(fileManager: FileManager = .default) throws -> CLIVideoFormat {
    guard let output, output != "-" else {
      if output == "-" {
        throw ValidationError("Recordings cannot be written to stdout; pass a file or directory to --output.")
      }
      return format ?? .mov
    }
    var isDirectory: ObjCBool = false
    let expanded = (output as NSString).expandingTildeInPath
    if output.hasSuffix("/") || (fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory) && isDirectory.boolValue) {
      return format ?? .mov
    }

    let pathExtension = URL(fileURLWithPath: output).pathExtension
    guard !pathExtension.isEmpty else {
      throw ValidationError("--output needs a .mov or .mp4 extension, or a trailing / for a directory.")
    }
    guard let outputFormat = CLIVideoFormat(fileExtension: pathExtension) else {
      throw ValidationError("--output extension .\(pathExtension) is not a video format; use .mov or .mp4.")
    }
    if let format, format != outputFormat {
      throw ValidationError(
        "--format \(format.fileExtension) does not match the --output extension .\(outputFormat.fileExtension)."
      )
    }
    return outputFormat
  }

  func recordingOptions() throws -> RecordingOptions {
    try RecordingOptions(
      format: resolvedFormat(),
      quality: quality,
      fps: fps,
      showCursor: !noCursor,
      systemAudio: systemAudio,
      microphone: microphone
    )
  }
}

// MARK: - Waiting

/// Why an attached `snapzy record` stopped waiting.
enum RecordingEndReason: Equatable {
  case signal
  case duration
  /// The menu bar, the recording shortcut, `snapzy record stop`, or a stream failure ended it.
  case stoppedElsewhere
}

/// Waits for Ctrl-C / SIGTERM, `--duration`, or the recording ending on its own,
/// polling `record.status` (which also keeps the connection inside its idle timeout).
struct RecordingWaiter {
  let id: String
  let duration: TimeInterval?
  let stopRequest: StopRequest
  var pollInterval: TimeInterval = 1
  var tick: TimeInterval = 0.05
  var now: () -> Date = Date.init
  var sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
  let status: () throws -> CLIRecordingStatus

  init(
    id: String,
    duration: TimeInterval?,
    stopRequest: StopRequest,
    status: @escaping () throws -> CLIRecordingStatus
  ) {
    self.id = id
    self.duration = duration
    self.stopRequest = stopRequest
    self.status = status
  }

  func wait() throws -> RecordingEndReason {
    let start = now()
    var lastPoll = start
    while true {
      if stopRequest.isRequested { return .signal }
      let current = now()
      if let duration, current.timeIntervalSince(start) >= duration { return .duration }
      if current.timeIntervalSince(lastPoll) >= pollInterval {
        lastPoll = current
        if try status().recording?.id != id { return .stoppedElsewhere }
      }
      sleep(tick)
    }
  }
}

/// Turns SIGINT, SIGTERM and SIGHUP into a stop request. A second signal while
/// stopping exits at once (Snapzy still finishes the file; `snapzy record stop` collects it).
final class StopRequest: @unchecked Sendable {
  static let signals = [SIGINT, SIGTERM, SIGHUP]

  private let lock = NSLock()
  private var requested = false
  private var sources: [DispatchSourceSignal] = []

  var isRequested: Bool {
    lock.withLock { requested }
  }

  func request() {
    let alreadyRequested = lock.withLock {
      defer { requested = true }
      return requested
    }
    if alreadyRequested {
      Foundation.exit(130)
    }
  }

  func install() {
    for signalNumber in Self.signals {
      signal(signalNumber, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global(qos: .userInitiated))
      source.setEventHandler { [weak self] in self?.request() }
      source.resume()
      sources.append(source)
    }
  }

  func uninstall() {
    guard !sources.isEmpty else { return }
    sources.forEach { $0.cancel() }
    sources.removeAll()
    for signalNumber in Self.signals {
      signal(signalNumber, SIG_DFL)
    }
  }
}

enum RecordingDuration {
  /// `12s`, `1.5s`, `2m 5s`.
  static func text(_ seconds: Double) -> String {
    guard seconds >= 60 else {
      return seconds.rounded() == seconds ? "\(Int(seconds))s" : String(format: "%.1fs", seconds)
    }
    let whole = Int(seconds.rounded())
    return whole % 60 == 0 ? "\(whole / 60)m" : "\(whole / 60)m \(whole % 60)s"
  }
}
