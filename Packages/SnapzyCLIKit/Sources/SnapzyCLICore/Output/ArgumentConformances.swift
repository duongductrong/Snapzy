//
//  ArgumentConformances.swift
//  SnapzyCLICore
//
//  Lets wire types be parsed directly from command-line values. `CLIRect` and
//  `DisplaySelector` already provide `init?(argument:)` in SnapzyCLIProtocol.
//

import ArgumentParser
import SnapzyCLIProtocol

extension CLIRect: ExpressibleByArgument {}

extension DisplaySelector: ExpressibleByArgument {}

extension CLIImageFormat: ExpressibleByArgument {
  /// Accepts `png`, `jpg`, `jpeg` and `webp`.
  public init?(argument: String) {
    self.init(fileExtension: argument)
  }

  public static var allValueStrings: [String] {
    ["png", "jpg", "webp"]
  }
}
