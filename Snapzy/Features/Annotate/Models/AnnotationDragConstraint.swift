import CoreGraphics
import Foundation

/// Applies modifier-key constraints to a point being dragged on the annotation canvas.
nonisolated enum AnnotationDragConstraint {
  static func constrainedEndPoint(
    tool: AnnotationToolType,
    arrowStyle: ArrowStyle,
    start: CGPoint,
    end: CGPoint,
    shiftHeld: Bool,
    bounds: CGRect
  ) -> CGPoint {
    guard shiftHeld else { return end }

    switch tool {
    case .rectangle, .filledRectangle, .oval:
      return squareEndPoint(start: start, end: end, bounds: bounds.standardized)
    case .line:
      return snappedLineEndPoint(start: start, end: end, bounds: bounds.standardized)
    case .arrow where arrowStyle == .straight:
      return snappedLineEndPoint(start: start, end: end, bounds: bounds.standardized)
    default:
      return end
    }
  }

  private static func squareEndPoint(start: CGPoint, end: CGPoint, bounds: CGRect) -> CGPoint {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let desiredSideLength = max(abs(dx), abs(dy))
    guard desiredSideLength > 0 else { return end }

    let xDirection = signedUnit(of: dx == 0 ? dy : dx)
    let yDirection = signedUnit(of: dy == 0 ? dx : dy)
    let xAvailable = xDirection > 0 ? bounds.maxX - start.x : start.x - bounds.minX
    let yAvailable = yDirection > 0 ? bounds.maxY - start.y : start.y - bounds.minY
    let sideLength = min(desiredSideLength, min(max(0, xAvailable), max(0, yAvailable)))

    return CGPoint(
      x: start.x + xDirection * sideLength,
      y: start.y + yDirection * sideLength
    )
  }

  private static func snappedLineEndPoint(start: CGPoint, end: CGPoint, bounds: CGRect) -> CGPoint {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = hypot(dx, dy)
    guard length > 0 else { return start }

    let increment = CGFloat.pi / 4
    let snappedIndex = Int((atan2(dy, dx) / increment).rounded())
    let direction = snappedDirection(at: snappedIndex)
    let constrainedLength = min(length, maximumLength(from: start, direction: direction, within: bounds))

    return CGPoint(
      x: start.x + constrainedLength * direction.dx,
      y: start.y + constrainedLength * direction.dy
    )
  }

  private static func signedUnit(of value: CGFloat) -> CGFloat {
    value >= 0 ? 1 : -1
  }

  private static func snappedDirection(at index: Int) -> CGVector {
    let diagonal = 1 / sqrt(CGFloat(2))
    switch (index % 8 + 8) % 8 {
    case 0:
      return CGVector(dx: 1, dy: 0)
    case 1:
      return CGVector(dx: diagonal, dy: diagonal)
    case 2:
      return CGVector(dx: 0, dy: 1)
    case 3:
      return CGVector(dx: -diagonal, dy: diagonal)
    case 4:
      return CGVector(dx: -1, dy: 0)
    case 5:
      return CGVector(dx: -diagonal, dy: -diagonal)
    case 6:
      return CGVector(dx: 0, dy: -1)
    default:
      return CGVector(dx: diagonal, dy: -diagonal)
    }
  }

  private static func maximumLength(from start: CGPoint, direction: CGVector, within bounds: CGRect) -> CGFloat {
    var maximumLength = CGFloat.greatestFiniteMagnitude

    if direction.dx > 0 {
      maximumLength = min(maximumLength, (bounds.maxX - start.x) / direction.dx)
    } else if direction.dx < 0 {
      maximumLength = min(maximumLength, (bounds.minX - start.x) / direction.dx)
    }

    if direction.dy > 0 {
      maximumLength = min(maximumLength, (bounds.maxY - start.y) / direction.dy)
    } else if direction.dy < 0 {
      maximumLength = min(maximumLength, (bounds.minY - start.y) / direction.dy)
    }

    return max(0, maximumLength)
  }
}
