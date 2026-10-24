//
//  CaptureResult.swift
//  SnapzyCLIProtocol
//
//  `capture.*` result. The app writes files into its staging directory; the
//  CLI moves them to `--output` and rewrites `path` before printing.
//

import Foundation

public struct CLICapturedFile: Codable, Sendable, Equatable {
  public var path: String
  public let format: CLIImageFormat
  /// Pixel size of the written image.
  public let width: Int
  public let height: Int
  /// Pixels per point of the written image (lower than the display scale after `maxDimension`).
  public let scale: Double
  public let bytes: Int
  public let displayID: UInt32?
  public let window: CLIWindow?
  /// How many windows matched an `app` selector; the frontmost (or `index`) one was captured.
  public let matchedCandidates: Int?

  public init(
    path: String,
    format: CLIImageFormat,
    width: Int,
    height: Int,
    scale: Double,
    bytes: Int,
    displayID: UInt32? = nil,
    window: CLIWindow? = nil,
    matchedCandidates: Int? = nil
  ) {
    self.path = path
    self.format = format
    self.width = width
    self.height = height
    self.scale = scale
    self.bytes = bytes
    self.displayID = displayID
    self.window = window
    self.matchedCandidates = matchedCandidates
  }
}

public struct CLICaptureResult: Codable, Sendable, Equatable {
  /// One file per captured display; window and area captures produce one file.
  public var files: [CLICapturedFile]
  public let durationMs: Int

  public init(files: [CLICapturedFile], durationMs: Int) {
    self.files = files
    self.durationMs = durationMs
  }
}
