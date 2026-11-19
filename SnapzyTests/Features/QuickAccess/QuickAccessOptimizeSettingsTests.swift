//
//  QuickAccessOptimizeSettingsTests.swift
//  SnapzyTests
//

import CoreGraphics
import ImageIO
import XCTest
@testable import Snapzy

final class QuickAccessOptimizeSettingsTests: XCTestCase {
  private let source = QuickAccessOptimizeSourceInfo(pixelWidth: 1200, pixelHeight: 800, nativeScale: 2)

  // MARK: - Settings

  func testFormatExtensionKeepsOriginalAndJPEGSpelling() {
    XCTAssertEqual(QuickAccessOptimizeFormat.original.fileExtension(forOriginal: "PNG"), "png")
    XCTAssertEqual(QuickAccessOptimizeFormat.webp.fileExtension(forOriginal: "png"), "webp")
    XCTAssertEqual(QuickAccessOptimizeFormat.jpeg.fileExtension(forOriginal: "png"), "jpg")
    XCTAssertEqual(QuickAccessOptimizeFormat.jpeg.fileExtension(forOriginal: "jpeg"), "jpeg")
  }

  func testClampedKeepsValuesInRange() {
    let settings = QuickAccessOptimizeSettings(scalePercent: 400, format: .png, qualityPercent: 1, maxFileSize: 5).clamped
    XCTAssertEqual(settings.scalePercent, 100)
    XCTAssertEqual(settings.qualityPercent, QuickAccessOptimizeSettings.qualityRange.lowerBound)
    XCTAssertEqual(settings.maxFileSize, 10000)
  }

  func testSummaryShowsQualityOnlyForLossyOutput() {
    let webp = QuickAccessOptimizeSettings(scalePercent: 50, format: .webp, qualityPercent: 80, maxFileSize: nil)
    XCTAssertEqual(webp.summary(), "50% · WebP 80")

    let png = QuickAccessOptimizeSettings(scalePercent: 100, format: .png, qualityPercent: 80, maxFileSize: nil)
    XCTAssertEqual(png.summary(), "100% · PNG")
  }

  func testSettingsRoundTripThroughJSON() throws {
    let settings = QuickAccessOptimizeSettings(scalePercent: 60, format: .jpeg, qualityPercent: 70, maxFileSize: 500_000)
    let data = try JSONEncoder().encode(settings)
    XCTAssertEqual(try JSONDecoder().decode(QuickAccessOptimizeSettings.self, from: data), settings)
  }

  // MARK: - Rendering

  func testCustomRenderConvertsFormatAndScales() throws {
    let original = try XCTUnwrap(makeNoisyImage(width: 1200, height: 800))
    let settings = QuickAccessOptimizeSettings(scalePercent: 50, format: .webp, qualityPercent: 80, maxFileSize: nil)

    let rendering = try XCTUnwrap(
      QuickAccessImageOptimizer.render(settings, from: original, source: source, originalExtension: "png")
    )

    XCTAssertEqual(rendering.fileExtension, "webp")
    XCTAssertEqual(rendering.dimensionsLabel, "600×400")
    XCTAssertEqual(rendering.scale, 1)
    XCTAssertEqual(rendering.qualityPercent, 80)
    XCTAssertTrue(rendering.meetsFileSizeLimit)
    XCTAssertEqual(String(data: rendering.data.subdata(in: 8 ..< 12), encoding: .ascii), "WEBP")
  }

  /// Regression: the render extension once inherited MainActor default isolation, so
  /// a detached call hopped back to the main thread and froze the Custom editor.
  func testCustomRenderRunsOffTheMainThreadWhenDetached() async throws {
    let original = try XCTUnwrap(makeNoisyImage(width: 600, height: 400))
    let source = QuickAccessOptimizeSourceInfo(pixelWidth: 600, pixelHeight: 400, nativeScale: 1)
    let ranOnMain = await Task.detached { () -> Bool in
      var sawMainThread = false
      _ = QuickAccessImageOptimizer.render(
        QuickAccessOptimizeSettings(scalePercent: 100, format: .webp, qualityPercent: 80, maxFileSize: nil),
        from: original,
        source: source,
        originalExtension: "png",
        isCancelled: {
          sawMainThread = sawMainThread || Thread.isMainThread
          return false
        }
      )
      return sawMainThread
    }.value

    XCTAssertFalse(ranOnMain)
  }

  func testFileSizeLimitLowersLossyQualityToFit() throws {
    let original = try XCTUnwrap(makeNoisyImage(width: 1200, height: 800))
    let unlimited = try XCTUnwrap(QuickAccessImageOptimizer.render(
      QuickAccessOptimizeSettings(scalePercent: 100, format: .jpeg, qualityPercent: 95, maxFileSize: nil),
      from: original,
      source: source,
      originalExtension: "png"
    ))
    let limit = unlimited.data.count * 2 / 3

    let limited = try XCTUnwrap(QuickAccessImageOptimizer.render(
      QuickAccessOptimizeSettings(scalePercent: 100, format: .jpeg, qualityPercent: 95, maxFileSize: limit),
      from: original,
      source: source,
      originalExtension: "png"
    ))

    XCTAssertTrue(limited.meetsFileSizeLimit)
    XCTAssertLessThanOrEqual(limited.data.count, limit)
    XCTAssertLessThan(try XCTUnwrap(limited.qualityPercent), 95)
  }

  func testUnreachableLimitShrinksToTheMinimumAndReportsIt() throws {
    let original = try XCTUnwrap(makeNoisyImage(width: 1200, height: 800))
    let rendering = try XCTUnwrap(QuickAccessImageOptimizer.render(
      QuickAccessOptimizeSettings(scalePercent: 100, format: .png, qualityPercent: 80, maxFileSize: 10000),
      from: original,
      source: source,
      originalExtension: "png"
    ))

    XCTAssertFalse(rendering.meetsFileSizeLimit)
    XCTAssertLessThan(rendering.pixelWidth, 1200)
    XCTAssertGreaterThanOrEqual(max(rendering.pixelWidth, rendering.pixelHeight), QuickAccessImageOptimizer.minimumLongEdge - 1)
  }

  func testJPEGOutputFlattensTransparencyOntoWhite() throws {
    let transparent = try XCTUnwrap(makeTransparentImage(width: 400, height: 400))
    let small = QuickAccessOptimizeSourceInfo(pixelWidth: 400, pixelHeight: 400, nativeScale: 1)
    let rendering = try XCTUnwrap(QuickAccessImageOptimizer.render(
      QuickAccessOptimizeSettings(scalePercent: 100, format: .jpeg, qualityPercent: 90, maxFileSize: nil),
      from: transparent,
      source: small,
      originalExtension: "png"
    ))

    let decoded = try XCTUnwrap(
      CGImageSourceCreateWithData(rendering.data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    )
    let pixel = try XCTUnwrap(firstPixel(of: decoded))
    XCTAssertGreaterThan(pixel.red, 240)
    XCTAssertGreaterThan(pixel.green, 240)
    XCTAssertGreaterThan(pixel.blue, 240)
  }

  // MARK: - Presets

  @MainActor
  func testPresetStoreSeedsStartersAndPersistsEdits() throws {
    let suiteName = "QuickAccessOptimizeSettingsTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = QuickAccessOptimizePresetStore(defaults: defaults)
    XCTAssertEqual(store.presets.count, 2)

    let added = store.addPreset(
      name: "   Slack   ",
      settings: QuickAccessOptimizeSettings(scalePercent: 70, format: .webp, qualityPercent: 75, maxFileSize: nil)
    )
    XCTAssertEqual(added.name, "Slack")

    var renamed = added
    renamed.name = ""
    store.updatePreset(renamed)
    store.deletePreset(id: store.presets[0].id)
    store.setLastCustomSettings(QuickAccessOptimizeSettings(scalePercent: 40, format: .png, qualityPercent: 80, maxFileSize: nil))

    let reloaded = QuickAccessOptimizePresetStore(defaults: defaults)
    XCTAssertEqual(reloaded.presets.map(\.id), store.presets.map(\.id))
    XCTAssertEqual(reloaded.presets.last?.name, L10n.QuickAccess.optimizePresetUntitled)
    XCTAssertEqual(reloaded.lastCustomSettings.scalePercent, 40)
  }

  @MainActor
  func testDeletingEveryPresetIsRemembered() throws {
    let suiteName = "QuickAccessOptimizeSettingsTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = QuickAccessOptimizePresetStore(defaults: defaults)
    store.presets.map(\.id).forEach(store.deletePreset)

    XCTAssertTrue(QuickAccessOptimizePresetStore(defaults: defaults).presets.isEmpty)
  }

  // MARK: - Menu

  @MainActor
  func testMenuListsLevelsThenPresetsThenCustom() {
    let levels = QuickAccessImageOptimizer.levels(for: source)
    let plan = QuickAccessOptimizePlan(
      source: source,
      levels: levels,
      currentFraction: nil,
      originalByteCount: 1000,
      fileExtension: "png"
    )
    let preset = QuickAccessOptimizePreset(name: "Chat", settings: .default)
    let model = QuickAccessOptimizeMenuModel(itemID: UUID(), plan: plan, presets: [preset])

    XCTAssertEqual(model.rows.count, levels.count + 2)
    XCTAssertEqual(model.rows[levels.count].kind, .preset(preset))
    XCTAssertTrue(model.rows[levels.count].startsGroup)
    XCTAssertEqual(model.rows.last?.kind, .custom)
    // A custom result has no matching level, so the menu opens on "Custom…".
    XCTAssertNil(model.currentRowID)
    XCTAssertEqual(model.anchorIndex, model.rows.count - 1)
  }

  // MARK: - Helpers

  /// Deterministic noise so PNG cannot compress the image down to nothing.
  private func makeNoisyImage(width: Int, height: Int) -> CGImage? {
    guard let context = makeContext(width: width, height: height), let data = context.data else { return nil }
    let pixels = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
    var seed: UInt32 = 0x9E37_79B9
    for y in 0 ..< height {
      for x in 0 ..< width {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        let offset = y * context.bytesPerRow + x * 4
        pixels[offset] = UInt8(truncatingIfNeeded: seed >> 24)
        pixels[offset + 1] = UInt8(truncatingIfNeeded: (x * 255) / width)
        pixels[offset + 2] = UInt8(truncatingIfNeeded: (y * 255) / height)
        pixels[offset + 3] = 255
      }
    }
    return context.makeImage()
  }

  private func makeTransparentImage(width: Int, height: Int) -> CGImage? {
    makeContext(width: width, height: height)?.makeImage()
  }

  private func makeContext(width: Int, height: Int) -> CGContext? {
    CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  }

  private func firstPixel(of image: CGImage) -> (red: UInt8, green: UInt8, blue: UInt8)? {
    guard let context = makeContext(width: 1, height: 1), let data = context.data else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    let pixel = data.bindMemory(to: UInt8.self, capacity: 4)
    return (pixel[0], pixel[1], pixel[2])
  }
}
