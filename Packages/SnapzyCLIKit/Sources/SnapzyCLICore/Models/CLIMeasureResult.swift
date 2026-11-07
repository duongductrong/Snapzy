//
//  CLIMeasureResult.swift
//  SnapzyCLICore
//
//  `snapzy measure` output. CLI-only (never on the wire): measuring happens in
//  the CLI process, on a file or on a staged capture. Geometry has a top-left
//  origin at the measured image; values are in points (pixels ÷ scale) and in
//  image pixels.
//

import Foundation
import SnapzyCLIProtocol
import SnapzyMeasureCore

/// `x,y` from the command line.
public struct CLIPoint: Codable, Sendable, Hashable, CustomStringConvertible {
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }

  /// Parses `x,y`.
  public init?(argument: String) {
    let values = argument
      .split(separator: ",", omittingEmptySubsequences: false)
      .map { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard values.count == 2, let x = values[0], let y = values[1], x.isFinite, y.isFinite else { return nil }
    self.init(x: x, y: y)
  }

  public var description: String {
    [x, y].map(CLIMeasureNumber.text).joined(separator: ",")
  }
}

/// What was measured.
public struct CLIMeasureSource: Encodable, Sendable, Equatable {
  public enum Kind: String, Encodable, Sendable {
    case image
    case screen
    case window
    case area
  }

  public let kind: Kind
  /// The image file; nil for a capture that was not kept.
  public let path: String?
  /// Pixel size of the measured image.
  public let width: Int
  public let height: Int
  /// Pixels per point.
  public let scale: Double
  public let displayID: UInt32?
  public let window: CLIWindow?

  public init(
    kind: Kind,
    path: String?,
    width: Int,
    height: Int,
    scale: Double,
    displayID: UInt32? = nil,
    window: CLIWindow? = nil
  ) {
    self.kind = kind
    self.path = path
    self.width = width
    self.height = height
    self.scale = scale
    self.displayID = displayID
    self.window = window
  }
}

/// One measurement in one unit. `width`/`height` are null for an axis a span did not measure;
/// `rect` always covers the measured pixels (one pixel thick on an unmeasured axis).
public struct CLIMeasureExtent: Encodable, Sendable, Equatable {
  public let width: Double?
  public let height: Double?
  public let rect: CLIRect

  private enum CodingKeys: String, CodingKey {
    case width, height, rect
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    // `encode` (not `encodeIfPresent`) so an unmeasured axis is an explicit null.
    try container.encode(width, forKey: .width)
    try container.encode(height, forKey: .height)
    try container.encode(rect, forKey: .rect)
  }
}

public enum CLIMeasurement: Encodable, Sendable, Equatable {
  /// The run of matching pixels around `at`. `at` echoes the input (points, or pixels with `--pixels`).
  case span(at: CLIPoint, axis: MeasureAxis, points: CLIMeasureExtent, pixels: CLIMeasureExtent)
  /// `input` echoes the requested box; `snapped` is false with `--no-snap`.
  case box(input: CLIRect, snapped: Bool, points: CLIMeasureExtent, pixels: CLIMeasureExtent)

  public var points: CLIMeasureExtent {
    switch self {
    case .span(_, _, let points, _), .box(_, _, let points, _): points
    }
  }

  public var pixels: CLIMeasureExtent {
    switch self {
    case .span(_, _, _, let pixels), .box(_, _, _, let pixels): pixels
    }
  }

  private enum CodingKeys: String, CodingKey {
    case kind, at, axis, input, snapped, points, pixels
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .span(at, axis, points, pixels):
      try container.encode("span", forKey: .kind)
      try container.encode(at, forKey: .at)
      try container.encode(axis.rawValue, forKey: .axis)
      try container.encode(points, forKey: .points)
      try container.encode(pixels, forKey: .pixels)
    case let .box(input, snapped, points, pixels):
      try container.encode("box", forKey: .kind)
      try container.encode(input, forKey: .input)
      try container.encode(snapped, forKey: .snapped)
      try container.encode(points, forKey: .points)
      try container.encode(pixels, forKey: .pixels)
    }
  }
}

public struct CLIMeasureResult: Encodable, Sendable, Equatable {
  public let source: CLIMeasureSource
  public let tolerance: Int
  public let measurements: [CLIMeasurement]

  public init(source: CLIMeasureSource, tolerance: Int, measurements: [CLIMeasurement]) {
    self.source = source
    self.tolerance = tolerance
    self.measurements = measurements
  }
}

/// Plain number text: `120`, `120.5`, `0.333` (at most three decimals).
enum CLIMeasureNumber {
  static func text(_ value: Double) -> String {
    guard value.isFinite else { return String(value) }
    let rounded = (value * 1000).rounded() / 1000
    // Whole numbers print without decimals; beyond Int range (`--at 1e30,0`) `Int(_:)` would trap.
    if rounded == rounded.rounded(), abs(rounded) < 1e15 {
      return String(Int(rounded))
    }
    var text = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), rounded)
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text
  }
}
