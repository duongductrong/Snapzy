//
//  CropContentAnalyzer+ContentBounds.swift
//  Snapzy
//
//  Auto-crop: tighten a rough crop rect to the detected content borders of a
//  CropEdgeProfile. Pure math over image points; safe to call off-main.
//

import CoreGraphics
import Foundation

extension CropContentAnalyzer {

  // MARK: - Auto-crop

  /// Tighten a rough rect (image points, bottom-left origin) to the strongest
  /// detected content border on each side. Candidates per side are edges
  /// strictly inside `rect` within the inner half toward that side; ties in
  /// strength (within 1.0) resolve to the outermost edge. Returns nil when no
  /// side has a candidate, when the result is smaller than `minContentSize`,
  /// or when the shrink removes less than 5% of the rect area.
  nonisolated static func contentBounds(
    in rect: CGRect,
    profile: CropEdgeProfile,
    minContentSize: CGFloat = 20
  ) -> CGRect? {
    let rect = rect.standardized
    guard rect.width > 0, rect.height > 0 else { return nil }

    let left = strongestEdge(profile.verticalEdges, profile.verticalStrengths,
                             in: rect.minX..<rect.midX, outermostIsMin: true)
    let right = strongestEdge(profile.verticalEdges, profile.verticalStrengths,
                              in: rect.midX..<rect.maxX, outermostIsMin: false)
    let bottom = strongestEdge(profile.horizontalEdges, profile.horizontalStrengths,
                               in: rect.minY..<rect.midY, outermostIsMin: true)
    let top = strongestEdge(profile.horizontalEdges, profile.horizontalStrengths,
                            in: rect.midY..<rect.maxY, outermostIsMin: false)
    guard left != nil || right != nil || bottom != nil || top != nil else { return nil }

    let tightened = CGRect(
      x: left ?? rect.minX,
      y: bottom ?? rect.minY,
      width: (right ?? rect.maxX) - (left ?? rect.minX),
      height: (top ?? rect.maxY) - (bottom ?? rect.minY)
    ).standardized.intersection(rect)
    guard !tightened.isNull,
          tightened.width >= minContentSize,
          tightened.height >= minContentSize else { return nil }

    let areaReduction = 1 - (tightened.width * tightened.height) / (rect.width * rect.height)
    guard areaReduction >= 0.05 else { return nil }
    return tightened
  }

  /// Strongest edge strictly inside `range`; strength ties (within 1.0)
  /// resolve to the outermost edge (min for left/bottom, max for right/top).
  private nonisolated static func strongestEdge(
    _ edges: [CGFloat], _ strengths: [CGFloat],
    in range: Range<CGFloat>, outermostIsMin: Bool
  ) -> CGFloat? {
    var best: (edge: CGFloat, strength: CGFloat)?
    for (edge, strength) in zip(edges, strengths) where range.contains(edge) {
      guard let current = best else { best = (edge, strength); continue }
      if strength > current.strength + 1 {
        best = (edge, strength)
      } else if strength >= current.strength - 1,
                outermostIsMin ? edge < current.edge : edge > current.edge {
        best = (edge, strength)
      }
    }
    return best?.edge
  }
}
