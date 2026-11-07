//
//  WindowCommand.swift
//  SnapzyCLICore
//

import ArgumentParser
import SnapzyCLIProtocol

struct WindowCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "window",
    abstract: "Capture one window, even when other windows cover it.",
    discussion: "Pick the window with exactly one of --id, --app or --active."
  )

  @OptionGroup var global: GlobalOptions
  @OptionGroup var output: CaptureOutputOptions
  @OptionGroup var selection: WindowSelectionOptions

  @Flag(name: .customLong("no-shadow"), help: "Capture without the window shadow.")
  var noShadow = false

  func run() async throws {
    try await CaptureCommand.run(
      .captureWindow,
      params: CaptureWindowParams(
        window: selection.selector(),
        options: output.captureOptions(windowShadow: !noShadow)
      ),
      output: output,
      global: global
    )
  }
}
