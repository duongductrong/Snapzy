import AppKit
import CoreGraphics
import XCTest
@testable import Snapzy

@MainActor
final class CounterArrowGeometryTests: XCTestCase {
  private static var retainedStates: [AnnotateState] = []

  private func counter(target: CGPoint? = CGPoint(x: 160, y: 50)) -> AnnotationItem {
    AnnotationItem(
      type: .counter(3),
      bounds: CGRect(x: 38, y: 38, width: 24, height: 24),
      properties: AnnotationProperties(strokeWidth: 3, counterArrowTarget: target)
    )
  }

  func testArrowStartsAtBadgeEdgeAndSelectionContainsItsSilhouette() throws {
    let item = counter()
    let geometry = try XCTUnwrap(item.counterArrowGeometry)
    XCTAssertEqual(geometry.start, CGPoint(x: 62, y: 50))
    XCTAssertEqual(geometry.end, CGPoint(x: 160, y: 50))
    XCTAssertEqual(geometry.style, .straight)
    XCTAssertEqual(geometry.arrowType, .tapered)
    XCTAssertEqual(item.resizeBounds, item.bounds)
    XCTAssertTrue(item.selectionBounds.contains(geometry.taperedArrowPath(strokeWidth: 3).boundingBoxOfPath))
    XCTAssertTrue(item.containsPoint(CGPoint(x: 50, y: 50)))
    XCTAssertTrue(item.containsPoint(CGPoint(x: 100, y: 50)))
    XCTAssertTrue(item.containsPoint(CGPoint(x: 158, y: 50)))
    XCTAssertFalse(item.containsPoint(CGPoint(x: 100, y: 90)))
  }

  func testClickInsideBadgeAndNonFiniteTargetsHaveNoArrow() {
    for target in [nil, CGPoint(x: 50, y: 50), CGPoint(x: 62, y: 50), CGPoint(x: CGFloat.nan, y: 50), CGPoint(x: 100, y: CGFloat.infinity)] {
      XCTAssertNil(counter(target: target).counterArrowGeometry)
    }
  }

  func testDiagonalArrowStartsOnEllipse() throws {
    let geometry = try XCTUnwrap(counter(target: CGPoint(x: 150, y: 150)).counterArrowGeometry)
    XCTAssertEqual(hypot(geometry.start.x - 50, geometry.start.y - 50), 12, accuracy: 0.001)
  }

  func testMoveDuplicateAndResizePreserveTargetRules() {
    let original = counter()
    let moved = original.translatedBy(dx: 10, dy: -20)
    XCTAssertEqual(moved.id, original.id)
    XCTAssertEqual(moved.properties.counterArrowTarget, CGPoint(x: 170, y: 30))
    let duplicate = original.duplicatedBy(dx: 10, dy: -20)
    XCTAssertNotEqual(duplicate.id, original.id)
    XCTAssertEqual(duplicate.properties.counterArrowTarget, moved.properties.counterArrowTarget)
    guard case .counter(let number) = duplicate.type else { return XCTFail("Expected counter") }
    XCTAssertEqual(number, 3)
    let viaBounds = original.applyingResizeBounds(original.bounds.offsetBy(dx: 10, dy: -20))
    XCTAssertEqual(viaBounds.properties.counterArrowTarget, moved.properties.counterArrowTarget)
    let resized = original.applyingResizeBounds(CGRect(x: 30, y: 30, width: 40, height: 40))
    XCTAssertEqual(resized.properties.counterArrowTarget, original.properties.counterArrowTarget)
    XCTAssertEqual(resized.resizeBounds.width, 40)
  }

  func testPersistenceRoundTripAndLegacyProperties() throws {
    let persisted = PersistedAnnotationProperties(properties: counter().properties)
    let encoded = try JSONEncoder().encode(persisted)
    let decoded = try JSONDecoder().decode(PersistedAnnotationProperties.self, from: encoded)
    XCTAssertEqual(decoded.annotationProperties.counterArrowTarget, CGPoint(x: 160, y: 50))
    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    legacy.removeValue(forKey: "counterArrowTarget")
    let legacyDecoded = try JSONDecoder().decode(PersistedAnnotationProperties.self, from: JSONSerialization.data(withJSONObject: legacy))
    XCTAssertNil(legacyDecoded.annotationProperties.counterArrowTarget)
    XCTAssertEqual(legacyDecoded.annotationProperties.strokeWidth, 3)
  }

  func testExportPreservesArrowEnteringCropWithBadgeOutside() throws {
    let state = AnnotateState(defaults: UserDefaultsFactory.make())
    Self.retainedStates.append(state)
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: 200, height: 100))
    state.loadImage(NSImage(cgImage: cgImage, size: CGSize(width: 200, height: 100)))
    state.padding = 0
    state.shadowIntensity = 0
    state.cornerRadius = 0
    state.aspectRatio = .free
    state.backgroundStyle = .none
    state.cropRect = CGRect(x: 80, y: 0, width: 100, height: 100)
    state.annotations = [counter()]
    XCTAssertFalse(state.annotations[0].bounds.intersects(try XCTUnwrap(state.cropRect)))
    let rendered = try XCTUnwrap(AnnotateExporter.renderFinalImage(state: state))
    let image = try XCTUnwrap(AnnotateExporter.bestCGImage(from: rendered))
    XCTAssertEqual(image.width, 100)
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try bytes.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    // The source badge was cropped out; red at this position must come from its
    // attached arrow after the crop origin has also translated the target.
    let index = (50 * image.width + 60) * 4
    XCTAssertGreaterThan(bytes[index], 200)
    XCTAssertLessThan(bytes[index + 1], 100)
    XCTAssertLessThan(bytes[index + 2], 100)
  }
}
