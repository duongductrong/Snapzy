import Foundation

// Simple Codable geometry. Deliberately separate from CoreGraphics so the
// projection never drags AppKit/UIKit types across the process boundary, and
// so its encoding is stable forever.

/// A point in logical image point space (1× authoring coordinates).
public struct SnapzyPoint: Codable, Sendable, Hashable {
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

/// A rect in logical image point space, top-left origin.
public struct SnapzyRect: Codable, Sendable, Hashable {
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

  public var isNull: Bool { width <= 0 || height <= 0 }

  public var standardized: SnapzyRect {
    SnapzyRect(
      x: width < 0 ? x + width : x,
      y: height < 0 ? y + height : y,
      width: abs(width),
      height: abs(height)
    )
  }
}

/// A size in logical image point space.
public struct SnapzySize: Codable, Sendable, Hashable {
  public let width: Double
  public let height: Double

  public init(width: Double, height: Double) {
    self.width = width
    self.height = height
  }
}

/// An RGBA color, components in 0…1.
public struct SnapzyColor: Codable, Sendable, Hashable {
  public let red: Double
  public let green: Double
  public let blue: Double
  public let alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }
}
