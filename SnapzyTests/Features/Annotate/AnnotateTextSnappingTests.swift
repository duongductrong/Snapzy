//
//  AnnotateTextSnappingTests.swift
//  SnapzyTests
//
//  Pure snap-math tests with a hand-built AnnotateTextLineProfile (no Vision
//  needed): single-line snapping, drag-direction normalization, multi-line
//  text-selection semantics, column-break truncation, freehand fallbacks, and
//  the segment -> annotation conversion.
//

import AppKit
import CoreGraphics
import SwiftUI
import XCTest
@testable import Snapzy

final class AnnotateTextSnappingTests: XCTestCase {
  // Three 20pt lines of one text block, 10pt apart, spanning x 100...500
  // (bottom-left image points, top line first).
  private static let wordEdges: [CGFloat] = [100, 180, 200, 300, 320, 500]

  private static func line(
    minY: CGFloat,
    minX: CGFloat = 100,
    maxX: CGFloat = 500,
    height: CGFloat = 20
  ) -> AnnotateTextLine {
    AnnotateTextLine(
      bounds: CGRect(x: minX, y: minY, width: maxX - minX, height: height),
      wordEdges: wordEdges.map { min(max($0, minX), maxX) }
    )
  }

  private let profile = AnnotateTextLineProfile(lines: [
    AnnotateTextSnappingTests.line(minY: 400), // midY 410
    AnnotateTextSnappingTests.line(minY: 370), // midY 380
    AnnotateTextSnappingTests.line(minY: 340)  // midY 350
  ])
  private let tolerance: CGFloat = 4

  private func resolve(
    from start: CGPoint,
    to current: CGPoint,
    path: [CGPoint]? = nil,
    profile: AnnotateTextLineProfile? = nil
  ) -> [AnnotateTextSnapSegment] {
    AnnotateTextSnapping.resolve(
      start: start,
      current: current,
      path: path ?? [start, current],
      profile: profile ?? self.profile,
      pointerTolerance: tolerance
    )
  }

  // MARK: - Single line

  func testSnapsToTheLineUnderTheDragAndToWordEdges() {
    let segments = resolve(from: CGPoint(x: 185, y: 380), to: CGPoint(x: 295, y: 378))

    // x snapped 185 -> 180 and 295 -> 300; bar centered on the line's midY at
    // 1.15x the line height.
    XCTAssertEqual(segments.map(\.rect), [CGRect(x: 180, y: 368.5, width: 120, height: 23)])
  }

  func testShakyDragStillSnapsToASingleStraightBar() {
    let shakyPath = [
      CGPoint(x: 185, y: 380), CGPoint(x: 210, y: 386), CGPoint(x: 240, y: 374),
      CGPoint(x: 265, y: 384), CGPoint(x: 295, y: 378)
    ]
    let segments = resolve(from: CGPoint(x: 185, y: 380), to: CGPoint(x: 295, y: 378), path: shakyPath)

    XCTAssertEqual(segments.map(\.rect), [CGRect(x: 180, y: 368.5, width: 120, height: 23)])
  }

  func testRightToLeftDragProducesTheSameBar() {
    let segments = resolve(from: CGPoint(x: 295, y: 378), to: CGPoint(x: 185, y: 380))

    XCTAssertEqual(segments.map(\.rect), [CGRect(x: 180, y: 368.5, width: 120, height: 23)])
  }

  func testEndFarFromAnyWordEdgeStaysWhereThePointerIs() {
    // 260 is >15pt from every word edge, so it is only clamped to the line.
    let segments = resolve(from: CGPoint(x: 185, y: 380), to: CGPoint(x: 260, y: 380))

    XCTAssertEqual(segments.map(\.rect), [CGRect(x: 180, y: 368.5, width: 80, height: 23)])
  }

  func testDragBeyondTheLineClampsToTheLineExtent() {
    let segments = resolve(from: CGPoint(x: 60, y: 380), to: CGPoint(x: 900, y: 380))

    XCTAssertEqual(segments.map(\.rect), [CGRect(x: 100, y: 368.5, width: 400, height: 23)])
  }

  // MARK: - Multi-line

  func testDownwardMultiLineDragUsesTextSelectionSemantics() {
    let segments = resolve(
      from: CGPoint(x: 185, y: 410),
      to: CGPoint(x: 295, y: 350),
      path: [CGPoint(x: 185, y: 410), CGPoint(x: 240, y: 380), CGPoint(x: 295, y: 350)]
    )

    XCTAssertEqual(segments.map(\.rect), [
      CGRect(x: 180, y: 398.5, width: 320, height: 23), // anchor -> line end
      CGRect(x: 100, y: 368.5, width: 400, height: 23), // full line
      CGRect(x: 100, y: 338.5, width: 200, height: 23)  // line start -> pointer
    ])
  }

  func testUpwardMultiLineDragMirrorsTheSelection() {
    let segments = resolve(
      from: CGPoint(x: 185, y: 350),
      to: CGPoint(x: 295, y: 410),
      path: [CGPoint(x: 185, y: 350), CGPoint(x: 240, y: 380), CGPoint(x: 295, y: 410)]
    )

    XCTAssertEqual(segments.map(\.rect), [
      CGRect(x: 300, y: 398.5, width: 200, height: 23),
      CGRect(x: 100, y: 368.5, width: 400, height: 23),
      CGRect(x: 100, y: 338.5, width: 80, height: 23)
    ])
  }

  func testMultiLineDragUsesOneUniformBarHeight() {
    // Vision line boxes grow with descenders; a sweep must not look ragged.
    let unevenProfile = AnnotateTextLineProfile(lines: [
      Self.line(minY: 400),                        // h 20, midY 410
      Self.line(minY: 366, height: 26),            // h 26, midY 379
      Self.line(minY: 336)                         // h 20, midY 346
    ])

    let segments = resolve(
      from: CGPoint(x: 185, y: 410),
      to: CGPoint(x: 295, y: 346),
      path: [CGPoint(x: 185, y: 410), CGPoint(x: 240, y: 379), CGPoint(x: 295, y: 346)],
      profile: unevenProfile
    )

    XCTAssertEqual(segments.map(\.rect.height), [23, 23, 23])
    XCTAssertEqual(segments.map(\.rect), [
      CGRect(x: 180, y: 398.5, width: 320, height: 23),
      CGRect(x: 100, y: 367.5, width: 400, height: 23),
      CGRect(x: 100, y: 334.5, width: 200, height: 23)
    ])
  }

  func testChainStopsAtAColumnBreak() {
    let disjointProfile = AnnotateTextLineProfile(lines: [
      Self.line(minY: 400),
      Self.line(minY: 370),
      Self.line(minY: 340, minX: 900, maxX: 1300) // different column
    ])

    let segments = resolve(
      from: CGPoint(x: 185, y: 410),
      to: CGPoint(x: 295, y: 350),
      path: [CGPoint(x: 185, y: 410), CGPoint(x: 240, y: 380), CGPoint(x: 295, y: 350)],
      profile: disjointProfile
    )

    // The unrelated column is dropped, so the second line becomes the tail.
    XCTAssertEqual(segments.map(\.rect), [
      CGRect(x: 180, y: 398.5, width: 320, height: 23),
      CGRect(x: 100, y: 368.5, width: 200, height: 23)
    ])
  }

  // MARK: - Freehand fallbacks

  func testEmptyProfileProducesNoSegments() {
    let segments = resolve(
      from: CGPoint(x: 185, y: 380),
      to: CGPoint(x: 295, y: 380),
      profile: .empty
    )

    XCTAssertTrue(segments.isEmpty)
  }

  func testDragAwayFromAnyTextProducesNoSegments() {
    XCTAssertTrue(resolve(from: CGPoint(x: 185, y: 200), to: CGPoint(x: 295, y: 200)).isEmpty)
  }

  func testTooShortDragProducesNoSegments() {
    XCTAssertTrue(resolve(from: CGPoint(x: 185, y: 380), to: CGPoint(x: 190, y: 380)).isEmpty)
  }

  func testVerticalDragProducesNoSegments() {
    XCTAssertTrue(resolve(from: CGPoint(x: 185, y: 410), to: CGPoint(x: 187, y: 350)).isEmpty)
  }

  func testScribbleThatLeavesTheTextBandStaysFreehand() {
    let scribble = [
      CGPoint(x: 185, y: 380), CGPoint(x: 200, y: 300), CGPoint(x: 220, y: 300),
      CGPoint(x: 240, y: 300), CGPoint(x: 295, y: 380)
    ]

    XCTAssertTrue(resolve(from: CGPoint(x: 185, y: 380), to: CGPoint(x: 295, y: 380), path: scribble).isEmpty)
  }

  // MARK: - Segment geometry

  func testSegmentGeometryMatchesTheHighlightRenderer() {
    let segment = AnnotateTextSnapSegment(rect: CGRect(x: 180, y: 368.5, width: 120, height: 23))

    // Highlights render at 3x stroke width with round caps, so the stroke width
    // carries the bar height and the endpoints are inset by the cap radius.
    XCTAssertEqual(segment.strokeWidth, 23.0 / 3, accuracy: 0.0001)
    XCTAssertEqual(segment.highlightPoints, [
      CGPoint(x: 191.5, y: 380),
      CGPoint(x: 288.5, y: 380)
    ])
  }

  func testSegmentsBecomeOrdinaryHighlightAnnotations() {
    let segments = [
      AnnotateTextSnapSegment(rect: CGRect(x: 180, y: 368.5, width: 120, height: 23)),
      AnnotateTextSnapSegment(rect: CGRect(x: 100, y: 338.5, width: 200, height: 23))
    ]

    let items = AnnotationFactory.createTextSnappedHighlights(
      segments: segments,
      context: AnnotationFactory.CreationContext(
        properties: AnnotationProperties(strokeColor: .yellow, strokeWidth: 3),
        arrowStyle: .straight,
        blurType: .pixelated,
        counterValue: 0,
        watermarkText: "Snapzy",
        activeAnnotationBounds: CGRect(x: 0, y: 0, width: 800, height: 600)
      )
    )

    XCTAssertEqual(items.count, 2)
    for (item, segment) in zip(items, segments) {
      guard case .highlight(let points) = item.type else {
        return XCTFail("Expected a highlight annotation")
      }
      XCTAssertEqual(points, segment.highlightPoints)
      XCTAssertEqual(item.properties.strokeWidth, segment.strokeWidth, accuracy: 0.0001)
      XCTAssertEqual(item.properties.strokeColor, .yellow)
    }
  }

  // MARK: - Vision conversion

  func testVisionBoxKeepsBottomLeftOriginInImagePoints() {
    let rect = AnnotateTextSnapDetector.imagePointRect(
      fromVisionBoundingBox: CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.1),
      imagePointSize: CGSize(width: 400, height: 200)
    )

    // Vision and the annotation canvas both measure Y from the bottom.
    XCTAssertEqual(rect, CGRect(x: 100, y: 40, width: 200, height: 20))
  }

  /// End-to-end guard for the coordinate convention: Vision reports normalized
  /// boxes from the bottom, and so does the annotation canvas, so text drawn
  /// near the top of the image must come back with a high Y.
  func testDetectorReportsTextNearTheImageTopWithAHighY() throws {
    try skipIfRunningInCI()
    let size = CGSize(width: 600, height: 300)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
    // AppKit's image context is bottom-left origin, so this sits near the top.
    ("Highlight this sentence" as NSString).draw(
      at: NSPoint(x: 40, y: 230),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 34),
        .foregroundColor: NSColor.black
      ]
    )
    image.unlockFocus()

    let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let profile = AnnotateTextSnapDetector.detectLines(in: cgImage, imagePointSize: size)

    let line = try XCTUnwrap(profile.lines.first, "Vision found no text in the rendered sample")
    XCTAssertGreaterThan(line.bounds.midY, size.height / 2)
    XCTAssertLessThan(line.bounds.minX, size.width / 2)
    XCTAssertGreaterThan(line.wordEdges.count, 2, "Expected per-word edges for snapping")
  }

  // MARK: - Preference

  @MainActor
  func testQuickPropertiesExposeTheToggleOnlyForHighlighterDefaults() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 400, height: 300))

    state.activateTool(.highlighter)
    XCTAssertTrue(state.quickPropertiesSupportsHighlighterTextSnapping)

    // Other tools never show it.
    state.activateTool(.rectangle)
    XCTAssertFalse(state.quickPropertiesSupportsHighlighterTextSnapping)

    // A committed highlight's geometry is fixed, so the selected-item context
    // (where every control edits that item) hides the creation-time toggle.
    let highlight = AnnotationItem(
      type: .highlight([CGPoint(x: 10, y: 20), CGPoint(x: 90, y: 20)]),
      bounds: CGRect(x: 10, y: 19, width: 80, height: 2),
      properties: AnnotationProperties()
    )
    state.annotations.append(highlight)
    state.activateTool(.highlighter)
    state.selectedAnnotationId = highlight.id
    state.setSelectedAnnotationIds([highlight.id])
    XCTAssertFalse(state.quickPropertiesSupportsHighlighterTextSnapping)

    state.deselectAnnotation()
    XCTAssertTrue(state.quickPropertiesSupportsHighlighterTextSnapping)
  }

  @MainActor
  func testQuickPropertiesToggleDrivesTheSnappingPreference() {
    let state = makeAnnotateState()
    let binding = state.quickHighlighterTextSnappingBinding

    XCTAssertTrue(binding.wrappedValue)

    binding.wrappedValue = false
    XCTAssertFalse(state.isHighlighterTextSnappingEnabled)

    state.isHighlighterTextSnappingEnabled = true
    XCTAssertTrue(binding.wrappedValue)
  }

  @MainActor
  func testTextSnappingPreferenceDefaultsOnAndPersists() {
    let defaults = UserDefaultsFactory.make()
    let state = AnnotateState(defaults: defaults)
    Self.retainedAnnotateStates.append(state)

    XCTAssertTrue(state.isHighlighterTextSnappingEnabled)

    state.isHighlighterTextSnappingEnabled = false
    XCTAssertEqual(
      defaults.object(forKey: PreferencesKeys.annotateHighlighterTextSnappingEnabled) as? Bool,
      false
    )
    XCTAssertFalse(AnnotateState(defaults: defaults).isHighlighterTextSnappingEnabled)
  }

  // Keep AnnotateState alive for the test process; XCTest scope cleanup can
  // crash while deinitializing this MainActor app-level ObservableObject.
  @MainActor private static var retainedAnnotateStates: [AnnotateState] = []

  @MainActor
  private func makeAnnotateState() -> AnnotateState {
    let state = AnnotateState(defaults: UserDefaultsFactory.make())
    Self.retainedAnnotateStates.append(state)
    return state
  }

  private func makeImage(width: Int, height: Int) throws -> NSImage {
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: width, height: height))
    return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
  }
}
