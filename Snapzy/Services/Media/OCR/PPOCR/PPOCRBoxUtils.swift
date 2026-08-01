//
//  PPOCRBoxUtils.swift
//  Snapzy
//
//  DB post-processing geometry: components, mini-boxes, unclip, reading order.
//

import CoreGraphics
import Foundation

enum PPOCRBoxUtils {
  /// One 8-connected foreground component of the binarized probability map.
  struct Component {
    var minX = 0, minY = 0, maxX = 0, maxY = 0
    var probabilitySum: Float = 0
    var pixelCount = 0
    /// Pixel centres on the component's edge — those with a background or
    /// out-of-map 4-neighbour. Enough to build the convex hull `minAreaRect`
    /// needs, without retaining the interior of a large text blob.
    var boundaryPoints: [CGPoint] = []

    var meanProbability: Float {
      pixelCount > 0 ? probabilitySum / Float(pixelCount) : 0
    }
  }

  /// Labels 8-connected components of `binary` (row-major width×height),
  /// accumulating each component's mean probability and edge pixels. Specks
  /// smaller than `minPixelCount` are dropped (DB contour noise floor).
  static func connectedComponents(
    binary: [Bool],
    probability: [Float],
    width: Int,
    height: Int,
    minPixelCount: Int
  ) -> [Component] {
    var visited = [Bool](repeating: false, count: binary.count)
    var components: [Component] = []
    var stack: [Int] = []

    for start in 0..<binary.count where binary[start] && !visited[start] {
      var component = Component(minX: width, minY: height, maxX: 0, maxY: 0)
      visited[start] = true
      stack.append(start)
      while let index = stack.popLast() {
        let x = index % width
        let y = index / width
        component.pixelCount += 1
        component.probabilitySum += probability[index]
        component.minX = min(component.minX, x)
        component.maxX = max(component.maxX, x)
        component.minY = min(component.minY, y)
        component.maxY = max(component.maxY, y)

        // Edge checks come first so the neighbour reads below stay in bounds.
        let isBoundary = x == 0 || x == width - 1 || y == 0 || y == height - 1
          || !binary[index - 1] || !binary[index + 1]
          || !binary[index - width] || !binary[index + width]
        if isBoundary {
          component.boundaryPoints.append(CGPoint(x: CGFloat(x), y: CGFloat(y)))
        }

        for deltaY in -1...1 {
          for deltaX in -1...1 where deltaX != 0 || deltaY != 0 {
            let nextX = x + deltaX
            let nextY = y + deltaY
            guard nextX >= 0, nextX < width, nextY >= 0, nextY < height else { continue }
            let next = nextY * width + nextX
            if binary[next] && !visited[next] {
              visited[next] = true
              stack.append(next)
            }
          }
        }
      }
      if component.pixelCount >= minPixelCount {
        components.append(component)
      }
    }
    return components
  }

  /// Minimum-area enclosing rectangle of `points`, matching OpenCV
  /// `minAreaRect` as used by PaddleOCR's `get_mini_boxes`: rotating calipers
  /// over the convex hull, taking the orientation with the smallest area.
  ///
  /// Returns `nil` only when the points cannot form a hull at all; degenerate
  /// (collinear) inputs come back as a zero-height rectangle for the caller's
  /// minimum-size filter to reject.
  static func minAreaRect(_ points: [CGPoint]) -> PPOCRRotatedRect? {
    let hull = convexHull(points)
    guard hull.count >= 2 else { return nil }

    var best: PPOCRRotatedRect?
    var bestArea = CGFloat.greatestFiniteMagnitude

    for index in 0..<hull.count {
      let start = hull[index]
      let end = hull[(index + 1) % hull.count]
      let edge = CGPoint(x: end.x - start.x, y: end.y - start.y)
      let length = (edge.x * edge.x + edge.y * edge.y).squareRoot()
      guard length > 0 else { continue }

      let widthAxis = CGPoint(x: edge.x / length, y: edge.y / length)
      let heightAxis = CGPoint(x: -widthAxis.y, y: widthAxis.x)

      var minAlongWidth = CGFloat.greatestFiniteMagnitude
      var maxAlongWidth = -CGFloat.greatestFiniteMagnitude
      var minAlongHeight = CGFloat.greatestFiniteMagnitude
      var maxAlongHeight = -CGFloat.greatestFiniteMagnitude
      for point in hull {
        let alongWidth = point.x * widthAxis.x + point.y * widthAxis.y
        let alongHeight = point.x * heightAxis.x + point.y * heightAxis.y
        minAlongWidth = min(minAlongWidth, alongWidth)
        maxAlongWidth = max(maxAlongWidth, alongWidth)
        minAlongHeight = min(minAlongHeight, alongHeight)
        maxAlongHeight = max(maxAlongHeight, alongHeight)
      }

      let boxWidth = maxAlongWidth - minAlongWidth
      let boxHeight = maxAlongHeight - minAlongHeight
      let area = boxWidth * boxHeight
      guard area < bestArea else { continue }
      bestArea = area

      let centerAlongWidth = (minAlongWidth + maxAlongWidth) / 2
      let centerAlongHeight = (minAlongHeight + maxAlongHeight) / 2
      best = PPOCRRotatedRect(
        center: CGPoint(
          x: centerAlongWidth * widthAxis.x + centerAlongHeight * heightAxis.x,
          y: centerAlongWidth * widthAxis.y + centerAlongHeight * heightAxis.y
        ),
        size: CGSize(width: boxWidth, height: boxHeight),
        angle: atan2(widthAxis.y, widthAxis.x)
      )
    }
    return best.map(uprighted)
  }

  /// Andrew's monotone chain convex hull. Winding does not matter here —
  /// `minAreaRect` only projects the points onto candidate axes.
  static func convexHull(_ points: [CGPoint]) -> [CGPoint] {
    guard points.count > 3 else { return points }
    let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }

    func cross(_ origin: CGPoint, _ first: CGPoint, _ second: CGPoint) -> CGFloat {
      (first.x - origin.x) * (second.y - origin.y) - (first.y - origin.y) * (second.x - origin.x)
    }

    func chain(_ ordered: [CGPoint]) -> [CGPoint] {
      var result: [CGPoint] = []
      for point in ordered {
        while result.count >= 2,
              cross(result[result.count - 2], result[result.count - 1], point) <= 0 {
          result.removeLast()
        }
        result.append(point)
      }
      result.removeLast()
      return result
    }

    let hull = chain(sorted) + chain(sorted.reversed())
    // Every point identical collapses both chains; fall back to the input.
    return hull.isEmpty ? points : hull
  }

  /// Puts the long axis on `width` and folds the angle into (-90°, 90°], so a
  /// horizontal text line reads as angle ≈ 0 whichever hull edge won the fit.
  ///
  /// This subsumes PaddleOCR's "taller than 1.5× its width ⇒ rotate upright"
  /// rule in `get_rotate_crop_image`: after normalization the crop is never
  /// taller than it is wide.
  private static func uprighted(_ rect: PPOCRRotatedRect) -> PPOCRRotatedRect {
    var result = rect
    if result.size.height > result.size.width {
      result.size = CGSize(width: result.size.height, height: result.size.width)
      result.angle += .pi / 2
    }
    while result.angle > .pi / 2 { result.angle -= .pi }
    while result.angle <= -.pi / 2 { result.angle += .pi }
    return result
  }

  /// PaddleOCR `DBPostProcess.unclip`: offsets the mini-box outward by
  /// `area × ratio / perimeter`. Applied along the box's own axes, so a
  /// rotated line grows perpendicular to its baseline rather than to the
  /// image axes.
  static func unclipped(_ rect: PPOCRRotatedRect, ratio: CGFloat) -> PPOCRRotatedRect {
    let width = rect.size.width
    let height = rect.size.height
    guard width > 0, height > 0 else { return rect }
    let distance = width * height * ratio / (2 * (width + height))
    return rect.padded(by: distance)
  }

  /// PaddleOCR `sorted_boxes`: sort by (top y, top x), then bubble adjacent
  /// boxes within a 10px vertical tolerance into left-to-right order.
  static func readingOrder(_ boxes: [PPOCRTextBox]) -> [PPOCRTextBox] {
    var sorted = boxes.sorted { lhs, rhs in
      if lhs.rect.minY != rhs.rect.minY { return lhs.rect.minY < rhs.rect.minY }
      return lhs.rect.minX < rhs.rect.minX
    }
    guard sorted.count > 1 else { return sorted }
    for index in 0..<(sorted.count - 1) {
      var previous = index
      while previous >= 0 {
        let next = previous + 1
        if abs(sorted[next].rect.minY - sorted[previous].rect.minY) < 10,
           sorted[next].rect.minX < sorted[previous].rect.minX {
          sorted.swapAt(previous, next)
          previous -= 1
        } else {
          break
        }
      }
    }
    return sorted
  }
}
