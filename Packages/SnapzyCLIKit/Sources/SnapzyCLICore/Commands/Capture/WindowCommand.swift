//
//  WindowCommand.swift
//  SnapzyCLICore
//

import ArgumentParser
import Foundation
import SnapzyCLIProtocol

struct WindowCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "window",
    abstract: "Capture one window, even when other windows cover it.",
    discussion: "Pick the window with exactly one of --id, --app or --active."
  )

  @OptionGroup var global: GlobalOptions
  @OptionGroup var output: CaptureOutputOptions

  @Option(help: "Window ID from `snapzy list windows`.")
  var id: UInt32?

  @Option(help: "App name or bundle ID. Captures its frontmost window unless --title or --index narrows it.")
  var app: String?

  @Option(help: "Regular expression matched against window titles (with --app).")
  var title: String?

  @Option(help: "0-based index among the matching windows, front to back (with --app).")
  var index: Int?

  @Flag(help: "The focused window of the frontmost app.")
  var active = false

  @Flag(name: .customLong("no-shadow"), help: "Capture without the window shadow.")
  var noShadow = false

  mutating func validate() throws {
    _ = try selector()
  }

  func selector() throws -> WindowSelector {
    switch (id, app, active) {
    case let (id?, nil, false):
      try requireNoAppFilters()
      return .id(id)
    case let (nil, app?, false):
      if let title {
        do {
          _ = try NSRegularExpression(pattern: title)
        } catch {
          throw ValidationError("--title is not a valid regular expression: \(error.localizedDescription)")
        }
      }
      if let index, index < 0 {
        throw ValidationError("--index must be 0 or greater.")
      }
      return .app(AppWindowQuery(app: app, titlePattern: title, index: index))
    case (nil, nil, true):
      try requireNoAppFilters()
      return .active
    default:
      throw ValidationError("Pass exactly one of --id, --app or --active.")
    }
  }

  private func requireNoAppFilters() throws {
    if title != nil || index != nil {
      throw ValidationError("--title and --index only apply with --app.")
    }
  }

  func run() async throws {
    try await CaptureCommand.run(
      .captureWindow,
      params: CaptureWindowParams(
        window: selector(),
        options: output.captureOptions(windowShadow: !noShadow)
      ),
      output: output,
      global: global
    )
  }
}
