//
//  AnnotateStampTests.swift
//  SnapzyTests
//
//  Annotate Stamp tool: placement sizing, sidecar persistence, rendering and quick edits.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class AnnotateStampTests: XCTestCase {
  private func context(stamp: StampAnnotation, size: CGFloat = 100) -> AnnotationFactory.CreationContext {
    AnnotationFactory.CreationContext(
      properties: AnnotationProperties(),
      arrowStyle: .straight,
      blurType: .pixelated,
      counterValue: 1,
      watermarkText: "",
      activeAnnotationBounds: CGRect(x: 0, y: 0, width: 1000, height: 1000),
      stamp: stamp,
      stampSize: size,
      stampOpacity: 0.6,
      stampMinimumDragDistance: 8
    )
  }

  private func roundTrip(_ item: AnnotationItem) throws -> AnnotationItem? {
    let data = try JSONEncoder().encode(PersistedAnnotationItem(item: item))
    return try JSONDecoder().decode(PersistedAnnotationItem.self, from: data).annotationItem
  }

  private func pngStampImage(width: Int = 40, height: Int = 20) throws -> StampImage {
    let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
      NSColor.systemPink.setFill()
      NSBezierPath(ovalIn: rect).fill()
      return true
    }
    return try XCTUnwrap(AnnotateStampStore.makeStampImage(from: image))
  }

  // MARK: - Tool

  func testTool_isDrawableWithDefaultKeyG() {
    XCTAssertTrue(AnnotationToolType.drawableTools.contains(.stamp))
    XCTAssertEqual(AnnotationToolType.stamp.defaultShortcut, "g")
    XCTAssertTrue(AnnotateShortcutManager.configurableTools.contains(.stamp))
    XCTAssertFalse(AnnotationToolType.stamp.requiresDragToCreateAnnotation)
    XCTAssertTrue(AnnotationType.stamp(StampAnnotation(content: .emoji("🔥"))).supportsRotation)
  }

  // MARK: - Placement

  func testClickPlacesDefaultSizeCenteredOnPoint() throws {
    let stamp = StampAnnotation(content: .emoji("🔥"))
    let item = try XCTUnwrap(AnnotationFactory.createAnnotation(
      tool: .stamp, from: CGPoint(x: 200, y: 300), to: CGPoint(x: 202, y: 301), path: [], context: context(stamp: stamp)
    ))
    XCTAssertEqual(item.bounds, CGRect(x: 150, y: 250, width: 100, height: 100))
    XCTAssertEqual(item.properties.opacity, 0.6, accuracy: 0.0001)
    XCTAssertEqual(item.type, .stamp(stamp))
  }

  func testBadgeKeepsItsAspectRatio() throws {
    let stamp = StampAnnotation(content: .sticker(.approved))
    let item = try XCTUnwrap(AnnotationFactory.createAnnotation(
      tool: .stamp, from: .zero, to: .zero, path: [], context: context(stamp: stamp, size: 200)
    ))
    XCTAssertEqual(item.bounds.width, 200, accuracy: 0.001)
    XCTAssertGreaterThan(StampSticker.approved.aspectRatio, 2)
    XCTAssertEqual(item.bounds.width / item.bounds.height, StampSticker.approved.aspectRatio, accuracy: 0.001)
  }

  func testDragFitsContentAndPinsTheStartCorner() throws {
    let stamp = StampAnnotation(content: .emoji("👍"))
    // Drag left and down: a 60×20 box, square content → 20×20 pinned at the start corner.
    let item = try XCTUnwrap(AnnotationFactory.createAnnotation(
      tool: .stamp, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 40, y: 80), path: [], context: context(stamp: stamp)
    ))
    XCTAssertEqual(item.bounds, CGRect(x: 80, y: 80, width: 20, height: 20))
  }

  func testFittedRectNeverDistortsContent() {
    let rect = AnnotateStampRenderer.fittedRect(for: .emoji("⭐️"), in: CGRect(x: 0, y: 0, width: 200, height: 50))
    XCTAssertEqual(rect, CGRect(x: 75, y: 0, width: 50, height: 50))
  }

  // MARK: - Persistence

  func testStickerEmojiAndImageStampsRoundTrip() throws {
    let image = try pngStampImage()
    let stamps: [StampAnnotation] = [
      StampAnnotation(content: .sticker(.lgtm), isStickerStyle: false),
      StampAnnotation(content: .emoji("🚀")),
      StampAnnotation(content: .image(image)),
    ]
    for stamp in stamps {
      var properties = AnnotationProperties()
      properties.opacity = 0.5
      properties.rotationDegrees = 30
      let item = AnnotationItem(type: .stamp(stamp), bounds: CGRect(x: 1, y: 2, width: 30, height: 40), properties: properties)
      let restored = try XCTUnwrap(try roundTrip(item))
      guard case .stamp(let restoredStamp) = restored.type else { return XCTFail("Expected a stamp") }
      XCTAssertEqual(restoredStamp, stamp)
      XCTAssertEqual(restoredStamp.isStickerStyle, stamp.isStickerStyle)
      XCTAssertEqual(restored.bounds, item.bounds)
      XCTAssertEqual(restored.properties.opacity, 0.5, accuracy: 0.0001)
      XCTAssertEqual(restored.properties.rotationDegrees, 30, accuracy: 0.0001)
      if case .image(let restoredImage) = restoredStamp.content {
        XCTAssertEqual(restoredImage.pngData, image.pngData)
        XCTAssertEqual(restoredImage.pixelSize, image.pixelSize)
      }
    }
  }

  func testUnknownStickerIdIsSkippedNotFatal() throws {
    let item = AnnotationItem(type: .stamp(StampAnnotation(content: .sticker(.bug))), bounds: .zero, properties: AnnotationProperties())
    var json = try XCTUnwrap(String(data: JSONEncoder().encode(PersistedAnnotationItem(item: item)), encoding: .utf8))
    json = json.replacingOccurrences(of: "\"bug\"", with: "\"future-sticker\"")
    let decoded = try JSONDecoder().decode(PersistedAnnotationItem.self, from: Data(json.utf8))
    XCTAssertNil(decoded.annotationItem)
  }

  func testRecentKeysRoundTrip() {
    for content in [StampContent.sticker(.heart), .emoji("❤️")] {
      XCTAssertEqual(content.recentKey.flatMap(StampContent.init(recentKey:)), content)
    }
    XCTAssertNil(StampContent.init(recentKey: "sticker:does-not-exist"))
  }

  // MARK: - Rendering

  func testRenderingDrawsOpaquePixelsInsideBounds() throws {
    for content in [StampContent.sticker(.approved), .sticker(.heart), .emoji("😀"), .image(try pngStampImage())] {
      let context = try XCTUnwrap(CGContext(
        data: nil, width: 120, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ))
      AnnotateStampRenderer.draw(StampAnnotation(content: content), in: CGRect(x: 10, y: 10, width: 100, height: 100), opacity: 1, context: context)
      let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
      let bytesPerRow = context.bytesPerRow
      // Center pixel is painted.
      XCTAssertGreaterThan(data[60 * bytesPerRow + 60 * 4 + 3], 200, "\(content)")
      // Far corner stays empty.
      XCTAssertEqual(data[0 * bytesPerRow + 0 * 4 + 3], 0, "\(content)")
    }
  }

  func testEmojiCatalogHasSearchableNames() {
    XCTAssertGreaterThan(AnnotateEmojiCatalog.all.count, 500)
    XCTAssertTrue(AnnotateEmojiCatalog.search("rocket").contains { $0.emoji == "🚀" })
    XCTAssertTrue(AnnotateEmojiCatalog.search("zzzz-nothing").isEmpty)
  }

  // MARK: - Quick edits

  func testResizingSelectedStampKeepsCenterInOneUndoStep() {
    let state = AnnotateState()
    let item = AnnotationItem(
      type: .stamp(StampAnnotation(content: .emoji("🎯"))),
      bounds: CGRect(x: 100, y: 100, width: 50, height: 50),
      properties: AnnotationProperties()
    )
    state.annotations = [item]
    state.setSelectedAnnotationIds([item.id])
    AnnotateStampStore.shared.setSliderEditing(true)
    state.setQuickStampSize(80)
    state.setQuickStampSize(150)
    AnnotateStampStore.shared.setSliderEditing(false)
    XCTAssertEqual(state.annotations[0].bounds, CGRect(x: 50, y: 50, width: 150, height: 150))
    state.undo()
    XCTAssertEqual(state.annotations[0].bounds, item.bounds)
  }
}
