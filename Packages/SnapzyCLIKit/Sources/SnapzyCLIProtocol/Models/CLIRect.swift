//
//  CLIRect.swift
//  SnapzyCLIProtocol
//
//  Geometry on the wire is in global points with a top-left origin at the
//  main display — the CoreGraphics / Accessibility convention, so a frame from
//  `list windows` can be passed straight back to `capture area`.
//

import Foundation

public struct CLIRect: Codable, Sendable, Hashable, CustomStringConvertible {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  /// Parses `x,y,width,height`. Width and height must be positive.
  public init?(argument: String) {
    let values = argument
      .split(separator: ",", omittingEmptySubsequences: false)
      .map { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard
      values.count == 4,
      let x = values[0], let y = values[1], let width = values[2], let height = values[3],
      [x, y, width, height].allSatisfy(\.isFinite),
      width > 0, height > 0
    else { return nil }
    self.init(x: x, y: y, width: width, height: height)
  }

  public var description: String {
    [x, y, width, height].map(Self.format).joined(separator: ",")
  }

  private static func format(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(value)
  }
}
