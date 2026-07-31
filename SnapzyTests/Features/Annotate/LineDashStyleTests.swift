//
//  LineDashStyleTests.swift
//  SnapzyTests
//
//  Unit tests for line dash style patterns and persistence fallbacks.
//

import CoreGraphics
@testable import Snapzy
import XCTest

final class LineDashStyleTests: XCTestCase {
  func testRawValuesRoundTrip() {
    XCTAssertEqual(LineDashStyle(rawValue: "solid"), .solid)
    XCTAssertEqual(LineDashStyle(rawValue: "dashed"), .dashed)
    XCTAssertEqual(LineDashStyle(rawValue: "dotted"), .dotted)
    XCTAssertNil(LineDashStyle(rawValue: "wavy"))
    XCTAssertEqual(LineDashStyle.allCases.count, 3)
  }

  func testSolidProducesNoDash() {
    XCTAssertTrue(LineDashStyle.solid.dashLengths(for: 5).isEmpty)
  }

  func testDashedScalesWithStrokeWidth() {
    XCTAssertEqual(LineDashStyle.dashed.dashLengths(for: 4), [12, 8])
    XCTAssertEqual(LineDashStyle.dashed.dashLengths(for: 10), [30, 20])
  }

  func testDottedUsesZeroLengthSegmentsForRoundCapDots() {
    let lengths = LineDashStyle.dotted.dashLengths(for: 4)
    XCTAssertEqual(lengths.first, 0)
    XCTAssertEqual(lengths.last, 8)
  }

  func testDashLengthsClampMinimumStrokeWidth() {
    XCTAssertEqual(LineDashStyle.dashed.dashLengths(for: 0), [3, 2])
  }

  func testPersistedPropertiesWithoutLineStyleDecodeToSolid() throws {
    // Sidecars written before line styles existed carry no `lineStyle` key.
    let json = """
    {
      "strokeColor": { "red": 1, "green": 0, "blue": 0, "alpha": 1 },
      "fillColor": { "red": 0, "green": 0, "blue": 0, "alpha": 0 },
      "strokeWidth": 3,
      "cornerRadius": 0,
      "fontSize": 16,
      "fontName": "SF Pro",
      "opacity": 1,
      "rotationDegrees": 0,
      "watermarkStyle": "single"
    }
    """
    let decoded = try JSONDecoder().decode(
      PersistedAnnotationProperties.self,
      from: Data(json.utf8)
    )
    XCTAssertNil(decoded.lineStyle)
    XCTAssertEqual(decoded.annotationProperties.lineStyle, .solid)
  }

  func testPersistedPropertiesRoundTripLineStyle() {
    var properties = AnnotationProperties()
    properties.lineStyle = .dotted
    let persisted = PersistedAnnotationProperties(properties: properties)
    XCTAssertEqual(persisted.lineStyle, "dotted")
    XCTAssertEqual(persisted.annotationProperties.lineStyle, .dotted)
  }
}
