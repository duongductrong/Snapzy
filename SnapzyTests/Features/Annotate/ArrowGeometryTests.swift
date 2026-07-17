//
//  ArrowGeometryTests.swift
//  SnapzyTests
//
//  Unit tests for ArrowGeometry path sampling, bounds, and transforms.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class ArrowGeometryTests: XCTestCase {

  // MARK: - sampledPoints / deduplication

  func testStraightLine_pointsAreStartAndEnd() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), style: .straight)
    XCTAssertEqual(geo.sampledPoints(), [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)])
  }

  func testStraightLine_deduplicatesCoincidentPoints() {
    let geo = ArrowGeometry(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 10, y: 10), style: .straight)
    XCTAssertEqual(geo.sampledPoints(), [CGPoint(x: 10, y: 10)])
  }

  func testCurvedRight_defaultControlPoint_offsetBelowMidpoint() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), style: .curvedRight)
    let control = geo.resolvedControlPoint!
    XCTAssertEqual(control.x, 50, accuracy: 0.001)
    XCTAssertLessThan(control.y, 0)
    XCTAssertEqual(geo.bendDirection, .alternate)
  }

  func testCurvedLeft_defaultControlPoint_offsetAboveMidpoint() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), style: .curvedLeft)
    let control = geo.resolvedControlPoint!
    XCTAssertEqual(control.x, 50, accuracy: 0.001)
    XCTAssertGreaterThan(control.y, 0)
    XCTAssertEqual(geo.bendDirection, .primary)
  }

  func testCurvedRight_sampledPoints_nonTrivial() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), style: .curvedRight)
    let points = geo.sampledPoints()
    XCTAssertEqual(points.count, 17)
    XCTAssertEqual(points.first, geo.start)
    XCTAssertEqual(points.last, geo.end)
  }

  // MARK: - isRenderable

  func testStraightLine_differentPoints_isRenderable() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 10), style: .straight)
    XCTAssertTrue(geo.isRenderable)
  }

  func testStraightLine_samePoint_isNotRenderable() {
    let geo = ArrowGeometry(start: CGPoint(x: 5, y: 5), end: CGPoint(x: 5, y: 5), style: .straight)
    XCTAssertFalse(geo.isRenderable)
  }

  // MARK: - tangentAngleAtEnd

  func testTangentAngle_straight() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), style: .straight)
    XCTAssertEqual(geo.tangentAngleAtEnd(), 0, accuracy: 0.001)
  }

  func testTangentAngle_straightUp() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 0), style: .straight)
    XCTAssertEqual(geo.tangentAngleAtEnd(), -.pi / 2, accuracy: 0.001)
  }

  // MARK: - bounds

  func testBounds_straight() {
    let geo = ArrowGeometry(start: CGPoint(x: 10, y: 20), end: CGPoint(x: 50, y: 80), style: .straight)
    let b = geo.bounds()
    XCTAssertEqual(b.minX, 10, accuracy: 0.001)
    XCTAssertEqual(b.minY, 20, accuracy: 0.001)
    XCTAssertGreaterThanOrEqual(b.width, 1)
    XCTAssertGreaterThanOrEqual(b.height, 1)
  }

  func testBounds_zeroSize_enforcesMinimum() {
    let geo = ArrowGeometry(start: CGPoint(x: 5, y: 5), end: CGPoint(x: 5, y: 5), style: .straight)
    let b = geo.bounds()
    XCTAssertEqual(b.width, 1, accuracy: 0.001)
    XCTAssertEqual(b.height, 1, accuracy: 0.001)
  }

  // MARK: - translatedBy

  func testTranslatedBy() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), style: .curvedRight)
    let moved = geo.translatedBy(dx: 10, dy: -5)
    XCTAssertEqual(moved.start, CGPoint(x: 10, y: -5))
    XCTAssertEqual(moved.end, CGPoint(x: 110, y: 95))
  }

  // MARK: - remapped

  func testRemapped() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), style: .straight)
    let remapped = geo.remapped(from: CGRect(x: 0, y: 0, width: 100, height: 100), to: CGRect(x: 0, y: 0, width: 200, height: 200))
    XCTAssertEqual(remapped.start, CGPoint(x: 0, y: 0))
    XCTAssertEqual(remapped.end, CGPoint(x: 200, y: 200))
  }

  // MARK: - withStyle

  func testWithStyle() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 10), style: .straight)
    let curved = geo.withStyle(.curvedRight)
    XCTAssertEqual(curved.style, .curvedRight)
    XCTAssertEqual(curved.start, geo.start)
    XCTAssertEqual(curved.end, geo.end)
  }

  func testWithStyle_preservesAlternateBendBetweenCurvedStyles() {
    let geo = ArrowGeometry(
      start: CGPoint(x: 0, y: 0),
      end: CGPoint(x: 100, y: 30),
      style: .curvedLeft
    )
    let curvedRight = geo.withStyle(.curvedRight)
    XCTAssertEqual(curvedRight.style, .curvedRight)
    XCTAssertEqual(curvedRight.bendDirection, .alternate)
  }

  func testWithBendDirection_mirrorsRemappedCurveControlPointAcrossBaseline() throws {
    let original = ArrowGeometry(
      start: CGPoint(x: 0, y: 0),
      end: CGPoint(x: 100, y: 0),
      style: .curvedLeft,
      controlPoint: CGPoint(x: 30, y: 50)
    )
    let remapped = original.remapped(
      from: CGRect(x: 0, y: 0, width: 100, height: 50),
      to: CGRect(x: 10, y: 20, width: 180, height: 90)
    )
    let control = try XCTUnwrap(remapped.resolvedControlPoint)

    let flipped = remapped.withBendDirection(.alternate)
    let flippedControl = try XCTUnwrap(flipped.resolvedControlPoint)

    XCTAssertEqual(flipped.bendDirection, .alternate)
    XCTAssertEqual(flipped.style, .curvedRight)
    XCTAssertEqual(
      baselineProgress(flippedControl, start: remapped.start, end: remapped.end),
      baselineProgress(control, start: remapped.start, end: remapped.end),
      accuracy: 0.001
    )
    XCTAssertEqual(
      signedPerpendicularDistance(flippedControl, start: remapped.start, end: remapped.end),
      -signedPerpendicularDistance(control, start: remapped.start, end: remapped.end),
      accuracy: 0.001
    )
  }

  private func signedPerpendicularDistance(_ point: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = max(hypot(dx, dy), 0.0001)
    let normal = CGPoint(x: -dy / length, y: dx / length)
    return (point.x - start.x) * normal.x + (point.y - start.y) * normal.y
  }

  private func baselineProgress(_ point: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = max(dx * dx + dy * dy, 0.0001)
    return ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
  }

  // MARK: - arrowType & backwards compatibility

  func testArrowType_defaultsToTapered() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), style: .straight)
    XCTAssertEqual(geo.arrowType, .tapered)
  }

  func testArrowType_withArrowType() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), style: .straight)
    let classic = geo.withArrowType(.classic)
    XCTAssertEqual(classic.arrowType, .classic)
    XCTAssertEqual(classic.start, geo.start)
    XCTAssertEqual(classic.end, geo.end)
    XCTAssertEqual(classic.style, geo.style)

    let outlined = geo.withArrowType(.outlined)
    XCTAssertEqual(outlined.arrowType, .outlined)
  }

  func testArrowType_translatedBy_preservesArrowType() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), style: .straight, arrowType: .classic)
    let translated = geo.translatedBy(dx: 10, dy: 10)
    XCTAssertEqual(translated.arrowType, .classic)
  }

  func testArrowType_remapped_preservesArrowType() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), style: .straight, arrowType: .classic)
    let remapped = geo.remapped(from: CGRect(x: 0, y: 0, width: 100, height: 100), to: CGRect(x: 0, y: 0, width: 200, height: 200))
    XCTAssertEqual(remapped.arrowType, .classic)
  }

  func testArrowType_persistence_roundtrips() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), style: .straight, arrowType: .classic)
    let persisted = PersistedArrowGeometry(geometry: geo)
    XCTAssertEqual(persisted.arrowType, "classic")
    
    let restored = persisted.arrowGeometry
    XCTAssertEqual(restored.arrowType, .classic)
  }

  func testArrowType_persistence_backwardCompatibility() {
    // A persisted geometry without arrowType (from older versions of the app)
    let persisted = PersistedArrowGeometry(geometry: ArrowGeometry(start: .zero, end: .zero, style: .straight))
    // Simulate older save where arrowType field is missing/nil
    var dictionaryRepresentation = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(persisted), options: []) as! [String: Any]
    dictionaryRepresentation.removeValue(forKey: "arrowType")
    
    let serializedData = try! JSONSerialization.data(withJSONObject: dictionaryRepresentation, options: [])
    let decoded = try! JSONDecoder().decode(PersistedArrowGeometry.self, from: serializedData)
    
    XCTAssertNil(decoded.arrowType)
    XCTAssertEqual(decoded.arrowGeometry.arrowType, .outlined) // Backwards compatible default
  }

  func testWithStyle_mirrorsControlPointBetweenCurvedStyles() {
    let geo = ArrowGeometry(
      start: CGPoint(x: 0, y: 0),
      end: CGPoint(x: 100, y: 0),
      style: .curvedLeft,
      controlPoint: CGPoint(x: 30, y: 50)
    )
    let curvedRight = geo.withStyle(.curvedRight)
    XCTAssertEqual(curvedRight.style, .curvedRight)
    XCTAssertEqual(curvedRight.bendDirection, .alternate)
    
    let control = curvedRight.resolvedControlPoint!
    // The control point should be mirrored across the baseline (y = 0)
    XCTAssertEqual(control.x, 30, accuracy: 0.001)
    XCTAssertEqual(control.y, -50, accuracy: 0.001)
  }

  func testWithStyle_straightToCurved_computesDefaultControlPoint() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), style: .straight)
    let curved = geo.withStyle(.curvedRight)
    XCTAssertEqual(curved.style, .curvedRight)
    XCTAssertNotNil(curved.resolvedControlPoint)
  }

  // MARK: - tapered / outlined geometry (reference silhouette)

  func testTaperedMetrics_shaftWidensTowardHead() {
    let metrics = ArrowGeometry.taperedMetrics(strokeWidth: 3, chordLength: 160)
    // Neck (near the head) tracks strokeWidth (visual weight near rectangle stroke).
    XCTAssertGreaterThan(metrics.shaftNeckWidth, 5)
    XCTAssertLessThan(metrics.shaftNeckWidth, 14)
    // Shaft must WIDEN toward the head: thin tail → wide neck, never thin at the tip.
    XCTAssertGreaterThan(metrics.shaftNeckWidth, metrics.shaftBaseWidth)
    // Taper is clear — tail is ~half the neck, not needle-thin.
    XCTAssertGreaterThan(metrics.shaftBaseWidth, metrics.shaftNeckWidth * 0.4)
    XCTAssertLessThan(metrics.shaftBaseWidth, metrics.shaftNeckWidth * 0.6)
    // Head wider than the neck for shallow shoulders.
    XCTAssertGreaterThan(metrics.headWidth, metrics.shaftNeckWidth * 1.85)
    // Head must leave room for a visible shaft on typical arrows.
    XCTAssertLessThan(metrics.headLength, 160 * 0.35)
    // Outline stays proportional to the body.
    XCTAssertGreaterThanOrEqual(metrics.outlineWidth, 1.5)
    XCTAssertLessThan(metrics.outlineWidth, 4)
    // Shallow barbs (not deep notches).
    XCTAssertLessThanOrEqual(metrics.sweepBack, metrics.headLength * 0.15)
  }

  func testTaperedMetrics_shaftWidensAcrossStrokeWidths() {
    // Widening (thin tail → wide neck) must hold at every stroke weight.
    for stroke in [CGFloat(1), 2, 3, 5, 8, 12] {
      let metrics = ArrowGeometry.taperedMetrics(strokeWidth: stroke, chordLength: 150)
      XCTAssertGreaterThan(
        metrics.shaftNeckWidth,
        metrics.shaftBaseWidth,
        "stroke \(stroke): neck \(metrics.shaftNeckWidth) must be wider than tail \(metrics.shaftBaseWidth)"
      )
    }
  }

  func testTaperedMetrics_bodyWidthComparableToStrokeWidth() {
    // Filled shaft (measured at its widest, the neck) should read close to other tools'
    // stroke weight (not 3–4× thicker).
    for stroke in [CGFloat(2), 3, 5, 8] {
      let metrics = ArrowGeometry.taperedMetrics(strokeWidth: stroke, chordLength: 150)
      XCTAssertLessThan(
        metrics.shaftNeckWidth,
        stroke * 3.2,
        "stroke \(stroke): shaft \(metrics.shaftNeckWidth) too wide vs stroke weight"
      )
      XCTAssertGreaterThan(
        metrics.shaftNeckWidth,
        stroke * 1.2,
        "stroke \(stroke): shaft \(metrics.shaftNeckWidth) too thin vs stroke weight"
      )
    }
  }

  func testTaperedMetrics_scalesWithStrokeWidth() {
    let thin = ArrowGeometry.taperedMetrics(strokeWidth: 2, chordLength: 140)
    let thick = ArrowGeometry.taperedMetrics(strokeWidth: 8, chordLength: 140)
    XCTAssertGreaterThan(thick.shaftBaseWidth, thin.shaftBaseWidth)
    XCTAssertGreaterThan(thick.headWidth, thin.headWidth)
    XCTAssertGreaterThan(thick.outlineWidth, thin.outlineWidth)
  }

  func testTaperedArrowPath_producesNonEmptyClosedPath() {
    let geo = ArrowGeometry(
      start: CGPoint(x: 20, y: 80),
      end: CGPoint(x: 180, y: 20),
      style: .straight,
      arrowType: .outlined
    )
    let path = geo.taperedArrowPath(strokeWidth: 4)
    let bounds = path.boundingBoxOfPath
    XCTAssertFalse(path.isEmpty)
    XCTAssertGreaterThan(bounds.width, 100)
    XCTAssertGreaterThan(bounds.height, 20)
    // Path must extend past start/end to cover shaft width + head wings.
    XCTAssertLessThan(bounds.minX, min(geo.start.x, geo.end.x) + 1)
    XCTAssertGreaterThan(bounds.maxX, max(geo.start.x, geo.end.x) - 1)
  }

  func testTaperedArrowPath_degenerateChord_returnsEmpty() {
    let geo = ArrowGeometry(start: CGPoint(x: 5, y: 5), end: CGPoint(x: 5.5, y: 5), style: .straight)
    let path = geo.taperedArrowPath(strokeWidth: 3)
    // chordLength must be > 1 to build geometry
    XCTAssertTrue(path.isEmpty || path.boundingBoxOfPath.isNull || path.boundingBoxOfPath.isEmpty)
  }

  func testTaperedArrowPath_curved_producesPathLargerThanStraightChord() {
    let geo = ArrowGeometry(
      start: CGPoint(x: 0, y: 0),
      end: CGPoint(x: 120, y: 0),
      style: .curvedLeft,
      arrowType: .tapered
    )
    let path = geo.taperedArrowPath(strokeWidth: 3)
    XCTAssertFalse(path.isEmpty)
    let bounds = path.boundingBoxOfPath
    // Curve bows off the baseline so height exceeds pure shaft thickness.
    XCTAssertGreaterThan(bounds.height, geo.taperedMetrics(strokeWidth: 3).shaftBaseWidth)
  }

  func testTaperedMetrics_instanceMatchesStatic() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), style: .straight)
    let viaInstance = geo.taperedMetrics(strokeWidth: 4)
    let viaStatic = ArrowGeometry.taperedMetrics(strokeWidth: 4, chordLength: 100)
    XCTAssertEqual(viaInstance, viaStatic)
  }

  // MARK: - every arrow type adapts every style (bend & straighten)

  /// All three display types (classic / tapered / outlined) must render across all
  /// three styles (straight / curvedRight / curvedLeft) with a valid, non-trivial shape.
  func testEveryArrowType_adaptsEveryStyle() {
    let start = CGPoint(x: 0, y: 0)
    let end = CGPoint(x: 140, y: 0)

    for type in ArrowType.allCases {
      for style in ArrowStyle.allCases {
        let geo = ArrowGeometry(start: start, end: end, style: style, arrowType: type)
        XCTAssertEqual(geo.arrowType, type, "\(type)/\(style): arrowType not preserved")
        XCTAssertEqual(geo.style, style, "\(type)/\(style): style not preserved")
        XCTAssertTrue(geo.isRenderable, "\(type)/\(style): must be renderable")

        // Curved styles expose a control point; straight does not.
        if style == .straight {
          XCTAssertNil(geo.resolvedControlPoint, "straight must have no control point")
        } else {
          XCTAssertNotNil(geo.resolvedControlPoint, "\(style): curve needs a control point")
        }

        // Classic strokes the centerline path(); tapered/outlined fill taperedArrowPath.
        switch type {
        case .classic:
          XCTAssertFalse(geo.path().isEmpty, "\(type)/\(style): centerline path empty")
        case .tapered, .outlined:
          let path = geo.taperedArrowPath(strokeWidth: 4)
          XCTAssertFalse(path.isEmpty, "\(type)/\(style): filled body empty")
        }
      }
    }
  }

  /// Curving a filled arrow must bow the body off the baseline for both bend directions.
  func testTaperedArrowPath_bothBendDirectionsBowOffBaseline() {
    let straightHeight = ArrowGeometry(
      start: CGPoint(x: 0, y: 0),
      end: CGPoint(x: 120, y: 0),
      style: .straight,
      arrowType: .tapered
    ).taperedArrowPath(strokeWidth: 3).boundingBoxOfPath.height

    for style in [ArrowStyle.curvedRight, .curvedLeft] {
      let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 120, y: 0), style: style, arrowType: .tapered)
      let bounds = geo.taperedArrowPath(strokeWidth: 3).boundingBoxOfPath
      XCTAssertGreaterThan(bounds.height, straightHeight, "\(style): curved body should bow past straight shaft")
    }
  }

  /// Switching display type must preserve the active curve/bend (adapting, not resetting).
  func testWithArrowType_preservesCurveAndBend() {
    let curved = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), style: .curvedRight, arrowType: .classic)
    for type in ArrowType.allCases {
      let switched = curved.withArrowType(type)
      XCTAssertEqual(switched.arrowType, type)
      XCTAssertEqual(switched.style, .curvedRight, "style dropped switching to \(type)")
      XCTAssertEqual(switched.bendDirection, curved.bendDirection, "bend dropped switching to \(type)")
      XCTAssertNotNil(switched.resolvedControlPoint, "curve dropped switching to \(type)")
    }
  }

  func testArrowType_iconForStyle() {
    for type in ArrowType.allCases {
      // Test straight style
      switch type {
      case .classic:
        XCTAssertEqual(type.icon(for: .straight), "arrow.up.right")
      case .tapered:
        XCTAssertEqual(type.icon(for: .straight), "arrowshape.turn.up.right")
      case .outlined:
        XCTAssertEqual(type.icon(for: .straight), "arrowshape.turn.up.right.fill")
      }

      // Test curvedRight style
      switch type {
      case .classic:
        XCTAssertEqual(type.icon(for: .curvedRight), "arrow.turn.up.right")
      case .tapered:
        XCTAssertEqual(type.icon(for: .curvedRight), "arrowshape.turn.up.right")
      case .outlined:
        XCTAssertEqual(type.icon(for: .curvedRight), "arrowshape.turn.up.right.fill")
      }

      // Test curvedLeft style
      switch type {
      case .classic:
        XCTAssertEqual(type.icon(for: .curvedLeft), "arrow.turn.up.left")
      case .tapered:
        XCTAssertEqual(type.icon(for: .curvedLeft), "arrowshape.turn.up.left")
      case .outlined:
        XCTAssertEqual(type.icon(for: .curvedLeft), "arrowshape.turn.up.left.fill")
      }
    }
  }

  // MARK: - endpoint heads (start / end)

  func testEndpointHeads_defaultToNoneStartArrowEnd() {
    let geo = ArrowGeometry(start: .zero, end: CGPoint(x: 100, y: 0), style: .straight)
    XCTAssertEqual(geo.startHead, .none)
    XCTAssertEqual(geo.endHead, .arrow)
  }

  func testWithStartHead_andEndHead() {
    let geo = ArrowGeometry(start: .zero, end: CGPoint(x: 100, y: 0), style: .straight)

    let bothArrows = geo.withStartHead(.arrow)
    XCTAssertEqual(bothArrows.startHead, .arrow)
    XCTAssertEqual(bothArrows.endHead, .arrow)

    let circleEnd = geo.withEndHead(.circle)
    XCTAssertEqual(circleEnd.startHead, .none)
    XCTAssertEqual(circleEnd.endHead, .circle)
  }

  func testEndpointHeads_preservedAcrossTransforms() {
    let geo = ArrowGeometry(
      start: .zero,
      end: CGPoint(x: 100, y: 40),
      style: .curvedRight,
      startHead: .circle,
      endHead: .none
    )

    let translated = geo.translatedBy(dx: 10, dy: 10)
    XCTAssertEqual(translated.startHead, .circle)
    XCTAssertEqual(translated.endHead, .none)

    let remapped = geo.remapped(
      from: CGRect(x: 0, y: 0, width: 100, height: 40),
      to: CGRect(x: 0, y: 0, width: 200, height: 80)
    )
    XCTAssertEqual(remapped.startHead, .circle)
    XCTAssertEqual(remapped.endHead, .none)

    let restyled = geo.withStyle(.straight)
    XCTAssertEqual(restyled.startHead, .circle)
    XCTAssertEqual(restyled.endHead, .none)

    let retyped = geo.withArrowType(.classic)
    XCTAssertEqual(retyped.startHead, .circle)
    XCTAssertEqual(retyped.endHead, .none)
  }

  func testTangentAngleAtStart_straight_pointsAwayFromEnd() {
    let geo = ArrowGeometry(start: CGPoint(x: 100, y: 0), end: CGPoint(x: 0, y: 0), style: .straight)
    // Start is to the right of the end, so the outward tangent points +x (angle 0).
    XCTAssertEqual(geo.tangentAngleAtStart(), 0, accuracy: 0.001)
  }

  func testEndpointHeads_persistence_roundtrips() {
    let geo = ArrowGeometry(
      start: .zero,
      end: CGPoint(x: 100, y: 0),
      style: .straight,
      arrowType: .classic,
      startHead: .arrow,
      endHead: .circle
    )
    let persisted = PersistedArrowGeometry(geometry: geo)
    XCTAssertEqual(persisted.startHead, "arrow")
    XCTAssertEqual(persisted.endHead, "circle")

    let restored = persisted.arrowGeometry
    XCTAssertEqual(restored.startHead, .arrow)
    XCTAssertEqual(restored.endHead, .circle)
  }

  func testEndpointHeads_persistence_backwardCompatibility() {
    // Older saves have no startHead/endHead → keep the historical single-headed arrow.
    let persisted = PersistedArrowGeometry(geometry: ArrowGeometry(start: .zero, end: .zero, style: .straight))
    var dict = try! JSONSerialization.jsonObject(
      with: JSONEncoder().encode(persisted), options: []
    ) as! [String: Any]
    dict.removeValue(forKey: "startHead")
    dict.removeValue(forKey: "endHead")

    let data = try! JSONSerialization.data(withJSONObject: dict, options: [])
    let decoded = try! JSONDecoder().decode(PersistedArrowGeometry.self, from: data)

    XCTAssertNil(decoded.startHead)
    XCTAssertNil(decoded.endHead)
    XCTAssertEqual(decoded.arrowGeometry.startHead, .none)
    XCTAssertEqual(decoded.arrowGeometry.endHead, .arrow)
  }
}
