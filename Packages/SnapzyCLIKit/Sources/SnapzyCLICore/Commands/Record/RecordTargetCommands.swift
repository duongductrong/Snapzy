//
//  RecordTargetCommands.swift
//  SnapzyCLICore
//
//  `record screen|window|area`: the same target flags as `capture`.
//

import ArgumentParser
import Foundation
import SnapzyCLIProtocol

struct RecordScreenCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "screen",
    abstract: "Record a whole display."
  )

  @OptionGroup var global: GlobalOptions
  @OptionGroup var output: RecordingOutputOptions

  @Option(help: "main or a display ID from `snapzy list displays`.")
  var display: DisplaySelector = .main

  mutating func validate() throws {
    if display == .all {
      throw ValidationError("A recording covers one display; pass --display main or a display ID.")
    }
  }

  func run() async throws {
    try await RecordCommand.start(.recordScreen, options: output, global: global) { options, destination in
      RecordScreenParams(display: display, options: options, output: destination)
    }
  }
}

struct RecordWindowCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "window",
    abstract: "Record one window, even when other windows cover it.",
    discussion: "Pick the window with exactly one of --id, --app or --active. It must be on screen."
  )

  @OptionGroup var global: GlobalOptions
  @OptionGroup var output: RecordingOutputOptions
  @OptionGroup var selection: WindowSelectionOptions

  func run() async throws {
    try await RecordCommand.start(.recordWindow, options: output, global: global) { options, destination in
      try RecordWindowParams(window: selection.selector(), options: options, output: destination)
    }
  }
}

struct RecordAreaCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "area",
    abstract: "Record a rectangle of the screen.",
    discussion: """
    Coordinates are global points with the origin at the top-left of the main \
    display. A rectangle spanning displays records the part on the display it \
    overlaps most.
    """
  )

  @OptionGroup var global: GlobalOptions
  @OptionGroup var output: RecordingOutputOptions
  @OptionGroup var selection: AreaSelectionOptions

  func run() async throws {
    try await RecordCommand.start(.recordArea, options: output, global: global) { options, destination in
      RecordAreaParams(rect: selection.rect, options: options, output: destination)
    }
  }
}

struct RecordStopCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "stop",
    abstract: "Stop the snapzy recording and print its file.",
    discussion: """
    The file goes to the --output the recording was started with, unless -o is \
    given here. Also collects a recording that was stopped from the menu bar.
    """
  )

  @OptionGroup var global: GlobalOptions

  @Option(help: "Recording ID from `snapzy record status`; defaults to the current one.")
  var id: String?

  @Option(name: [.short, .long], help: "Where to write the video instead of the start command's --output.")
  var output: String?

  @Flag(help: "Overwrite an existing file at --output.")
  var force = false

  mutating func validate() throws {
    if output == "-" {
      throw ValidationError("Recordings cannot be written to stdout; pass a file or directory to --output.")
    }
  }

  func run() async throws {
    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let override = OutputDestination.resolve(output, currentDirectory: currentDirectory).recordingOutput(force: force)
    try await CommandRunner.run(global) { client, renderer in
      let result = try client.call(
        .recordStop,
        params: RecordStopParams(id: id),
        as: CLIRecordingResult.self,
        timeout: max(client.requestTimeout, RecordCommand.minimumStopTimeout)
      )
      let delivered = try RecordCommand.deliver(
        result,
        override: override,
        writer: OutputWriter(),
        currentDirectory: currentDirectory
      )
      try StandardStreams.write(renderer.render(delivered))
    }
  }
}

struct RecordStatusCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: "Show the snapzy recording in progress, if any."
  )

  @OptionGroup var global: GlobalOptions

  func run() async throws {
    try await CommandRunner.run(global) { client, renderer in
      let status = try client.call(.recordStatus, as: CLIRecordingStatus.self)
      try StandardStreams.write(renderer.render(status))
    }
  }
}
