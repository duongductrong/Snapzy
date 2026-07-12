import CoreGraphics
import Foundation

enum CombineSnapping {
  static func resolve(
    draggedBounds: CGRect,
    candidateBounds: [CGRect],
    gap: CGFloat,
    tolerance: CGFloat
  ) -> CGRect? {
    var best: (bounds: CGRect, distance: CGFloat)?
    let safeGap = max(0, gap)

    for candidate in candidateBounds {
      let xTargets = [
        candidate.minX - safeGap - draggedBounds.width,
        candidate.maxX + safeGap
      ]
      let yTargets = [
        candidate.minY - safeGap - draggedBounds.height,
        candidate.maxY + safeGap
      ]

      for x in xTargets {
        let distance = abs(draggedBounds.minX - x)
        guard distance <= tolerance else { continue }
        let alignedY = nearestAlignment(
          currentMin: draggedBounds.minY,
          currentMax: draggedBounds.maxY,
          candidateMin: candidate.minY,
          candidateMax: candidate.maxY,
          tolerance: tolerance
        ) ?? draggedBounds.minY
        let bounds = CGRect(x: x.rounded(), y: alignedY.rounded(), width: draggedBounds.width, height: draggedBounds.height)
        if best == nil || distance < best!.distance { best = (bounds, distance) }
      }

      for y in yTargets {
        let distance = abs(draggedBounds.minY - y)
        guard distance <= tolerance else { continue }
        let alignedX = nearestAlignment(
          currentMin: draggedBounds.minX,
          currentMax: draggedBounds.maxX,
          candidateMin: candidate.minX,
          candidateMax: candidate.maxX,
          tolerance: tolerance
        ) ?? draggedBounds.minX
        let bounds = CGRect(x: alignedX.rounded(), y: y.rounded(), width: draggedBounds.width, height: draggedBounds.height)
        if best == nil || distance < best!.distance { best = (bounds, distance) }
      }
    }
    return best?.bounds
  }

  private static func nearestAlignment(
    currentMin: CGFloat,
    currentMax: CGFloat,
    candidateMin: CGFloat,
    candidateMax: CGFloat,
    tolerance: CGFloat
  ) -> CGFloat? {
    let options = [
      (candidateMin, abs(currentMin - candidateMin)),
      (candidateMax - (currentMax - currentMin), abs(currentMax - candidateMax))
    ]
    return options.min(by: { $0.1 < $1.1 }).flatMap { $0.1 <= tolerance ? $0.0 : nil }
  }
}

