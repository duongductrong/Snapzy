//
//  SelectionOptions.swift
//  SnapzyCLICore
//
//  What to capture: one display, one window or one rectangle. Shared by
//  `capture` and `measure` so both command families take identical flags.
//

import ArgumentParser
import Foundation
import SnapzyCLIProtocol

struct DisplaySelectionOptions: ParsableArguments {
  @Option(help: "main, all, or a display ID from `snapzy list displays`.")
  var display: DisplaySelector = .main
}

struct WindowSelectionOptions: ParsableArguments {
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
}

struct AreaSelectionOptions: ParsableArguments {
  /// `.unconditional` so displays left of or above the main one work:
  /// `--rect -1440,0,800,600` would otherwise parse `-1440…` as an option.
  @Option(parsing: .unconditional, help: "Rectangle as x,y,width,height in points.")
  var rect: CLIRect
}
