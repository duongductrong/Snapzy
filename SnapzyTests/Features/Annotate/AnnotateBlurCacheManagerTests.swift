//
//  AnnotateBlurCacheManagerTests.swift
//  SnapzyTests
//
//  Unit tests for BlurCacheManager caching logic.
//

import AppKit
import XCTest
@testable import Snapzy

final class AnnotateBlurCacheManagerTests: XCTestCase {

  private var cache: BlurCacheManager!
  private var sourceImage: NSImage!

  override func setUp() {
    super.setUp()
    cache = BlurCacheManager()
    guard let cgImage = TestImageFactory.solidColor(width: 200, height: 200) else {
      XCTFail("Failed to create test image")
      return
    }
    sourceImage = NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
  }

  override func tearDown() {
    cache = nil
    sourceImage = nil
    super.tearDown()
  }

  func testGetCachedBlur_returnsImage() {
    let id = UUID()
    let bounds = CGRect(x: 10, y: 10, width: 50, height: 50)
    let image = cache.getCachedBlur(for: id, bounds: bounds, sourceImage: sourceImage, blurType: .pixelated, effectValue: 8)
    XCTAssertNotNil(image)
  }

  func testGetCachedBlur_reusesCache() {
    let id = UUID()
    let bounds = CGRect(x: 10, y: 10, width: 50, height: 50)
    let first = cache.getCachedBlur(for: id, bounds: bounds, sourceImage: sourceImage, blurType: .pixelated, effectValue: 8)
    let second = cache.getCachedBlur(for: id, bounds: bounds, sourceImage: sourceImage, blurType: .pixelated, effectValue: 8)
    XCTAssertTrue(first === second)
  }

  func testGetCachedBlur_regeneratesWhenBoundsChange() {
    let id = UUID()
    let first = cache.getCachedBlur(for: id, bounds: CGRect(x: 10, y: 10, width: 50, height: 50), sourceImage: sourceImage, blurType: .pixelated, effectValue: 8)
    let second = cache.getCachedBlur(for: id, bounds: CGRect(x: 10, y: 10, width: 60, height: 60), sourceImage: sourceImage, blurType: .pixelated, effectValue: 8)
    XCTAssertFalse(first === second)
  }

  func testGetCachedBlur_allowsApproximateReuse() {
    let id = UUID()
    let first = cache.getCachedBlur(for: id, bounds: CGRect(x: 10, y: 10, width: 50, height: 50), sourceImage: sourceImage, blurType: .pixelated, effectValue: 8)
    let second = cache.getCachedBlur(for: id, bounds: CGRect(x: 10, y: 10, width: 60, height: 60), sourceImage: sourceImage, blurType: .pixelated, effectValue: 8, allowApproximateReuse: true)
    XCTAssertTrue(first === second)
  }


  func testGetCachedBlur_nonBlockingSchedulesRender() {
    let id = UUID()
    let bounds = CGRect(x: 10, y: 10, width: 50, height: 50)

    let immediate = cache.getCachedBlur(
      for: id,
      bounds: bounds,
      sourceImage: sourceImage,
      blurType: .pixelated,
      effectValue: 8,
      renderSynchronously: false
    )
    XCTAssertNil(immediate)

    // Poll until async render completes (avoids DispatchQueue.main.async + wait(for:)
    // run loop interaction issues on CI runners).
    let deadline = CFAbsoluteTimeGetCurrent() + 10.0
    while CFAbsoluteTimeGetCurrent() < deadline {
      if cache.hasCachedBlur(for: id) { break }
      RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }
    XCTAssertTrue(cache.hasCachedBlur(for: id))
  }

  func testInvalidate_removesCache() {
    let id = UUID()
    cache.getCachedBlur(for: id, bounds: CGRect(x: 0, y: 0, width: 20, height: 20), sourceImage: sourceImage, blurType: .pixelated, effectValue: 8)
    XCTAssertTrue(cache.hasCachedBlur(for: id))
    cache.invalidate(id: id)
    XCTAssertFalse(cache.hasCachedBlur(for: id))
  }

  func testClearAll_removesAllCache() {
    let id1 = UUID()
    let id2 = UUID()
    cache.getCachedBlur(for: id1, bounds: CGRect(x: 0, y: 0, width: 20, height: 20), sourceImage: sourceImage, blurType: .pixelated, effectValue: 8)
    cache.getCachedBlur(for: id2, bounds: CGRect(x: 0, y: 0, width: 20, height: 20), sourceImage: sourceImage, blurType: .pixelated, effectValue: 8)
    cache.clearAll()
    XCTAssertFalse(cache.hasCachedBlur(for: id1))
    XCTAssertFalse(cache.hasCachedBlur(for: id2))
  }

  func testGetCachedBlur_emptyBounds_returnsNil() {
    let image = cache.getCachedBlur(for: UUID(), bounds: CGRect(x: 0, y: 0, width: 0, height: 0), sourceImage: sourceImage, blurType: .pixelated, effectValue: 8)
    XCTAssertNil(image)
  }
}
