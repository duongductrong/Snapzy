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
nonisolated enum BlurType: String, CaseIterable, Identifiable, Equatable {
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

nonisolated enum WatermarkStyle: String, CaseIterable, Identifiable, Equatable {
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

nonisolated enum TextPresentation: String, CaseIterable, Identifiable, Equatable {
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
    case .plain: L10n.AnnotateUI.textPresentationPlain
    case .label: L10n.AnnotateUI.textPresentationLabel
    case .callout: L10n.AnnotateUI.textPresentationCallout
    }
  }
}

/// Shared proportions for label and callout text. Keeping these in one place
/// makes the editing overlay, on-canvas preview, and exported image agree.
nonisolated enum TextBubbleGeometry {
  /// One rounded corner of the outline, in the y-up space the bubble is built in
  /// (`maxY` is the top edge).
  ///
  /// Corners are traversed clockwise, i.e. from `startAngle` down to
  /// `endAngle == startAngle - 90°`, so the forward direction along an arc at
  /// angle `a` is `(sin a, -cos a)` — the same convention as `basis(for:)`. That
  /// is what lets a tail rooted in an arc leave the wall the way a mid-edge tail
  /// does.
  private enum Corner {
    case topRight
    case bottomRight
    case bottomLeft
    case topLeft

    /// Angle this arc begins at, where the preceding edge hands over.
    var startAngle: CGFloat {
      switch self {
      case .topRight: .pi / 2
      case .bottomRight: 0
      case .bottomLeft: -.pi / 2
      case .topLeft: .pi
      }
    }

    /// Angle this arc ends at, where the following edge takes over.
    var endAngle: CGFloat { startAngle - .pi / 2 }

    /// The arc's bisector: the outward diagonal a corner-rooted tail is confined
    /// around.
    var midAngle: CGFloat { startAngle - .pi / 4 }

    func center(in rect: CGRect, radius: CGFloat) -> CGPoint {
      switch self {
      case .topRight: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius)
      case .bottomRight: CGPoint(x: rect.maxX - radius, y: rect.minY + radius)
      case .bottomLeft: CGPoint(x: rect.minX + radius, y: rect.minY + radius)
      case .topLeft: CGPoint(x: rect.minX + radius, y: rect.maxY - radius)
      }
    }

    func point(in rect: CGRect, radius: CGFloat, at angle: CGFloat) -> CGPoint {
      let center = center(in: rect, radius: radius)
      return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    /// Point this arc begins at.
    func start(in rect: CGRect, radius: CGFloat) -> CGPoint {
      point(in: rect, radius: radius, at: startAngle)
    }

    /// Point this arc ends at.
    func end(in rect: CGRect, radius: CGFloat) -> CGPoint {
      point(in: rect, radius: radius, at: endAngle)
    }

    static func tangent(at angle: CGFloat) -> CGPoint {
      CGPoint(x: sin(angle), y: -cos(angle))
    }
  }

  private enum TailSide {
    case minX
    case maxX
    case minY
    case maxY

    /// Corner this side leaves, in traversal order.
    var upstreamCorner: Corner {
      switch self {
      case .maxY: .topLeft
      case .maxX: .topRight
      case .minY: .bottomRight
      case .minX: .bottomLeft
      }
    }

    /// Corner this side runs into, in traversal order.
    var downstreamCorner: Corner {
      switch self {
      case .maxY: .topRight
      case .maxX: .bottomRight
      case .minY: .bottomLeft
      case .minX: .topLeft
      }
    }

    /// `true` when this side runs vertically, so its length is `rect.height`.
    var isVertical: Bool {
      switch self {
      case .minX, .maxX: true
      case .minY, .maxY: false
      }
    }

    /// Point this side starts at: where the upstream corner's arc ends.
    func start(in rect: CGRect, radius: CGFloat) -> CGPoint {
      upstreamCorner.end(in: rect, radius: radius)
    }

    /// Point this side ends at: where the downstream corner's arc begins.
    func end(in rect: CGRect, radius: CGFloat) -> CGPoint {
      downstreamCorner.start(in: rect, radius: radius)
    }

    /// The corner at the target's end of this side, i.e. the arc that hosts the
    /// tail when the straight span is too short to hold its root. The two tangent
    /// points of a side straddle the rect's midline, so that midline is the
    /// boundary, and the pick depends on the target alone.
    func corner(nearest target: CGPoint, in rect: CGRect) -> Corner {
      switch self {
      case .maxX: target.y >= rect.midY ? .topRight : .bottomRight
      case .minX: target.y >= rect.midY ? .topLeft : .bottomLeft
      case .maxY: target.x >= rect.midX ? .topRight : .topLeft
      case .minY: target.x >= rect.midX ? .bottomRight : .bottomLeft
      }
    }
  }

  /// Half-angle of a growing tail near its root, as a slope. A tail widens with
  /// length until `maxRootHalfWidth` caps it, which keeps a short tail readable
  /// and stops a long one from narrowing into a needle.
  private static let tailApexSlope = CGFloat(tan(26 * Double.pi / 180))
  /// Hard ceiling on the root half-width, as a fraction of the shorter side.
  private static let maxRootHalfWidthRatio: CGFloat = 0.3
  /// How far a tail may lean away from the outward normal of the wall it leaves.
  ///
  /// Aiming a tail at its target is only worth so much: past this lean the tip
  /// sits nearly in line with its own root, so the tip angle is set by the lean
  /// rather than by the length and the wedge flattens back into the sliver the
  /// needle report was about — a long drag towards a corner, where the root is
  /// clamped well behind the target, is enough to get there. Bounding the lean
  /// is what makes the tip angle hold at every target, not just every length.
  private static let maxTailTilt = CGFloat(32 * Double.pi / 180)

  /// Tail numbers that do not depend on the bubble's corner radius. Split out
  /// because the resolved target is stored and re-resolved across font-size,
  /// preset and presentation changes, so it must not read anything
  /// radius-dependent.
  private struct CalloutTailLengths {
    /// Shortest tail: a target dragged up against the bubble still leaves a
    /// readable wedge instead of a dot.
    let minTailLength: CGFloat
    /// Longest tail: a distant target becomes a guide rather than a needle.
    let maxTailLength: CGFloat
    /// Root half-width of the shortest tail, and the floor under clamping.
    let baseHalfWidth: CGFloat
  }

  /// Every number the callout tail needs, derived once and read by the target
  /// resolver, the outline builder and the hit-test path so they cannot drift
  /// apart. Same shape as `ArrowGeometry.TaperedArrowMetrics`.
  private struct CalloutTailMetrics {
    let lengths: CalloutTailLengths
    /// Corner radius actually drawn, i.e. `resolvedCornerRadius`. A large stored
    /// radius is what makes the straight span disappear, so the tail has to know
    /// it.
    let radius: CGFloat
    /// Widest root half-width the drawn geometry may use. Already capped by
    /// whichever of the straight span and the corner arc has to host the root, so
    /// this clamp and `attachesAtCorner` read the same number and the attachment
    /// mode cannot flip as the tail grows mid-drag.
    let maxRootHalfWidth: CGFloat
    /// `true` when this side's straight span cannot hold `baseHalfWidth` clear of
    /// both corner arcs, so the root goes into a corner arc instead.
    let attachesAtCorner: Bool

    var minTailLength: CGFloat { lengths.minTailLength }
    var baseHalfWidth: CGFloat { lengths.baseHalfWidth }

    /// Reach the drawn tail may use.
    ///
    /// A tail is only as blunt as its root is wide for its length, and the root
    /// cannot outgrow the span hosting it, so the radius-free reach is capped at
    /// whatever `maxRootHalfWidth / tan(apex)` allows. Without this a large
    /// rounded bubble could still grow a needle: a wide corner pushes the root's
    /// anchor far along the edge, leaving a long tail with a root narrow for its
    /// length.
    ///
    /// The `minTailLength` floor keeps the interval ordered on a tiny bubble,
    /// where the span cap can land below the shortest tail.
    var maxTailLength: CGFloat {
      max(min(lengths.maxTailLength, maxRootHalfWidth / TextBubbleGeometry.tailApexSlope), minTailLength)
    }

    func rootHalfWidth(forTailLength length: CGFloat) -> CGFloat {
      min(max(length * TextBubbleGeometry.tailApexSlope, baseHalfWidth), maxRootHalfWidth)
    }
  }

  /// Where the tail leaves the bubble and which outline segment it replaces.
  private struct CalloutTail {
    /// Either the root sits on the straight span of `side`, or it replaces part
    /// of a corner arc.
    enum Root {
      case edge
      case corner(Corner, entryAngle: CGFloat, exitAngle: CGFloat)
    }

    let side: TailSide
    let root: Root
    let target: CGPoint
    let entry: CGPoint
    let exit: CGPoint
    /// Forward wall directions at `entry` and `exit`, used for the two root
    /// fillets. They differ when the root sits in an arc, so each fillet leaves
    /// the wall tangentially instead of one shared direction cutting into it.
    let entryTangent: CGPoint
    let exitTangent: CGPoint
    let rootHalfWidth: CGFloat
  }

  private static func calloutTailLengths(in rect: CGRect, fontSize: CGFloat) -> CalloutTailLengths {
    let shortestSide = min(rect.width, rect.height)
    return CalloutTailLengths(
      minTailLength: max(12, min(shortestSide * 0.35, fontSize * 0.9)),
      maxTailLength: min(shortestSide * 0.6, fontSize * 2.4),
      baseHalfWidth: max(5, min(fontSize * 0.44, shortestSide * 0.2))
    )
  }

  private static func calloutTailMetrics(
    in rect: CGRect,
    side: TailSide,
    cornerRadius: CGFloat,
    fontSize: CGFloat
  ) -> CalloutTailMetrics {
    let shortestSide = min(rect.width, rect.height)
    let lengths = calloutTailLengths(in: rect, fontSize: fontSize)
    let radius = resolvedCornerRadius(storedValue: cornerRadius, in: rect, fontSize: fontSize)
    let edgeLength = side.isVertical ? rect.height : rect.width
    // Half of the straight span: what is left of this edge once both corner arcs
    // are taken. Both the mode test and the root cap read it, so the mode cannot
    // flip as the tail changes length mid-drag.
    let midEdgeHalfSpan = max(0, edgeLength / 2 - radius)
    let attachesAtCorner = midEdgeHalfSpan < lengths.baseHalfWidth
    // In an arc the root is a chord of the corner circle, so it can never be
    // wider than the circle: `radius / sqrt(2)` is exactly the `delta <= 45°`
    // bound that keeps both sub-arcs of the split corner non-empty.
    let spanLimit = attachesAtCorner ? radius / CGFloat(2).squareRoot() : midEdgeHalfSpan
    return CalloutTailMetrics(
      lengths: lengths,
      radius: radius,
      maxRootHalfWidth: min(shortestSide * maxRootHalfWidthRatio, spanLimit),
      attachesAtCorner: attachesAtCorner
    )
  }

  /// Horizontal and vertical breathing room between the text and its bubble.
  ///
  /// One value for all three presentations: switching Text / Text Label /
  /// Callout Label must not resize the annotation, so the insets cannot depend
  /// on the presentation. `presentation` is kept in the signature so call sites
  /// stay uniform with the rest of the geometry helpers.
  static func contentInsets(for presentation: TextPresentation, fontSize: CGFloat) -> CGSize {
    CGSize(
      width: max(12, min(fontSize * 0.70, 24)),
      height: max(7, min(fontSize * 0.45, 14))
    )
  }

  /// Natural radius used when a bubble has no explicit radius of its own, e.g.
  /// text measured before the user ever touches the corner control.
  static func cornerRadius(in bounds: CGRect, fontSize: CGFloat) -> CGFloat {
    min(max(4, fontSize * 0.16), min(bounds.width, bounds.height) * 0.12)
  }

  /// Text Label and Callout Label share this single rule so the same stored
  /// number renders the same curvature in either presentation (T-07).
  ///
  /// The stored value is an absolute point value, not a proportion of the
  /// bubble. `0` means square corners, and the value is capped at half the
  /// shorter side so a large number yields a full pill. `fontSize` is only
  /// accepted so call sites stay uniform with the bubble geometry helpers and
  /// is deliberately not part of the calculation.
  static func resolvedCornerRadius(
    storedValue: CGFloat,
    in bounds: CGRect,
    fontSize: CGFloat
  ) -> CGFloat {
    let shortestSide = min(bounds.width, bounds.height)
    guard shortestSide > 0 else { return 0 }
    return min(max(0, storedValue), shortestSide / 2)
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

  /// Resolves a requested tail tip so the drawn tail always has a readable
  /// length, clamped into `[minTailLength, maxTailLength]` from the bubble.
  ///
  /// Deliberately radius-free. The resolved point is what callers store, and a
  /// font-size change, a style preset or a presentation switch re-resolves it;
  /// folding the corner radius in would re-aim the tail on any of those. Where
  /// the drawn root actually sits is the outline's business, see `calloutTail`.
  ///
  /// One `clamp`, so re-resolving an already-resolved target is a fixed point.
  /// The damped extension this replaces kept shortening the tail on every
  /// re-resolve, which is why tails shrank whenever the font size changed.
  static func resolvedTailTarget(in rect: CGRect, requestedTarget: CGPoint, fontSize: CGFloat) -> CGPoint {
    let rect = rect.standardized
    guard requestedTarget.x.isFinite, requestedTarget.y.isFinite else {
      return defaultTailTarget(for: rect, fontSize: fontSize)
    }
    guard !rect.contains(requestedTarget) else {
      return requestedTarget
    }

    let side = attachmentSide(for: requestedTarget, in: rect)
    let lengths = calloutTailLengths(in: rect, fontSize: fontSize)
    // The margin is the nominal one here; where the drawn root actually sits is
    // resolved again from the real corner radius in `calloutTail`.
    let margin = min(lengths.baseHalfWidth + 2, min(rect.width, rect.height) * 0.42)
    let anchor = attachmentPoint(for: requestedTarget, on: side, in: rect, margin: margin)
    let dx = requestedTarget.x - anchor.x
    let dy = requestedTarget.y - anchor.y
    let distance = hypot(dx, dy)
    guard distance > 0 else { return anchor }
    let resolvedLength = min(max(distance, lengths.minTailLength), lengths.maxTailLength)
    let scale = resolvedLength / distance
    return CGPoint(x: anchor.x + dx * scale, y: anchor.y + dy * scale)
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
          let tail = calloutTail(
            in: rect, requestedTarget: tailTarget, cornerRadius: cornerRadius, fontSize: fontSize
          ) else {
      // `cornerWidth`/`cornerHeight` are the corner *radius*, not the diameter.
      // Passing the radius directly keeps a tail-less bubble (Text Label) at the
      // same curvature as the hand-rolled arc path below (Callout Label) and as
      // every other rounded shape in the app.
      return CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    }

    let radius = min(max(0, cornerRadius), min(rect.width, rect.height) / 2)
    let path = CGMutablePath()
    path.move(to: TailSide.maxY.start(in: rect, radius: radius))
    // Edges and corners alternate in the same order as the hand-rolled loop this
    // replaces, and a side carrying no tail still emits the identical arc and
    // tangency points, so a Callout matches an identical Text Label bubble
    // corner for corner.
    for side in [TailSide.maxY, .maxX, .minY, .minX] {
      appendEdge(side, in: rect, radius: radius, tail: tail, path: path)
      appendCorner(side.downstreamCorner, in: rect, radius: radius, tail: tail, path: path)
    }
    path.closeSubpath()
    return path
  }

  static func tailPath(
    in rect: CGRect,
    to requestedTarget: CGPoint,
    cornerRadius: CGFloat,
    fontSize: CGFloat
  ) -> CGPath {
    let rect = rect.standardized
    guard let tail = calloutTail(
      in: rect, requestedTarget: requestedTarget, cornerRadius: cornerRadius, fontSize: fontSize
    ) else {
      return CGMutablePath()
    }

    let path = CGMutablePath()
    path.move(to: tail.entry)
    appendTail(tail, to: path)
    path.closeSubpath()
    return path
  }

  /// Builds the tail for a requested tip: resolves the tip, picks the attachment
  /// side, then roots the tail either on that side's straight span or in the
  /// corner arc at its end.
  private static func calloutTail(
    in rect: CGRect,
    requestedTarget: CGPoint,
    cornerRadius: CGFloat,
    fontSize: CGFloat
  ) -> CalloutTail? {
    guard rect.width > 0, rect.height > 0 else { return nil }

    let target = resolvedTailTarget(in: rect, requestedTarget: requestedTarget, fontSize: fontSize)
    // Bringing the target into the label restores the plain rounded rectangle.
    guard !rect.contains(target) else { return nil }
    let side = attachmentSide(for: target, in: rect)
    let metrics = calloutTailMetrics(
      in: rect, side: side, cornerRadius: cornerRadius, fontSize: fontSize
    )

    if metrics.attachesAtCorner, metrics.radius > 0,
       let tail = cornerTail(for: target, on: side, in: rect, metrics: metrics) {
      return tail
    }

    // The anchor stays clear of both arcs by the widest root this side can ever
    // draw, so no tail length can spill its root into an arc part-way through a
    // drag.
    let anchor = attachmentPoint(
      for: target, on: side, in: rect, margin: metrics.radius + metrics.maxRootHalfWidth
    )
    let distance = hypot(target.x - anchor.x, target.y - anchor.y)
    guard distance > 1 else { return nil }
    let basis = basis(for: side)
    // The root's anchor is clamped along the edge, so a target dragged well past
    // the side sits almost in the wall's plane from here. Leaning the tail back
    // into the cone keeps it a wedge instead of a sliver along the edge.
    let direction = outwardBiased(
      normalized(target - anchor), normal: basis.outward, tangent: basis.tangent
    )

    // The tip is placed at a length clamped in *drawn* space rather than at the
    // resolved target: the root's anchor sits further along the edge than the
    // resolver's nominal one, so aiming at the stored point would draw a tail
    // longer than the reach cap allows.
    let drawnLength = min(max(distance, metrics.minTailLength), metrics.maxTailLength)
    let rootHalfWidth = metrics.rootHalfWidth(forTailLength: drawnLength)
    return CalloutTail(
      side: side,
      root: .edge,
      target: anchor + direction * drawnLength,
      entry: anchor - basis.tangent * rootHalfWidth,
      exit: anchor + basis.tangent * rootHalfWidth,
      entryTangent: basis.tangent,
      exitTangent: basis.tangent,
      rootHalfWidth: rootHalfWidth
    )
  }

  /// Roots the tail in the corner arc at the target's end of `side`, because the
  /// straight span is too short to hold the root clear of both arcs. The anchor
  /// is the arc point facing the target, confined to the sub-span the root
  /// replaces, and the root replaces exactly that sub-arc, so the outline stays
  /// one continuous loop.
  private static func cornerTail(
    for target: CGPoint,
    on side: TailSide,
    in rect: CGRect,
    metrics: CalloutTailMetrics
  ) -> CalloutTail? {
    let radius = metrics.radius
    // `attachesAtCorner` needs `edgeLength / 2 - radius < baseHalfWidth` with
    // `baseHalfWidth <= 0.2 * shortestSide`, which no non-negative radius
    // satisfies, so this is defence in depth rather than a live branch.
    guard radius > 0 else { return nil }

    let corner = side.corner(nearest: target, in: rect)
    let center = corner.center(in: rect, radius: radius)
    let dx = target.x - center.x
    let dy = target.y - center.y
    guard hypot(dx, dy) > 1 else { return nil }
    let raw = atan2(dy, dx)

    // Two passes: the root width follows the drawn length, and the drawn length
    // follows where the clamp puts the anchor. The first pass uses the floor root
    // width, whose `delta` is the smallest and whose clamp window is therefore
    // the widest, so the second pass can only narrow it and cannot oscillate.
    let floorDelta = asin(min(max(metrics.baseHalfWidth / radius, 0), 1))
    let firstAnchor = corner.point(
      in: rect, radius: radius, at: clampAngle(raw: raw, into: corner, delta: floorDelta)
    )
    let drawnLength = min(
      max(hypot(target.x - firstAnchor.x, target.y - firstAnchor.y), metrics.minTailLength),
      metrics.maxTailLength
    )
    let rootHalfWidth = metrics.rootHalfWidth(forTailLength: drawnLength)
    let delta = asin(min(max(rootHalfWidth / radius, 0), 1))
    let angle = clampAngle(raw: raw, into: corner, delta: delta)
    let anchor = corner.point(in: rect, radius: radius, at: angle)
    guard hypot(target.x - anchor.x, target.y - anchor.y) > 1 else { return nil }

    let entryAngle = angle + delta
    let exitAngle = angle - delta
    let radial = CGPoint(x: cos(angle), y: sin(angle))
    return CalloutTail(
      side: side,
      root: .corner(corner, entryAngle: entryAngle, exitAngle: exitAngle),
      target: anchor + outwardBiased(
        normalized(target - anchor), normal: radial, tangent: Corner.tangent(at: angle)
      ) * drawnLength,
      entry: corner.point(in: rect, radius: radius, at: entryAngle),
      exit: corner.point(in: rect, radius: radius, at: exitAngle),
      entryTangent: Corner.tangent(at: entryAngle),
      exitTangent: Corner.tangent(at: exitAngle),
      rootHalfWidth: rootHalfWidth
    )
  }

  /// Rotates `direction` back towards `normal` until it leans no more than
  /// `maxTailTilt` away from it, keeping it on the same side of the normal.
  ///
  /// A projection, not a jump: a direction already inside the cone is returned
  /// untouched, and one at the boundary is left where the clamp would put it, so
  /// dragging the target across the boundary cannot snap the tail.
  private static func outwardBiased(
    _ direction: CGPoint,
    normal: CGPoint,
    tangent: CGPoint
  ) -> CGPoint {
    let outward = direction.x * normal.x + direction.y * normal.y
    let limit = cos(maxTailTilt)
    guard outward < limit else { return direction }
    let along = direction.x * tangent.x + direction.y * tangent.y
    return normal * limit + tangent * (along < 0 ? -sin(maxTailTilt) : sin(maxTailTilt))
  }

  /// Clamps a direction into `corner`'s arc while keeping the root (`delta`
  /// either side of the anchor) inside it.
  ///
  /// The comparison happens in the corner's own frame, because a raw direction
  /// can point up to 180° away and a plain `min`/`max` on the angle picks the
  /// wrong branch across ±π.
  private static func clampAngle(raw: CGFloat, into corner: Corner, delta: CGFloat) -> CGFloat {
    let mid = corner.midAngle
    let relative = atan2(sin(raw - mid), cos(raw - mid))
    let limit = max(0, .pi / 4 - delta)
    return mid + min(max(relative, -limit), limit)
  }

  private static func appendEdge(
    _ side: TailSide,
    in rect: CGRect,
    radius: CGFloat,
    tail: CalloutTail,
    path: CGMutablePath
  ) {
    guard tail.side == side, case .edge = tail.root else {
      path.addLine(to: side.end(in: rect, radius: radius))
      return
    }
    path.addLine(to: tail.entry)
    appendTail(tail, to: path)
    path.addLine(to: side.end(in: rect, radius: radius))
  }

  /// Draws one corner, split around the tail when the root lives in this arc: the
  /// arc runs up to the entry point, the tail replaces exactly the sub-arc it
  /// spans, and the remaining arc closes the corner.
  ///
  /// The removed sub-arc subtends `2 * delta` and its chord is
  /// `2 * radius * sin(delta)`, which is exactly `2 * rootHalfWidth`, so the tail
  /// fills the gap without overlapping and the outline stays a single
  /// non-crossing loop.
  private static func appendCorner(
    _ corner: Corner,
    in rect: CGRect,
    radius: CGFloat,
    tail: CalloutTail,
    path: CGMutablePath
  ) {
    let center = corner.center(in: rect, radius: radius)
    guard case .corner(let tailCorner, let entryAngle, let exitAngle) = tail.root,
          tailCorner == corner else {
      path.addArc(
        center: center, radius: radius,
        startAngle: corner.startAngle, endAngle: corner.endAngle, clockwise: true
      )
      return
    }
    path.addArc(
      center: center, radius: radius,
      startAngle: corner.startAngle, endAngle: entryAngle, clockwise: true
    )
    appendTail(tail, to: path)
    path.addArc(
      center: center, radius: radius,
      startAngle: exitAngle, endAngle: corner.endAngle, clockwise: true
    )
  }

  private static func appendTail(_ tail: CalloutTail, to path: CGMutablePath) {
    let intoTip = normalized(tail.target - tail.entry)
    let outOfTip = normalized(tail.exit - tail.target)
    let rootLength = hypot(tail.target.x - tail.entry.x, tail.target.y - tail.entry.y)
    // The tip fillet scales with the tail, so a long guide keeps a soft point
    // instead of a needle and a short one still ends in a crisp point.
    let tipInset = min(max(rootLength * 0.18, 2), tail.rootHalfWidth * 0.9)
    let rootControl = min(tail.rootHalfWidth * 0.9, rootLength * 0.3)

    path.addCurve(
      to: tail.target,
      control1: tail.entry + tail.entryTangent * rootControl,
      control2: tail.target - intoTip * tipInset
    )
    path.addCurve(
      to: tail.exit,
      control1: tail.target + outOfTip * tipInset,
      control2: tail.exit - tail.exitTangent * rootControl
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

  /// Anchor of a mid-edge tail, clamped along `side` so the root stays clear of
  /// both corner arcs. `margin` is the distance from the side's ends that must
  /// stay free, i.e. `radius + maxRootHalfWidth`, which is at most half the edge
  /// length by construction, so the clamp can never invert.
  private static func attachmentPoint(
    for target: CGPoint,
    on side: TailSide,
    in rect: CGRect,
    margin: CGFloat
  ) -> CGPoint {
    switch side {
    case .minX:
      return CGPoint(x: rect.minX, y: min(max(target.y, rect.minY + margin), rect.maxY - margin))
    case .maxX:
      return CGPoint(x: rect.maxX, y: min(max(target.y, rect.minY + margin), rect.maxY - margin))
    case .minY:
      return CGPoint(x: min(max(target.x, rect.minX + margin), rect.maxX - margin), y: rect.minY)
    case .maxY:
      return CGPoint(x: min(max(target.x, rect.minX + margin), rect.maxX - margin), y: rect.maxY)
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

nonisolated private func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
  CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}

nonisolated private func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
  CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}

nonisolated private func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
  CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
}

nonisolated private func normalized(_ point: CGPoint) -> CGPoint {
  let length = hypot(point.x, point.y)
  guard length > 0.0001 else { return .zero }
  return point * (1 / length)
}

nonisolated enum ArrowStyle: String, CaseIterable, Identifiable, Equatable {
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

nonisolated enum ArrowBendDirection: String, CaseIterable, Identifiable, Equatable {
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

nonisolated enum ArrowType: String, Codable, CaseIterable, Identifiable {
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
nonisolated enum ArrowEndpointStyle: String, CaseIterable, Identifiable, Equatable {
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

/// Stroke dash pattern for line-based annotations (shapes, lines, classic arrows).
nonisolated enum LineDashStyle: String, CaseIterable, Identifiable, Equatable, Codable {
  case solid
  case dashed
  case dotted

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .solid: L10n.AnnotateUI.lineStyleSolid
    case .dashed: L10n.AnnotateUI.lineStyleDashed
    case .dotted: L10n.AnnotateUI.lineStyleDotted
    }
  }

  /// Dash segment lengths scaled to the annotation's stroke width.
  /// Empty means solid; a zero-length segment with round caps renders as a dot.
  func dashLengths(for strokeWidth: CGFloat) -> [CGFloat] {
    let width = max(strokeWidth, 1)
    switch self {
    case .solid: return []
    case .dashed: return [width * 3, width * 2]
    case .dotted: return [0, width * 2]
    }
  }

  /// Fixed-size dash pattern used by toolbar icons.
  var iconDash: [CGFloat] {
    switch self {
    case .solid: []
    case .dashed: [4, 2.5]
    case .dotted: [0.1, 3]
    }
  }
}

nonisolated struct ArrowGeometry: Equatable {
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

  nonisolated func translatedBy(dx: CGFloat, dy: CGFloat) -> ArrowGeometry {
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

  /// Returns a copy with updated endpoints while preserving the control point's
  /// normalized position relative to the endpoint chord.
  ///
  /// The longitudinal progress and signed normal offset are both normalized by
  /// the old chord length, then reconstructed using the new chord. This keeps a
  /// manually adjusted curve's shape stable when either endpoint is moved.
  func withEndpoints(start newStart: CGPoint, end newEnd: CGPoint) -> ArrowGeometry {
    let newControlPoint: CGPoint?
    if style == .straight {
      newControlPoint = nil
    } else if let currentControlPoint = resolvedControlPoint {
      newControlPoint = Self.controlPointPreservingRelativeShape(
        currentControlPoint,
        oldStart: start,
        oldEnd: end,
        newStart: newStart,
        newEnd: newEnd
      )
    } else {
      newControlPoint = nil
    }

    return ArrowGeometry(
      start: newStart,
      end: newEnd,
      style: style,
      controlPoint: newControlPoint,
      arrowType: arrowType,
      startHead: startHead,
      endHead: endHead
    )
  }

  /// Returns a copy with a directly manipulated control point. Crossing the
  /// endpoint chord synchronizes the curved style with the actual bend side.
  /// A control point on the chord has no meaningful side, so the current style
  /// is retained until the point moves clearly to one side.
  func withControlPoint(_ newControlPoint: CGPoint) -> ArrowGeometry {
    guard style != .straight else { return self }

    let updatedStyle: ArrowStyle
    let chordLength = hypot(end.x - start.x, end.y - start.y)
    if chordLength <= 0.0001 {
      updatedStyle = style
    } else {
      let direction = CGPoint(
        x: (end.x - start.x) / chordLength,
        y: (end.y - start.y) / chordLength
      )
      let normal = CGPoint(x: -direction.y, y: direction.x)
      let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
      let signedOffset = (newControlPoint - midpoint).x * normal.x
        + (newControlPoint - midpoint).y * normal.y

      if abs(signedOffset) <= 0.0001 {
        updatedStyle = style
      } else {
        updatedStyle = signedOffset > 0 ? .curvedLeft : .curvedRight
      }
    }

    return ArrowGeometry(
      start: start,
      end: end,
      style: updatedStyle,
      controlPoint: newControlPoint,
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

  private static func controlPointPreservingRelativeShape(
    _ controlPoint: CGPoint,
    oldStart: CGPoint,
    oldEnd: CGPoint,
    newStart: CGPoint,
    newEnd: CGPoint
  ) -> CGPoint {
    let oldVector = oldEnd - oldStart
    let oldLength = hypot(oldVector.x, oldVector.y)
    guard oldLength > 0.0001 else {
      return controlPoint
    }

    let oldUnit = oldVector * (1 / oldLength)
    let oldNormal = CGPoint(x: -oldUnit.y, y: oldUnit.x)
    let controlOffset = controlPoint - oldStart
    let longitudinalProgress = (controlOffset.x * oldUnit.x + controlOffset.y * oldUnit.y) / oldLength
    let signedNormalOffset = (controlOffset.x * oldNormal.x + controlOffset.y * oldNormal.y) / oldLength

    let newVector = newEnd - newStart
    let newLength = hypot(newVector.x, newVector.y)
    guard newLength > 0.0001 else {
      return controlPoint
    }

    let newUnit = newVector * (1 / newLength)
    let newNormal = CGPoint(x: -newUnit.y, y: newUnit.x)
    return newStart
      + newUnit * (longitudinalProgress * newLength)
      + newNormal * (signedNormalOffset * newLength)
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

// MARK: - Bounds Remapping

extension AnnotationItem {
  /// Returns a translated copy while preserving the item's geometry and
  /// tool-specific metadata. The identity is retained for in-place movement.
  func translatedBy(dx: CGFloat, dy: CGFloat) -> AnnotationItem {
    var translated = self
    translated.bounds.origin.x += dx
    translated.bounds.origin.y += dy

    if let tailTarget = translated.properties.calloutTailTarget {
      translated.properties.calloutTailTarget = CGPoint(
        x: tailTarget.x + dx,
        y: tailTarget.y + dy
      )
    }

    switch translated.type {
    case .arrow(let geometry):
      let updated = geometry.translatedBy(dx: dx, dy: dy)
      translated.type = .arrow(updated)
      translated.bounds = updated.bounds()
    case .line(let start, let end):
      translated.type = .line(
        start: CGPoint(x: start.x + dx, y: start.y + dy),
        end: CGPoint(x: end.x + dx, y: end.y + dy)
      )
    case .path(let points):
      translated.type = .path(points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
    case .highlight(let points):
      translated.type = .highlight(points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
    default:
      break
    }

    return translated
  }

  /// Returns a translated copy with a fresh annotation identity.
  func duplicatedBy(dx: CGFloat, dy: CGFloat) -> AnnotationItem {
    let translated = translatedBy(dx: dx, dy: dy)
    return AnnotationItem(
      type: translated.type,
      bounds: translated.bounds,
      properties: translated.properties
    )
  }

  /// Returns a copy resized/moved to `newBounds`, remapping embedded geometry
  /// (arrow/line/path/highlight points, counter diameter, callout tail) exactly
  /// as an interactive bounds change would. Pure: no side effects, so the canvas
  /// can preview gestures on local copies and commit through `AnnotateState`.
  func applyingResizeBounds(_ newBounds: CGRect) -> AnnotationItem {
    var copy = self
    let oldBounds = resizeBounds
    let normalizedBounds = newBounds.standardized

    if case .text = copy.type,
       copy.properties.textPresentation == .callout,
       let tailTarget = copy.properties.calloutTailTarget {
      if TextBubbleGeometry.isDefaultTail(tailTarget, for: oldBounds, fontSize: copy.properties.fontSize) {
        copy.properties.calloutTailTarget = TextBubbleGeometry.defaultTailTarget(for: normalizedBounds, fontSize: copy.properties.fontSize)
      } else if oldBounds.size == normalizedBounds.size {
        copy.properties.calloutTailTarget = CGPoint(
          x: tailTarget.x + normalizedBounds.minX - oldBounds.minX,
          y: tailTarget.y + normalizedBounds.minY - oldBounds.minY
        )
      }
    }
    copy.bounds = normalizedBounds

    // Also remap embedded coordinates for arrows/lines/paths
    switch copy.type {
    case .arrow(let geometry):
      let updated = geometry.remapped(from: oldBounds, to: normalizedBounds)
      copy.type = .arrow(updated)
      copy.bounds = updated.bounds()
    case .line(let start, let end):
      copy.type = .line(
        start: Self.remapPoint(start, from: oldBounds, to: normalizedBounds),
        end: Self.remapPoint(end, from: oldBounds, to: normalizedBounds)
      )
    case .path(let points):
      copy.type = .path(points.map { Self.remapPoint($0, from: oldBounds, to: normalizedBounds) })
    case .highlight(let points):
      copy.type = .highlight(points.map { Self.remapPoint($0, from: oldBounds, to: normalizedBounds) })
    case .counter:
      let diameter = max(normalizedBounds.width, normalizedBounds.height)
      let controlValue = AnnotationProperties.controlValue(forCounterDiameter: diameter)
      let counterDiameter = AnnotationProperties.counterDiameter(for: controlValue)
      copy.bounds = CGRect(
        x: normalizedBounds.midX - counterDiameter / 2,
        y: normalizedBounds.midY - counterDiameter / 2,
        width: counterDiameter,
        height: counterDiameter
      )
      copy.properties.strokeWidth = controlValue
    default:
      break
    }

    return copy
  }

  private static func remapPoint(_ point: CGPoint, from oldBounds: CGRect, to newBounds: CGRect) -> CGPoint {
    CGPoint(
      x: remapCoordinate(point.x, oldMin: oldBounds.minX, oldSize: oldBounds.width, newMin: newBounds.minX, newSize: newBounds.width),
      y: remapCoordinate(point.y, oldMin: oldBounds.minY, oldSize: oldBounds.height, newMin: newBounds.minY, newSize: newBounds.height)
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
}

// MARK: - Render Ordering

extension Array where Element == AnnotationItem {
  /// Z-order for rendering and hit-testing: embedded images (canvas surfaces)
  /// at the bottom, blur/redact effects above them, and markup annotations
  /// (shapes, arrows, text, counters, …) always on top. Stable within each
  /// tier; the model array order itself is unchanged.
  var renderOrdered: [AnnotationItem] {
    var embedded: [AnnotationItem] = []
    var blurs: [AnnotationItem] = []
    var markup: [AnnotationItem] = []
    embedded.reserveCapacity(count)
    blurs.reserveCapacity(count)
    markup.reserveCapacity(count)
    for item in self {
      switch item.type {
      case .embeddedImage:
        embedded.append(item)
      case .blur:
        blurs.append(item)
      default:
        markup.append(item)
      }
    }
    return embedded + blurs + markup
  }
}

/// Types of annotations
nonisolated enum AnnotationType: Equatable {
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

  /// Dash styles apply to stroked geometry; tapered/outlined arrows are filled
  /// silhouettes, so only the classic arrow qualifies.
  var supportsQuickLineStyle: Bool {
    switch self {
    case .rectangle, .filledRectangle, .oval, .line, .spotlight:
      return true
    case .arrow(let geometry):
      return geometry.arrowType == .classic
    default:
      return false
    }
  }
}

/// Visual properties for an annotation
nonisolated struct AnnotationProperties: Equatable {
  static let controlValueRange: ClosedRange<CGFloat> = 1 ... 20

  var strokeColor: Color
  var fillColor: Color
  var strokeWidth: CGFloat
  var lineStyle: LineDashStyle
  var cornerRadius: CGFloat
  var fontSize: CGFloat
  var fontName: String
  var opacity: CGFloat
  var rotationDegrees: CGFloat
  var watermarkStyle: WatermarkStyle
  var spotlightOpacity: CGFloat
  var textPresentation: TextPresentation
  var calloutTailTarget: CGPoint?
  var textBorderColor: Color
  var textBorderWidth: CGFloat
  var isBorderEnabled: Bool
  /// Text colour a `.plain` switch displaced, kept so leaving `.plain` can put
  /// the user's own colour back.
  ///
  /// Plain text has no bubble to sit on, so a colour chosen against a filled
  /// surface can turn unreadable; T-08 then substitutes a contrasting one. That
  /// substitution must not be permanent — a white label on a red bubble over a
  /// white screenshot has to go back to white when the bubble returns. `nil`
  /// whenever no substitution is in effect, i.e. the colour on screen is the
  /// colour the user chose.
  var latentTextColor: Color?

  init(
    strokeColor: Color = .red,
    fillColor: Color = .clear,
    strokeWidth: CGFloat = 3,
    lineStyle: LineDashStyle = .solid,
    cornerRadius: CGFloat = 0,
    fontSize: CGFloat = 16,
    fontName: String = "SF Pro",
    opacity: CGFloat = 1,
    rotationDegrees: CGFloat = 0,
    watermarkStyle: WatermarkStyle = .single,
    spotlightOpacity: CGFloat = 0.5,
    textPresentation: TextPresentation = .plain,
    calloutTailTarget: CGPoint? = nil,
    textBorderColor: Color = .clear,
    textBorderWidth: CGFloat = 0,
    isBorderEnabled: Bool = false,
    latentTextColor: Color? = nil
  ) {
    self.strokeColor = strokeColor
    self.fillColor = fillColor
    self.strokeWidth = strokeWidth
    self.lineStyle = lineStyle
    self.cornerRadius = cornerRadius
    self.fontSize = fontSize
    self.fontName = fontName
    self.opacity = opacity
    self.rotationDegrees = rotationDegrees
    self.watermarkStyle = watermarkStyle
    self.spotlightOpacity = spotlightOpacity
    self.textPresentation = textPresentation
    self.calloutTailTarget = calloutTailTarget
    self.textBorderColor = textBorderColor
    self.textBorderWidth = textBorderWidth
    self.isBorderEnabled = isBorderEnabled
    self.latentTextColor = latentTextColor
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

  func matchesTextStyle(_ other: AnnotationProperties) -> Bool {
    fontSize == other.fontSize
      && fontName == other.fontName
      && cornerRadius == other.cornerRadius
      && textPresentation == other.textPresentation
      && textBorderWidth == other.textBorderWidth
      && textBorderColor == other.textBorderColor
      && isBorderEnabled == other.isBorderEnabled
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
    if case .arrow(let geometry) = type,
       geometry.style != .straight,
       let controlPoint = geometry.resolvedControlPoint {
      let controlPointBounds = CGRect(
        x: controlPoint.x - padding,
        y: controlPoint.y - padding,
        width: padding * 2,
        height: padding * 2
      )
      result = result.union(controlPointBounds)
    }
    if case .text = type,
       properties.textPresentation == .callout,
       let tailTarget = properties.calloutTailTarget {
      let tailBounds = TextBubbleGeometry.tailPath(
        in: bounds,
        to: tailTarget,
        cornerRadius: TextBubbleGeometry.resolvedCornerRadius(
          storedValue: properties.cornerRadius, in: bounds, fontSize: properties.fontSize
        ),
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
            cornerRadius: TextBubbleGeometry.resolvedCornerRadius(
              storedValue: properties.cornerRadius, in: bounds, fontSize: properties.fontSize
            ),
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
