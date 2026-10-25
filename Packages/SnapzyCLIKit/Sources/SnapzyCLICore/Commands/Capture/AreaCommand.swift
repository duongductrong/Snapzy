//
//  AreaCommand.swift
//  SnapzyCLICore
//

import ArgumentParser
import SnapzyCLIProtocol

struct AreaCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "area",
    abstract: "Capture a rectangle of the screen.",
    discussion: """
    Coordinates are global points with the origin at the top-left of the main \
    display, the same space as the frames printed by `snapzy list`.
    """
  )

  @OptionGroup var global: GlobalOptions
  @OptionGroup var output: CaptureOutputOptions

  /// `.unconditional` so displays left of or above the main one work:
  /// `--rect -1440,0,800,600` would otherwise parse `-1440…` as an option.
  @Option(parsing: .unconditional, help: "Rectangle as x,y,width,height in points.")
  var rect: CLIRect

  func run() async throws {
    try await CaptureCommand.run(
      .captureArea,
      params: CaptureAreaParams(rect: rect, options: output.captureOptions()),
      output: output,
      global: global
    )
  }
}
