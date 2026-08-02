import CoreGraphics
import Foundation

/// Applies modifier-key constraints to a point being dragged on the annotation canvas.
nonisolated enum AnnotationDragConstraint {
  static func constrainedEndPoint(
    tool: AnnotationToolType,
    arrowStyle: ArrowStyle,
    start: CGPoint,
    end: CGPoint,
    shiftHeld: Bool
  ) -> CGPoint {
    guard shiftHeld else { return end }

    switch tool {
    case .rectangle, .filledRectangle, .oval:
      return squareEndPoint(start: start, end: end)
    case .line:
      return snappedLineEndPoint(start: start, end: end)
    case .arrow where arrowStyle == .straight:
      return snappedLineEndPoint(start: start, end: end)
    default:
      return end
    }
  }

  private static func squareEndPoint(start: CGPoint, end: CGPoint) -> CGPoint {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let sideLength = max(abs(dx), abs(dy))
    guard sideLength > 0 else { return end }

    return CGPoint(
      x: start.x + signedMagnitude(of: dx == 0 ? dy : dx, magnitude: sideLength),
      y: start.y + signedMagnitude(of: dy == 0 ? dx : dy, magnitude: sideLength)
    )
  }

  private static func snappedLineEndPoint(start: CGPoint, end: CGPoint) -> CGPoint {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = hypot(dx, dy)
    guard length > 0 else { return start }

    let increment = CGFloat.pi / 4
    let snappedAngle = (atan2(dy, dx) / increment).rounded() * increment

    return CGPoint(
      x: start.x + length * cos(snappedAngle),
      y: start.y + length * sin(snappedAngle)
    )
  }

  private static func signedMagnitude(of value: CGFloat, magnitude: CGFloat) -> CGFloat {
    value >= 0 ? magnitude : -magnitude
  }
}
