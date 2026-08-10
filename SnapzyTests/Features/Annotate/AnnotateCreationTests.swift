//
//  AnnotateCreationTests.swift
//  SnapzyTests
//
//  Characterization tests for state-level creation wiring: `updateBlurType`
//  across all blur types and `nextCounterValue` monotonicity. Basic factory
//  creation is covered in AnnotateAnnotationFactoryTests / AnnotateCoreTests.
//

import CoreGraphics
import SwiftUI
import XCTest
@testable import Snapzy

final class AnnotateCreationTests: XCTestCase {
  @MainActor private static var retainedAnnotateStates: [AnnotateState] = []

  @MainActor
  private func makeAnnotateState() -> AnnotateState {
    let state = AnnotateState()
    Self.retainedAnnotateStates.append(state)
    return state
  }

  @MainActor
  private func makeBlurAnnotation() -> AnnotationItem {
    AnnotationItem(
      type: .blur(.pixelated),
      bounds: CGRect(x: 0, y: 0, width: 100, height: 60),
      properties: AnnotationProperties()
    )
  }

  @MainActor
  func testUpdateBlurTypeAppliesEveryBlurType() throws {
    let state = makeAnnotateState()
    let annotation = makeBlurAnnotation()
    state.annotations = [annotation]

    for blurType in BlurType.allCases {
      state.updateBlurType(id: annotation.id, blurType: blurType)
      let updated = try XCTUnwrap(state.annotations.first)
      guard case .blur(let appliedType) = updated.type else {
        return XCTFail("Expected blur annotation, got \(updated.type)")
      }
      XCTAssertEqual(appliedType, blurType)
    }

    // Guards against silently dropping a case if the enum grows.
    XCTAssertEqual(BlurType.allCases.count, 8)
  }

  @MainActor
  func testUpdateBlurTypeIsNoOpForNonBlurAnnotation() {
    let state = makeAnnotateState()
    let rectangle = AnnotationItem(
      type: .rectangle,
      bounds: CGRect(x: 0, y: 0, width: 40, height: 40),
      properties: AnnotationProperties()
    )
    state.annotations = [rectangle]

    state.updateBlurType(id: rectangle.id, blurType: .gaussian)

    XCTAssertEqual(state.annotations.first?.type, .rectangle)
  }

  @MainActor
  func testUpdateBlurTypeIgnoresUnknownId() {
    let state = makeAnnotateState()
    let annotation = makeBlurAnnotation()
    state.annotations = [annotation]

    state.updateBlurType(id: UUID(), blurType: .washi)

    guard case .blur(.pixelated) = state.annotations.first?.type else {
      return XCTFail("Expected unchanged pixelated blur")
    }
  }

  @MainActor
  func testNextCounterValueStartsAtOneWhenNoCounters() {
    let state = makeAnnotateState()
    XCTAssertEqual(state.nextCounterValue(), 1)
  }

  @MainActor
  func testNextCounterValueReturnsMaxExistingPlusOne() {
    let state = makeAnnotateState()
    state.annotations = [
      AnnotationItem(type: .counter(1), bounds: .zero, properties: AnnotationProperties()),
      AnnotationItem(type: .counter(5), bounds: .zero, properties: AnnotationProperties()),
    ]

    // Derived from the maximum existing counter, not the count of counters.
    XCTAssertEqual(state.nextCounterValue(), 6)
  }

  @MainActor
  func testNextCounterValueIgnoresNonCounterAnnotations() {
    let state = makeAnnotateState()
    state.annotations = [
      AnnotationItem(type: .rectangle, bounds: .zero, properties: AnnotationProperties()),
      AnnotationItem(type: .counter(3), bounds: .zero, properties: AnnotationProperties()),
    ]

    XCTAssertEqual(state.nextCounterValue(), 4)
  }

  @MainActor
  func testCanExtractTextRequiresNormalAnnotateSourceImage() {
    let state = AnnotateState(
      image: NSImage(size: CGSize(width: 120, height: 80)),
      url: URL(fileURLWithPath: "/tmp/annotate-ocr-test.png"),
      appliesDefaultCanvasPresetOnNewImages: false
    )

    XCTAssertTrue(state.canExtractText)

    state.activateCombineMode()
    XCTAssertFalse(state.canExtractText)

    state.deactivateCombineMode()
    state.editorMode = .mockup
    XCTAssertFalse(state.canExtractText)

    state.editorMode = .annotate
    state.sourceImage = nil
    XCTAssertFalse(state.canExtractText)
  }
}
