//
//  ScreenCommand.swift
//  SnapzyCLICore
//

import ArgumentParser
import SnapzyCLIProtocol

struct ScreenCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "screen",
    abstract: "Capture a whole display, or every display."
  )

  @OptionGroup var global: GlobalOptions
  @OptionGroup var output: CaptureOutputOptions

  @Option(help: "main, all, or a display ID from `snapzy list displays`.")
  var display: DisplaySelector = .main

  func run() async throws {
    try await CaptureCommand.run(
      .captureScreen,
      params: CaptureScreenParams(display: display, options: output.captureOptions()),
      output: output,
      global: global
    )
  }
}
