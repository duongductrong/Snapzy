//
//  MeasurePixel.swift
//  SnapzyMeasureCore
//
//  A pixel in an image, top-left origin (CGImage convention).
//

public struct MeasurePixel: Equatable, Hashable, Sendable {
  public var x: Int
  public var y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }
}
