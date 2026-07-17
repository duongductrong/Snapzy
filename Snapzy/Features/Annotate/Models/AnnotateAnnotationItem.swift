//
//  AnnotateAnnotationItem.swift
//  Snapzy
//
//  Model representing a single annotation element
//

import CoreGraphics
import Foundation
import SwiftUI

/// Blur effect type for blur annotations
enum BlurType: String, CaseIterable, Identifiable, Equatable {
  case pixelated
  case gaussian
  case hexagonal
  case crystallized
  case pointillism
  case halftone
  case tape
  case washi

  var id: String {
    rawValue
  }

  var displayName: String {
    switch self {
    case .pixelated: L10n.AnnotateUI.pixelated
    case .gaussian: L10n.AnnotateUI.gaussian
    case .hexagonal: L10n.AnnotateUI.hexagonal
    case .crystallized: L10n.AnnotateUI.crystallized
    case .pointillism: L10n.AnnotateUI.pointillism
    case .halftone: L10n.AnnotateUI.halftone
    case .tape: L10n.AnnotateUI.tape
    case .washi: L10n.AnnotateUI.washi
    }
  }

  var icon: String {
    switch self {
    case .pixelated: "square.grid.3x3"
    case .gaussian: "drop.halffull"
    case .hexagonal: "hexagon"
    case .crystallized: "sparkles"
    case .pointillism: "circle.grid.3x3.fill"
    case .halftone: "checkerboard.rectangle"
    case .tape: "bandage"
    case .washi: "paintbrush"
    }
  }
}

enum WatermarkStyle: String, CaseIterable, Identifiable, Equatable {
  case single
  case diagonal
  case tiled

  var id: String {
    rawValue
  }

  var displayName: String {
    switch self {
    case .single: L10n.AnnotateUI.watermarkSingle
    case .diagonal: L10n.AnnotateUI.watermarkDiagonal
    case .tiled: L10n.AnnotateUI.watermarkTiled
    }
  }

  var icon: String {
    switch self {
    case .single: "text.aligncenter"
    case .diagonal: "line.diagonal"
    case .tiled: "square.grid.3x3"
    }
  }

  var defaultRotationDegrees: CGFloat {
    switch self {
    case .single: 0
    case .diagonal, .tiled: -24
    }
  }
}

enum TextPresentation: String, CaseIterable, Identifiable, Equatable {
  case plain
  case label
  case callout

  var id: String { rawValue }

  var icon: String {
    switch self {
    case .plain: "textformat"
    case .label: "rectangle.fill"
    case .callout: "text.bubble.fill"
    }
  }

  var helpText: String {
    switch self {
    case .plain: "Transparent text"
    case .label: "Text label"
    case .callout: "Callout label"
    }
  }
}

/// Shared proportions for label and callout text. Keeping these in one place
/// makes the editing overlay, on-canvas preview, and exported image agree.
enum TextBubbleGeometry {
  private enum TailSide {
    case minX
    case maxX
    case minY
    case maxY
  }

  private struct TailGeometry {
    let side: TailSide
    let target: CGPoint
    let entry: CGPoint
    let exit: CGPoint
    let tangent: CGPoint
    let rootHalfWidth: CGFloat
  }

  static func contentInsets(for presentation: TextPresentation, fontSize: CGFloat) -> CGSize {
    guard presentation != .plain else { return CGSize(width: 4, height: 4) }
    return CGSize(
      width: max(9, min(fontSize * 0.55, 18)),
      height: max(5, min(fontSize * 0.32, 10))
    )
  }

  static func cornerRadius(in bounds: CGRect, fontSize: CGFloat) -> CGFloat {
    min(max(4, fontSize * 0.16), min(bounds.width, bounds.height) * 0.12)
  }

  static func defaultTailTarget(for bounds: CGRect, fontSize: CGFloat) -> CGPoint {
    CGPoint(
      x: bounds.minX + bounds.width * 0.795,
      y: bounds.minY - bounds.height * 0.35
    )
  }

  static func isDefaultTail(_ target: CGPoint, for bounds: CGRect, fontSize: CGFloat) -> Bool {
    let expected = defaultTailTarget(for: bounds, fontSize: fontSize)
    return hypot(target.x - expected.x, target.y - expected.y) < 1
  }

  static func resolvedTailTarget(in rect: CGRect, requestedTarget: CGPoint, fontSize: CGFloat) -> CGPoint {
    guard requestedTarget.x.isFinite, requestedTarget.y.isFinite else {
      return defaultTailTarget(for: rect, fontSize: fontSize)
    }
    return requestedTarget
  }

  static func bubblePath(
    in rect: CGRect,
    cornerRadius: CGFloat,
    tailTarget: CGPoint?,
    fontSize: CGFloat
  ) -> CGPath {
    let rect = rect.standardized
    guard rect.width > 0, rect.height > 0 else { return CGMutablePath() }
    guard let tailTarget,
          let tail = tailGeometry(in: rect, requestedTarget: tailTarget, fontSize: fontSize) else {
      return CGPath(roundedRect: rect, cornerWidth: cornerRadius * 2, cornerHeight: cornerRadius * 2, transform: nil)
    }

    let radius = min(max(0, cornerRadius), min(rect.width, rect.height) / 2)
    let path = CGMutablePath()

    let topLeft = CGPoint(x: rect.minX + radius, y: rect.maxY)
    let topRight = CGPoint(x: rect.maxX - radius, y: rect.maxY)
    let rightTop = CGPoint(x: rect.maxX, y: rect.maxY - radius)
    let rightBottom = CGPoint(x: rect.maxX, y: rect.minY + radius)
    let bottomRight = CGPoint(x: rect.maxX - radius, y: rect.minY)
    let bottomLeft = CGPoint(x: rect.minX + radius, y: rect.minY)
    let leftBottom = CGPoint(x: rect.minX, y: rect.minY + radius)
    let leftTop = CGPoint(x: rect.minX, y: rect.maxY - radius)

    path.move(to: topLeft)
    appendEdge(from: topLeft, to: topRight, side: .maxY, tail: tail, path: path)
    path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius, startAngle: .pi / 2, endAngle: 0, clockwise: true)
    appendEdge(from: rightTop, to: rightBottom, side: .maxX, tail: tail, path: path)
    path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), radius: radius, startAngle: 0, endAngle: -.pi / 2, clockwise: true)
    appendEdge(from: bottomRight, to: bottomLeft, side: .minY, tail: tail, path: path)
    path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius), radius: radius, startAngle: -.pi / 2, endAngle: -.pi, clockwise: true)
    appendEdge(from: leftBottom, to: leftTop, side: .minX, tail: tail, path: path)
    path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), radius: radius, startAngle: .pi, endAngle: .pi / 2, clockwise: true)
    path.closeSubpath()
    return path
  }

  static func tailPath(in rect: CGRect, to requestedTarget: CGPoint, fontSize: CGFloat) -> CGPath {
    let rect = rect.standardized
    guard let tail = tailGeometry(in: rect, requestedTarget: requestedTarget, fontSize: fontSize) else {
      return CGMutablePath()
    }

    let path = CGMutablePath()
    path.move(to: tail.entry)
    appendTail(tail, to: path)
    path.closeSubpath()
    return path
  }

  private static func tailGeometry(
    in rect: CGRect,
    requestedTarget: CGPoint,
    fontSize: CGFloat
  ) -> TailGeometry? {
    guard rect.width > 0, rect.height > 0 else { return nil }

    let target = resolvedTailTarget(in: rect, requestedTarget: requestedTarget, fontSize: fontSize)
    // Bringing the target into the label restores the plain rounded rectangle.
    guard !rect.contains(target) else { return nil }
    let side = attachmentSide(for: target, in: rect)
    let baseHalfWidth = max(5, min(fontSize * 0.44, min(rect.width, rect.height) * 0.2))
    let anchor = attachmentPoint(for: target, on: side, in: rect, baseHalfWidth: baseHalfWidth)
    let basis = basis(for: side)
    let distance = hypot(target.x - anchor.x, target.y - anchor.y)
    guard distance > 1 else { return nil }

    // The root width stays compact while dragging; the visual transition from
    // short label point to long guide comes from the same pair of Bezier walls.
    let shortTailLimit = max(fontSize * 1.25, min(rect.width, rect.height) * 0.55)
    let rootHalfWidth = baseHalfWidth * (distance > shortTailLimit ? 1.1 : 1)
    return TailGeometry(
      side: side,
      target: target,
      entry: anchor - basis.tangent * rootHalfWidth,
      exit: anchor + basis.tangent * rootHalfWidth,
      tangent: basis.tangent,
      rootHalfWidth: rootHalfWidth
    )
  }

  private static func appendEdge(
    from start: CGPoint,
    to end: CGPoint,
    side: TailSide,
    tail: TailGeometry,
    path: CGMutablePath
  ) {
    guard tail.side == side else {
      path.addLine(to: end)
      return
    }
    path.addLine(to: tail.entry)
    appendTail(tail, to: path)
    path.addLine(to: end)
  }

  private static func appendTail(_ tail: TailGeometry, to path: CGMutablePath) {
    let intoTip = normalized(tail.target - tail.entry)
    let outOfTip = normalized(tail.exit - tail.target)
    let tipInset = min(
      max(tail.rootHalfWidth * 0.7, 2),
      hypot(tail.target.x - tail.entry.x, tail.target.y - tail.entry.y) * 0.24
    )
    let rootControl = min(
      tail.rootHalfWidth * 0.9,
      hypot(tail.target.x - tail.entry.x, tail.target.y - tail.entry.y) * 0.3
    )

    path.addCurve(
      to: tail.target,
      control1: tail.entry + tail.tangent * rootControl,
      control2: tail.target - intoTip * tipInset
    )
    path.addCurve(
      to: tail.exit,
      control1: tail.target + outOfTip * tipInset,
      control2: tail.exit - tail.tangent * rootControl
    )
  }

  private static func attachmentSide(for target: CGPoint, in rect: CGRect) -> TailSide {
    let normalizedX = (target.x - rect.midX) / max(rect.width / 2, 1)
    let normalizedY = (target.y - rect.midY) / max(rect.height / 2, 1)
    if abs(normalizedX) > abs(normalizedY) {
      return normalizedX < 0 ? .minX : .maxX
    }
    return normalizedY < 0 ? .minY : .maxY
  }

  private static func attachmentPoint(
    for target: CGPoint,
    on side: TailSide,
    in rect: CGRect,
    baseHalfWidth: CGFloat
  ) -> CGPoint {
    let inset = min(
      max(baseHalfWidth + 2, cornerRadius(in: rect, fontSize: baseHalfWidth * 2)),
      min(rect.width, rect.height) * 0.42
    )
    switch side {
    case .minX:
      return CGPoint(x: rect.minX, y: min(max(target.y, rect.minY + inset), rect.maxY - inset))
    case .maxX:
      return CGPoint(x: rect.maxX, y: min(max(target.y, rect.minY + inset), rect.maxY - inset))
    case .minY:
      return CGPoint(x: min(max(target.x, rect.minX + inset), rect.maxX - inset), y: rect.minY)
    case .maxY:
      return CGPoint(x: min(max(target.x, rect.minX + inset), rect.maxX - inset), y: rect.maxY)
    }
  }

  private static func basis(for side: TailSide) -> (outward: CGPoint, tangent: CGPoint) {
    switch side {
    case .minX: (CGPoint(x: -1, y: 0), CGPoint(x: 0, y: 1))
    case .maxX: (CGPoint(x: 1, y: 0), CGPoint(x: 0, y: -1))
    case .minY: (CGPoint(x: 0, y: -1), CGPoint(x: -1, y: 0))
    case .maxY: (CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 0))
    }
  }
}

private func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
  CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}

private func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
  CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}

private func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
  CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
}

private func normalized(_ point: CGPoint) -> CGPoint {
  let length = hypot(point.x, point.y)
  guard length > 0.0001 else { return .zero }
  return point * (1 / length)
}

enum ArrowStyle: String, CaseIterable, Identifiable, Equatable {
  case straight
  case curvedRight
  case curvedLeft

  var id: String {
    rawValue
  }

  var supportsBendDirection: Bool {
    switch self {
    case .straight: false
    case .curvedRight, .curvedLeft: true
    }
  }

  var displayName: String {
    switch self {
    case .straight: L10n.AnnotateUI.straight
    case .curvedRight: L10n.AnnotateUI.curvedRight
    case .curvedLeft: L10n.AnnotateUI.curvedLeft
    }
  }

  var icon: String {
    switch self {
    case .straight: "arrow.up.right"
    case .curvedRight: "arrowshape.turn.up.right"
    case .curvedLeft: "arrowshape.turn.up.left"
    }
  }

  var helperText: String {
    switch self {
    case .straight: L10n.AnnotateUI.straightArrowHelp
    case .curvedRight: L10n.AnnotateUI.curvedRightArrowHelp
    case .curvedLeft: L10n.AnnotateUI.curvedLeftArrowHelp
    }
  }

  init?(rawValue: String) {
    switch rawValue {
    case "straight": self = .straight
    case "curvedRight": self = .curvedRight
    case "curvedLeft": self = .curvedLeft
    case "curve", "elbow": self = .curvedRight // Legacy compatibility mapping
    default: return nil
    }
  }
}

enum ArrowBendDirection: String, CaseIterable, Identifiable, Equatable {
  case primary
  case alternate

  var id: String {
    rawValue
  }

  var displayName: String {
    switch self {
    case .primary: L10n.AnnotateUI.arrowBendNormal
    case .alternate: L10n.AnnotateUI.arrowBendReversed
    }
  }

  var icon: String {
    switch self {
    case .primary: "arrow.uturn.right"
    case .alternate: "arrow.uturn.left"
    }
  }

  var toggled: ArrowBendDirection {
    switch self {
    case .primary: .alternate
    case .alternate: .primary
    }
  }
}

enum ArrowType: String, Codable, CaseIterable, Identifiable {
  case classic
  case tapered
  case outlined

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .classic: return L10n.AnnotateUI.arrowTypeClassic
    case .tapered: return L10n.AnnotateUI.arrowTypeTapered
    case .outlined: return L10n.AnnotateUI.arrowTypeOutlined
    }
  }

  var icon: String {
    switch self {
    case .classic: return "arrow.up.right"
    case .tapered: return "arrowshape.turn.up.right"
    case .outlined: return "arrowshape.turn.up.right.fill"
    }
  }

  func icon(for style: ArrowStyle) -> String {
    switch style {
    case .straight:
      switch self {
      case .classic: return "arrow.up.right"
      case .tapered: return "arrowshape.turn.up.right"
      case .outlined: return "arrowshape.turn.up.right.fill"
      }
    case .curvedRight:
      switch self {
      case .classic: return "arrow.turn.up.right"
      case .tapered: return "arrowshape.turn.up.right"
      case .outlined: return "arrowshape.turn.up.right.fill"
      }
    case .curvedLeft:
      switch self {
      case .classic: return "arrow.turn.up.left"
      case .tapered: return "arrowshape.turn.up.left"
      case .outlined: return "arrowshape.turn.up.left.fill"
      }
    }
  }
}

/// Decoration drawn at a single arrow endpoint (start or end).
/// Applies to the `.classic` display type; tapered/outlined bake their head into the body.
enum ArrowEndpointStyle: String, CaseIterable, Identifiable, Equatable {
  case none
  case arrow
  case circle

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .none: L10n.AnnotateUI.arrowHeadNone
    case .arrow: L10n.AnnotateUI.arrowHeadArrow
    case .circle: L10n.AnnotateUI.arrowHeadCircle
    }
  }

  var icon: String {
    switch self {
    case .none: "minus"
    case .arrow: "arrowtriangle.right.fill"
    case .circle: "circle.fill"
    }
  }
}

struct ArrowGeometry: Equatable {
  var start: CGPoint
  var end: CGPoint
  var style: ArrowStyle
  var controlPoint: CGPoint?
  var arrowType: ArrowType
  var startHead: ArrowEndpointStyle
  var endHead: ArrowEndpointStyle

  struct TaperedArrowMetrics: Equatable {
    /// Shaft width at the tail (start).
    let shaftBaseWidth: CGFloat
    /// Shaft width where it meets the head (neck).
    let shaftNeckWidth: CGFloat
    /// Full width of the triangular head.
    let headWidth: CGFloat
    /// Length of the head along the centerline.
    let headLength: CGFloat
    /// Visible outer outline thickness for `.outlined` (true outside edge).
    let outlineWidth: CGFloat
    /// How far the head base is pulled back along the tangent (barb depth).
    let sweepBack: CGFloat

    /// Max half-width used for hit testing / selection padding.
    var maxHalfWidth: CGFloat {
      max(shaftBaseWidth, headWidth) / 2
    }
  }

  /// Shared dimension model so geometry, rendering, and hit-testing stay in sync.
  /// Same presentation silhouette (thin tail widening to the neck, ~2× head, shallow
  /// shoulders, white border); neck width tracks strokeWidth so visual weight matches
  /// other tools (e.g. rectangle).
  static func taperedMetrics(strokeWidth: CGFloat, chordLength: CGFloat) -> TaperedArrowMetrics {
    let safeStroke = max(strokeWidth, 1)
    // Mild length scale only — avoid oversized bodies on long drags.
    let scale = min(1.08, max(0.75, chordLength / 180))

    // Neck (just behind the head) carries the visual weight ≈ other annotate tools' stroke.
    let shaftNeck = (2.6 + safeStroke * 1.75) * scale
    // Shaft widens from a thin tail up to the neck: narrow at the tail → wide at
    // the head, so the body fans out toward the arrowhead (never thin at the tip).
    let shaftBase = shaftNeck * 0.5
    // Head ~2× the neck width with clear but shallow shoulders.
    let headWidth = max(shaftNeck * 2.0, shaftNeck + 5.5 * scale)
    let idealHeadLength = (9.0 + safeStroke * 2.2) * scale
    // Cap head so short arrows still keep a visible shaft.
    let headLength = min(max(idealHeadLength, shaftNeck * 1.1), chordLength * 0.32)
    // Outline scales with stroke; stays readable without overpowering thin bodies.
    let outlineWidth = max(1.5, 1.1 + safeStroke * 0.32)
    // Shallow sweep — soft shoulders, not deep barbs.
    let sweepBack = headLength * 0.10

    return TaperedArrowMetrics(
      shaftBaseWidth: shaftBase,
      shaftNeckWidth: shaftNeck,
      headWidth: headWidth,
      headLength: headLength,
      outlineWidth: outlineWidth,
      sweepBack: sweepBack
    )
  }

  func taperedMetrics(strokeWidth: CGFloat) -> TaperedArrowMetrics {
    let dx = end.x - start.x
    let dy = end.y - start.y
    return Self.taperedMetrics(strokeWidth: strokeWidth, chordLength: hypot(dx, dy))
  }

  init(
    start: CGPoint,
    end: CGPoint,
    style: ArrowStyle,
    bendDirection: ArrowBendDirection = .primary,
    controlPoint: CGPoint? = nil,
    arrowType: ArrowType = .tapered,
    startHead: ArrowEndpointStyle = .none,
    endHead: ArrowEndpointStyle = .arrow
  ) {
    self.start = start
    self.end = end
    self.style = style
    self.arrowType = arrowType
    self.startHead = startHead
    self.endHead = endHead

    // Calculate resolvedDirection for normalizedControlPoint:
    let resolvedDirection: ArrowBendDirection = (style == .curvedLeft) ? .primary : .alternate
    
    self.controlPoint = Self.normalizedControlPoint(
      start: start,
      end: end,
      style: style,
      bendDirection: resolvedDirection,
      current: controlPoint
    )
  }

  var resolvedControlPoint: CGPoint? {
    let resolvedDirection: ArrowBendDirection = (style == .curvedLeft) ? .primary : .alternate
    return Self.normalizedControlPoint(
      start: start,
      end: end,
      style: style,
      bendDirection: resolvedDirection,
      current: controlPoint
    )
  }

  var bendDirection: ArrowBendDirection {
    switch style {
    case .straight:
      return .primary
    case .curvedRight:
      return .alternate
    case .curvedLeft:
      return .primary
    }
  }

  var isRenderable: Bool {
    let points = sampledPoints()
    guard let first = points.first else { return false }
    return points.dropFirst().contains { $0 != first }
  }

  func path() -> CGPath {
    let path = CGMutablePath()
    path.move(to: start)

    switch style {
    case .straight:
      path.addLine(to: end)

    case .curvedRight, .curvedLeft:
      if let control = resolvedControlPoint {
        path.addQuadCurve(to: end, control: control)
      } else {
        path.addLine(to: end)
      }
    }

    return path
  }

  /// Closed filled path for tapered / outlined arrow display types.
  /// Shape: thin rounded tail → shaft widening toward the neck → triangular head with slight barbs.
  func taperedArrowPath(strokeWidth: CGFloat) -> CGPath {
    let path = CGMutablePath()

    let dx = end.x - start.x
    let dy = end.y - start.y
    let chordLength = hypot(dx, dy)
    guard chordLength > 1 else { return path }

    let metrics = Self.taperedMetrics(strokeWidth: strokeWidth, chordLength: chordLength)
    let wStart = metrics.shaftBaseWidth
    let wEnd = metrics.shaftNeckWidth
    let wHead = metrics.headWidth
    let resolvedHeadLength = metrics.headLength

    // Sample centerline points and unit tangents (supports straight + quadratic curves).
    let steps = 48
    var points: [CGPoint] = []
    var tangents: [CGPoint] = []
    points.reserveCapacity(steps + 1)
    tangents.reserveCapacity(steps + 1)

    for i in 0...steps {
      let t = CGFloat(i) / CGFloat(steps)
      let p: CGPoint
      let tangent: CGPoint

      if style != .straight, let control = resolvedControlPoint {
        let oneMinusT = 1.0 - t
        p = CGPoint(
          x: oneMinusT * oneMinusT * start.x + 2 * oneMinusT * t * control.x + t * t * end.x,
          y: oneMinusT * oneMinusT * start.y + 2 * oneMinusT * t * control.y + t * t * end.y
        )
        let tx = 2 * oneMinusT * (control.x - start.x) + 2 * t * (end.x - control.x)
        let ty = 2 * oneMinusT * (control.y - start.y) + 2 * t * (end.y - control.y)
        tangent = CGPoint(x: tx, y: ty)
      } else {
        p = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        tangent = CGPoint(x: dx, y: dy)
      }

      points.append(p)

      let len = hypot(tangent.x, tangent.y)
      if len > 0.0001 {
        tangents.append(CGPoint(x: tangent.x / len, y: tangent.y / len))
      } else if let lastTangent = tangents.last {
        tangents.append(lastTangent)
      } else {
        tangents.append(CGPoint(x: dx / max(chordLength, 1), y: dy / max(chordLength, 1)))
      }
    }

    // Neck = point on the centerline one headLength back from the tip.
    var neckIndex = steps
    var accumulatedDistance: CGFloat = 0
    for i in stride(from: steps, to: 0, by: -1) {
      accumulatedDistance += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
      if accumulatedDistance >= resolvedHeadLength {
        neckIndex = max(i - 1, 1)
        break
      }
    }
    if neckIndex < 1 { neckIndex = 1 }

    let neckPoint = points[neckIndex]
    let neckTangent = tangents[neckIndex]
    let neckNormal = CGPoint(x: -neckTangent.y, y: neckTangent.x)

    // Head base is swept slightly behind the neck so the shaft forms clear shoulders.
    let arrowheadBaseCenter = CGPoint(
      x: neckPoint.x - neckTangent.x * metrics.sweepBack,
      y: neckPoint.y - neckTangent.y * metrics.sweepBack
    )
    let headLeft = CGPoint(
      x: arrowheadBaseCenter.x + neckNormal.x * (wHead / 2),
      y: arrowheadBaseCenter.y + neckNormal.y * (wHead / 2)
    )
    let headRight = CGPoint(
      x: arrowheadBaseCenter.x - neckNormal.x * (wHead / 2),
      y: arrowheadBaseCenter.y - neckNormal.y * (wHead / 2)
    )

    // Smooth ease for shaft taper (matches solid presentation look, not a linear wedge).
    func shaftWidth(progress: CGFloat) -> CGFloat {
      let eased = progress * progress * (3 - 2 * progress) // smoothstep
      return wStart + (wEnd - wStart) * eased
    }

    var leftShaftPoints: [CGPoint] = []
    var rightShaftPoints: [CGPoint] = []
    leftShaftPoints.reserveCapacity(neckIndex + 1)
    rightShaftPoints.reserveCapacity(neckIndex + 1)

    for i in 0...neckIndex {
      let progress = CGFloat(i) / CGFloat(neckIndex)
      let halfW = shaftWidth(progress: progress) / 2
      let p = points[i]
      let norm = CGPoint(x: -tangents[i].y, y: tangents[i].x)
      leftShaftPoints.append(CGPoint(x: p.x + norm.x * halfW, y: p.y + norm.y * halfW))
      rightShaftPoints.append(CGPoint(x: p.x - norm.x * halfW, y: p.y - norm.y * halfW))
    }

    // Closed outline: tip → left wing → left shaft → rounded tail → right shaft → right wing → tip
    path.move(to: end)
    path.addLine(to: headLeft)
    path.addLine(to: leftShaftPoints[neckIndex])
    for i in stride(from: neckIndex - 1, through: 0, by: -1) {
      path.addLine(to: leftShaftPoints[i])
    }

    let tailNormal = CGPoint(x: -tangents[0].y, y: tangents[0].x)
    let startAngle = atan2(tailNormal.y, tailNormal.x)
    path.addArc(
      center: start,
      radius: wStart / 2,
      startAngle: startAngle,
      endAngle: startAngle + .pi,
      clockwise: false
    )

    for i in 0...neckIndex {
      path.addLine(to: rightShaftPoints[i])
    }
    path.addLine(to: headRight)
    path.closeSubpath()

    return path
  }

  func sampledPoints(curveSegments: Int = 16) -> [CGPoint] {
    switch style {
    case .straight:
      return deduplicated([start, end])

    case .curvedRight, .curvedLeft:
      guard let control = resolvedControlPoint else {
        return deduplicated([start, end])
      }

      var points: [CGPoint] = []
      points.reserveCapacity(curveSegments + 1)

      for segment in 0 ... curveSegments {
        let t = CGFloat(segment) / CGFloat(curveSegments)
        let oneMinusT = 1 - t
        let point = CGPoint(
          x: oneMinusT * oneMinusT * start.x + 2 * oneMinusT * t * control.x + t * t * end.x,
          y: oneMinusT * oneMinusT * start.y + 2 * oneMinusT * t * control.y + t * t * end.y
        )
        points.append(point)
      }

      return deduplicated(points)
    }
  }

  func tangentAngleAtEnd() -> CGFloat {
    switch style {
    case .straight:
      return atan2(end.y - start.y, end.x - start.x)

    case .curvedRight, .curvedLeft:
      if let control = resolvedControlPoint, control != end {
        return atan2(end.y - control.y, end.x - control.x)
      }
      return atan2(end.y - start.y, end.x - start.x)
    }
  }

  /// Outward tangent angle at the start point (pointing away from the arrow body).
  func tangentAngleAtStart() -> CGFloat {
    switch style {
    case .straight:
      return atan2(start.y - end.y, start.x - end.x)

    case .curvedRight, .curvedLeft:
      if let control = resolvedControlPoint, control != start {
        return atan2(start.y - control.y, start.x - control.x)
      }
      return atan2(start.y - end.y, start.x - end.x)
    }
  }

  func bounds() -> CGRect {
    let points = sampledPoints()
    guard let first = points.first else { return CGRect(x: start.x, y: start.y, width: 1, height: 1) }

    var minX = first.x
    var maxX = first.x
    var minY = first.y
    var maxY = first.y

    for point in points.dropFirst() {
      minX = min(minX, point.x)
      maxX = max(maxX, point.x)
      minY = min(minY, point.y)
      maxY = max(maxY, point.y)
    }

    var rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).standardized
    if rect.width < 1 {
      rect.origin.x -= (1 - rect.width) / 2
      rect.size.width = 1
    }
    if rect.height < 1 {
      rect.origin.y -= (1 - rect.height) / 2
      rect.size.height = 1
    }
    return rect
  }

  func translatedBy(dx: CGFloat, dy: CGFloat) -> ArrowGeometry {
    ArrowGeometry(
      start: CGPoint(x: start.x + dx, y: start.y + dy),
      end: CGPoint(x: end.x + dx, y: end.y + dy),
      style: style,
      controlPoint: resolvedControlPoint.map { CGPoint(x: $0.x + dx, y: $0.y + dy) },
      arrowType: arrowType,
      startHead: startHead,
      endHead: endHead
    )
  }

  func remapped(from oldBounds: CGRect, to newBounds: CGRect) -> ArrowGeometry {
    ArrowGeometry(
      start: Self.remap(point: start, from: oldBounds, to: newBounds),
      end: Self.remap(point: end, from: oldBounds, to: newBounds),
      style: style,
      controlPoint: resolvedControlPoint.map { Self.remap(point: $0, from: oldBounds, to: newBounds) },
      arrowType: arrowType,
      startHead: startHead,
      endHead: endHead
    )
  }

  func withStyle(_ newStyle: ArrowStyle) -> ArrowGeometry {
    if newStyle == style {
      return self
    }
    
    let newControlPoint: CGPoint?
    if newStyle == .straight {
      newControlPoint = nil
    } else if style == .straight {
      let resolvedDirection: ArrowBendDirection = (newStyle == .curvedLeft) ? .primary : .alternate
      newControlPoint = Self.defaultCurveControlPoint(start: start, end: end, bendDirection: resolvedDirection)
    } else {
      newControlPoint = resolvedControlPoint.map { Self.mirroredControlPoint($0, start: start, end: end) }
    }
    
    let resolvedDirection: ArrowBendDirection = (newStyle == .curvedLeft) ? .primary : .alternate
    return ArrowGeometry(
      start: start,
      end: end,
      style: newStyle,
      bendDirection: resolvedDirection,
      controlPoint: newControlPoint,
      arrowType: arrowType,
      startHead: startHead,
      endHead: endHead
    )
  }

  func withBendDirection(_ newDirection: ArrowBendDirection) -> ArrowGeometry {
    guard style.supportsBendDirection else { return self }
    
    let newStyle: ArrowStyle
    if style == .curvedRight {
      newStyle = .curvedLeft
    } else if style == .curvedLeft {
      newStyle = .curvedRight
    } else {
      newStyle = style
    }

    let resolvedDirection: ArrowBendDirection = (newStyle == .curvedLeft) ? .primary : .alternate
    let newControlPoint = resolvedControlPoint
      .map { Self.mirroredControlPoint($0, start: start, end: end) }
      ?? Self.defaultCurveControlPoint(start: start, end: end, bendDirection: resolvedDirection)
    return ArrowGeometry(start: start, end: end, style: newStyle, bendDirection: resolvedDirection, controlPoint: newControlPoint, arrowType: arrowType, startHead: startHead, endHead: endHead)
  }

  func withArrowType(_ newType: ArrowType) -> ArrowGeometry {
    ArrowGeometry(start: start, end: end, style: style, bendDirection: bendDirection, controlPoint: controlPoint, arrowType: newType, startHead: startHead, endHead: endHead)
  }

  func withStartHead(_ newHead: ArrowEndpointStyle) -> ArrowGeometry {
    ArrowGeometry(start: start, end: end, style: style, bendDirection: bendDirection, controlPoint: controlPoint, arrowType: arrowType, startHead: newHead, endHead: endHead)
  }

  func withEndHead(_ newHead: ArrowEndpointStyle) -> ArrowGeometry {
    ArrowGeometry(start: start, end: end, style: style, bendDirection: bendDirection, controlPoint: controlPoint, arrowType: arrowType, startHead: startHead, endHead: newHead)
  }

  private static func normalizedControlPoint(
    start: CGPoint,
    end: CGPoint,
    style: ArrowStyle,
    bendDirection: ArrowBendDirection,
    current: CGPoint?
  ) -> CGPoint? {
    switch style {
    case .straight:
      return nil
    case .curvedRight, .curvedLeft:
      return current ?? defaultCurveControlPoint(start: start, end: end, bendDirection: bendDirection)
    }
  }

  private static func inferredBendDirection(
    start: CGPoint,
    end: CGPoint,
    style: ArrowStyle,
    controlPoint: CGPoint?
  ) -> ArrowBendDirection {
    guard style.supportsBendDirection,
          let controlPoint else {
      return .primary
    }

    switch style {
    case .straight:
      return .primary

    case .curvedRight, .curvedLeft:
      let dx = end.x - start.x
      let dy = end.y - start.y
      let length = hypot(dx, dy)
      guard length > 0.0001 else { return .primary }

      let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
      let normal = CGPoint(x: -dy / length, y: dx / length)
      let offsetFromMidpoint = CGPoint(x: controlPoint.x - mid.x, y: controlPoint.y - mid.y)
      let side = offsetFromMidpoint.x * normal.x + offsetFromMidpoint.y * normal.y
      return side < 0 ? .alternate : .primary
    }
  }

  private static func defaultCurveControlPoint(
    start: CGPoint,
    end: CGPoint,
    bendDirection: ArrowBendDirection
  ) -> CGPoint {
    let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = max(hypot(dx, dy), 1)
    let normal = CGPoint(x: -dy / length, y: dx / length)
    let offsetMagnitude = min(max(length * 0.22, 18), 72)
    let offset = bendDirection == .primary ? offsetMagnitude : -offsetMagnitude
    return CGPoint(
      x: mid.x + normal.x * offset,
      y: mid.y + normal.y * offset
    )
  }

  private static func distanceSquared(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
    let dx = lhs.x - rhs.x
    let dy = lhs.y - rhs.y
    return dx * dx + dy * dy
  }

  private static func mirroredControlPoint(_ controlPoint: CGPoint, start: CGPoint, end: CGPoint) -> CGPoint {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0.0001 else {
      return controlPoint
    }

    let progress = ((controlPoint.x - start.x) * dx + (controlPoint.y - start.y) * dy) / lengthSquared
    let projectedPoint = CGPoint(x: start.x + progress * dx, y: start.y + progress * dy)
    return CGPoint(
      x: projectedPoint.x * 2 - controlPoint.x,
      y: projectedPoint.y * 2 - controlPoint.y
    )
  }

  private static func remap(point: CGPoint, from oldBounds: CGRect, to newBounds: CGRect) -> CGPoint {
    CGPoint(
      x: remapCoordinate(
        point.x,
        oldMin: oldBounds.minX,
        oldSize: oldBounds.width,
        newMin: newBounds.minX,
        newSize: newBounds.width
      ),
      y: remapCoordinate(
        point.y,
        oldMin: oldBounds.minY,
        oldSize: oldBounds.height,
        newMin: newBounds.minY,
        newSize: newBounds.height
      )
    )
  }

  private static func remapCoordinate(
    _ value: CGFloat,
    oldMin: CGFloat,
    oldSize: CGFloat,
    newMin: CGFloat,
    newSize: CGFloat
  ) -> CGFloat {
    guard oldSize != 0 else {
      return newMin + newSize / 2
    }

    let progress = (value - oldMin) / oldSize
    return newMin + progress * newSize
  }

  private func deduplicated(_ points: [CGPoint]) -> [CGPoint] {
    var result: [CGPoint] = []
    result.reserveCapacity(points.count)

    for point in points where result.last != point {
      result.append(point)
    }

    return result
  }
}

/// Single annotation element on the canvas
struct AnnotationItem: Identifiable, Equatable {
  let id: UUID
  var type: AnnotationType
  var bounds: CGRect
  var properties: AnnotationProperties

  init(id: UUID = UUID(), type: AnnotationType, bounds: CGRect, properties: AnnotationProperties) {
    self.id = id
    self.type = type
    self.bounds = bounds
    self.properties = properties
  }

  static func == (lhs: AnnotationItem, rhs: AnnotationItem) -> Bool {
    lhs.id == rhs.id
  }
}

/// Types of annotations
enum AnnotationType: Equatable {
  case path([CGPoint])
  case rectangle
  case filledRectangle
  case oval
  case arrow(ArrowGeometry)
  case line(start: CGPoint, end: CGPoint)
  case text(String)
  case highlight([CGPoint])
  case blur(BlurType)
  case counter(Int)
  case watermark(String)
  case embeddedImage(UUID)
  case spotlight

  /// Corresponding toolbar tool type for this annotation
  var toolType: AnnotationToolType {
    switch self {
    case .path: .pencil
    case .rectangle: .rectangle
    case .filledRectangle: .filledRectangle
    case .oval: .oval
    case .arrow: .arrow
    case .line: .line
    case .text: .text
    case .highlight: .highlighter
    case .blur: .blur
    case .counter: .counter
    case .watermark: .watermark
    case .embeddedImage: .selection
    case .spotlight: .spotlight
    }
  }

  /// Whether this annotation type exposes the standard property sidebar controls.
  var supportsPropertyEditing: Bool {
    switch self {
    case .embeddedImage:
      false
    default:
      true
    }
  }

  var supportsQuickPropertiesBar: Bool {
    supportsPropertyEditing && toolType.supportsQuickPropertiesBar
  }

  var supportsQuickStrokeColor: Bool {
    supportsQuickPropertiesBar && toolType.supportsQuickStrokeColor
  }

  var supportsQuickFillColor: Bool {
    supportsQuickPropertiesBar && toolType.supportsQuickFillColor
  }

  var supportsQuickStrokeWidth: Bool {
    supportsQuickPropertiesBar && toolType.supportsQuickStrokeWidth
  }
}

/// Visual properties for an annotation
struct AnnotationProperties: Equatable {
  static let controlValueRange: ClosedRange<CGFloat> = 1 ... 20

  var strokeColor: Color
  var fillColor: Color
  var strokeWidth: CGFloat
  var cornerRadius: CGFloat
  var fontSize: CGFloat
  var fontName: String
  var opacity: CGFloat
  var rotationDegrees: CGFloat
  var watermarkStyle: WatermarkStyle
  var spotlightOpacity: CGFloat
  var textPresentation: TextPresentation
  var calloutTailTarget: CGPoint?

  init(
    strokeColor: Color = .red,
    fillColor: Color = .clear,
    strokeWidth: CGFloat = 3,
    cornerRadius: CGFloat = 0,
    fontSize: CGFloat = 16,
    fontName: String = "SF Pro",
    opacity: CGFloat = 1,
    rotationDegrees: CGFloat = 0,
    watermarkStyle: WatermarkStyle = .single,
    spotlightOpacity: CGFloat = 0.5,
    textPresentation: TextPresentation = .plain,
    calloutTailTarget: CGPoint? = nil
  ) {
    self.strokeColor = strokeColor
    self.fillColor = fillColor
    self.strokeWidth = strokeWidth
    self.cornerRadius = cornerRadius
    self.fontSize = fontSize
    self.fontName = fontName
    self.opacity = opacity
    self.rotationDegrees = rotationDegrees
    self.watermarkStyle = watermarkStyle
    self.spotlightOpacity = spotlightOpacity
    self.textPresentation = textPresentation
    self.calloutTailTarget = calloutTailTarget
  }

  static func clampedControlValue(_ value: CGFloat) -> CGFloat {
    min(max(value, controlValueRange.lowerBound), controlValueRange.upperBound)
  }

  static func counterDiameter(for controlValue: CGFloat) -> CGFloat {
    12 + clampedControlValue(controlValue) * 4
  }

  static func controlValue(forCounterDiameter diameter: CGFloat) -> CGFloat {
    clampedControlValue((max(diameter, 16) - 12) / 4)
  }

  static func pixelatedBlurSize(for controlValue: CGFloat) -> CGFloat {
    6 + clampedControlValue(controlValue) * 2
  }

  static func gaussianBlurRadius(for controlValue: CGFloat) -> CGFloat {
    8 + clampedControlValue(controlValue) * 4
  }

  static func hexagonalScale(for controlValue: CGFloat) -> CGFloat {
    8 + clampedControlValue(controlValue) * 3
  }

  static func crystallizeRadius(for controlValue: CGFloat) -> CGFloat {
    10 + clampedControlValue(controlValue) * 4
  }

  static func pointillismRadius(for controlValue: CGFloat) -> CGFloat {
    8 + clampedControlValue(controlValue) * 3
  }

  static func halftoneWidth(for controlValue: CGFloat) -> CGFloat {
    6 + clampedControlValue(controlValue) * 2
  }

  static func tapePatternSpacing(for controlValue: CGFloat) -> CGFloat {
    8 + clampedControlValue(controlValue) * 2
  }

  static func washiPatternSpacing(for controlValue: CGFloat) -> CGFloat {
    8 + clampedControlValue(controlValue) * 2
  }

  static func clampedOpacity(_ value: CGFloat) -> CGFloat {
    min(max(value, 0.05), 0.65)
  }

  static func clampedSpotlightOpacity(_ value: CGFloat) -> CGFloat {
    min(max(value, 0.1), 0.9)
  }

  static func clampedRotationDegrees(_ value: CGFloat) -> CGFloat {
    min(max(value, -45), 45)
  }
}

// MARK: - Hit Testing

extension AnnotationItem {
  var supportsResize: Bool {
    switch type {
    case .path, .highlight:
      false
    default:
      true
    }
  }

  var resizeBounds: CGRect {
    switch type {
    case .arrow(let geometry):
      return geometry.bounds()
    case .line(let start, let end):
      return Self.normalizedBounds(Self.bounds(containing: [start, end]) ?? bounds)
    case .path(let points), .highlight(let points):
      return Self.normalizedBounds(Self.bounds(containing: points) ?? bounds)
    case .counter:
      let counterBounds = bounds.isEmpty ? Self.counterBounds(center: bounds.origin, properties: properties) : bounds
      return Self.normalizedBounds(counterBounds)
    default:
      return Self.normalizedBounds(bounds)
    }
  }

  var selectionBounds: CGRect {
    if case .highlight = type {
      return selectionDecorationBounds
    }

    let padding: CGFloat
    if case .arrow = type {
      padding = max(16, properties.strokeWidth * 3)
    } else {
      padding = max(6, properties.strokeWidth / 2)
    }
    var result = resizeBounds.insetBy(dx: -padding, dy: -padding)
    if case .text = type,
       properties.textPresentation == .callout,
       let tailTarget = properties.calloutTailTarget {
      let tailBounds = TextBubbleGeometry.tailPath(
        in: bounds,
        to: tailTarget,
        fontSize: properties.fontSize
      ).boundingBoxOfPath
      if !tailBounds.isNull {
        result = result.union(tailBounds.insetBy(dx: -padding, dy: -padding))
      }
    }
    return result
  }

  var selectionDecorationBounds: CGRect {
    switch type {
    case .highlight(let points):
      Self.highlighterSelectionBounds(
        containing: points,
        strokeWidth: properties.strokeWidth,
        fallback: resizeBounds
      )
    default:
      resizeBounds
    }
  }

  /// Check if point hits this annotation with appropriate tolerance
  func containsPoint(_ point: CGPoint, baseTolerance: CGFloat = 6) -> Bool {
    let tolerance = baseTolerance + properties.strokeWidth / 2

    switch type {
    case .rectangle, .filledRectangle, .blur(_), .watermark, .embeddedImage, .spotlight:
      return bounds.contains(point)

    case .oval:
      return pointInEllipse(point, in: bounds)

    case .arrow(let geometry):
      let maxArrowWidth = (3.2 + properties.strokeWidth * 2.0) * 1.2
      let arrowTolerance = baseTolerance + maxArrowWidth / 2
      return distanceToPolyline(point, points: geometry.sampledPoints()) <= arrowTolerance

    case .line(let start, let end):
      return distanceToSegment(point, from: start, to: end) <= tolerance

    case .path(let points), .highlight(let points):
      let adjustedTolerance = type.isHighlight ? tolerance * 3 : tolerance
      return distanceToPolyline(point, points: points) <= adjustedTolerance

    case .text:
      if bounds.contains(point) { return true }
      if properties.textPresentation == .callout,
         let tailTarget = properties.calloutTailTarget {
        return bounds.union(
          TextBubbleGeometry.tailPath(
            in: bounds,
            to: tailTarget,
            fontSize: properties.fontSize
          ).boundingBoxOfPath.insetBy(dx: -tolerance, dy: -tolerance)
        ).contains(point)
      }
      return false

    case .counter:
      let counterBounds = bounds.isEmpty ? Self.counterBounds(center: bounds.origin, properties: properties) : bounds
      return pointInEllipse(point, in: counterBounds.insetBy(dx: -baseTolerance, dy: -baseTolerance))
    }
  }

  // MARK: - Geometry Helpers

  private static func bounds(containing points: [CGPoint]) -> CGRect? {
    guard let first = points.first else { return nil }

    var minX = first.x
    var maxX = first.x
    var minY = first.y
    var maxY = first.y

    for point in points.dropFirst() {
      minX = min(minX, point.x)
      maxX = max(maxX, point.x)
      minY = min(minY, point.y)
      maxY = max(maxY, point.y)
    }

    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).standardized
  }

  private static func normalizedBounds(_ rect: CGRect, minimumDimension: CGFloat = 1) -> CGRect {
    var normalized = rect.standardized

    if normalized.width < minimumDimension {
      normalized.origin.x -= (minimumDimension - normalized.width) / 2
      normalized.size.width = minimumDimension
    }

    if normalized.height < minimumDimension {
      normalized.origin.y -= (minimumDimension - normalized.height) / 2
      normalized.size.height = minimumDimension
    }

    return normalized
  }

  private static func highlighterSelectionBounds(
    containing points: [CGPoint],
    strokeWidth: CGFloat,
    fallback: CGRect
  ) -> CGRect {
    let baseBounds = Self.normalizedBounds(Self.bounds(containing: points) ?? fallback)
    let visibleRadius = max(strokeWidth * 1.5, 1)
    let horizontalPadding = max(6, visibleRadius)
    let verticalPadding = max(6, visibleRadius + 4)
    var bounds = baseBounds.insetBy(dx: -horizontalPadding, dy: -verticalPadding)

    let minimumHeight = max(16, strokeWidth * 3 + 8)
    if bounds.height < minimumHeight {
      let delta = minimumHeight - bounds.height
      bounds.origin.y -= delta / 2
      bounds.size.height = minimumHeight
    }

    let minimumWidth = max(16, strokeWidth * 3)
    if bounds.width < minimumWidth {
      let delta = minimumWidth - bounds.width
      bounds.origin.x -= delta / 2
      bounds.size.width = minimumWidth
    }

    return bounds.standardized
  }

  private func pointInEllipse(_ point: CGPoint, in rect: CGRect) -> Bool {
    let cx = rect.midX
    let cy = rect.midY
    let rx = rect.width / 2
    let ry = rect.height / 2

    guard rx > 0, ry > 0 else { return false }

    let dx = (point.x - cx) / rx
    let dy = (point.y - cy) / ry
    return (dx * dx + dy * dy) <= 1
  }

  private static func counterBounds(center: CGPoint, properties: AnnotationProperties) -> CGRect {
    let diameter = AnnotationProperties.counterDiameter(for: properties.strokeWidth)
    return CGRect(
      x: center.x - diameter / 2,
      y: center.y - diameter / 2,
      width: diameter,
      height: diameter
    )
  }

  private func distanceToSegment(_ point: CGPoint, from start: CGPoint, to end: CGPoint) -> CGFloat {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = dx * dx + dy * dy

    guard lengthSquared > 0 else {
      return hypot(point.x - start.x, point.y - start.y)
    }

    // Project point onto line, clamped to segment
    var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
    t = max(0, min(1, t))

    let projX = start.x + t * dx
    let projY = start.y + t * dy

    return hypot(point.x - projX, point.y - projY)
  }

  private func distanceToPolyline(_ point: CGPoint, points: [CGPoint]) -> CGFloat {
    guard points.count >= 2 else {
      if let first = points.first {
        return hypot(point.x - first.x, point.y - first.y)
      }
      return .infinity
    }

    var minDistance: CGFloat = .infinity
    for i in 0 ..< (points.count - 1) {
      let dist = distanceToSegment(point, from: points[i], to: points[i + 1])
      minDistance = min(minDistance, dist)
    }
    return minDistance
  }
}