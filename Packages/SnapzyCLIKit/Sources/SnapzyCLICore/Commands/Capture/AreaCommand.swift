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
  @OptionGroup var selection: AreaSelectionOptions

  func run() async throws {
    try await CaptureCommand.run(
      .captureArea,
      params: CaptureAreaParams(rect: selection.rect, options: output.captureOptions()),
      output: output,
      global: global
    )
  }
}
