//
//  AnnotateExporterTests.swift
//  SnapzyTests
//
//  Unit tests for AnnotateExporter helpers (URL generation, image scale, encoding).
//

import AppKit
import SwiftUI
import XCTest
@testable import Snapzy

@MainActor
final class AnnotateExporterTests: XCTestCase {
  private static var retainedAnnotateStates: [AnnotateState] = []

  private var tempDir: URL!

  override func setUp() {
    super.setUp()
    tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDir)
    super.tearDown()
  }

  // MARK: - generateCopyURL

  func testGenerateCopyURL_createsFirstCopy() {
    let original = tempDir.appendingPathComponent("screenshot.png")
    try? Data().write(to: original)
    let copyURL = AnnotateExporter.generateCopyURL(from: original)
    XCTAssertEqual(copyURL.lastPathComponent, "screenshot_copy.png")
  }

  func testGenerateCopyURL_incrementsWhenExists() throws {
    let original = tempDir.appendingPathComponent("screenshot.png")
    try Data().write(to: original)
    let copy1 = tempDir.appendingPathComponent("screenshot_copy.png")
    try Data().write(to: copy1)
    let copy2 = AnnotateExporter.generateCopyURL(from: original)
    XCTAssertEqual(copy2.lastPathComponent, "screenshot_copy2.png")
  }

  // MARK: - sourceImageScale / bestCGImage

  func testBestCGImage_extractsFromNSImage() {
    guard let cgImage = TestImageFactory.solidColor(width: 200, height: 100) else {
      XCTFail("Failed to create test image")
      return
    }
    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 100))
    let extracted = AnnotateExporter.bestCGImage(from: nsImage)
    XCTAssertNotNil(extracted)
    XCTAssertEqual(extracted?.width, 200)
    XCTAssertEqual(extracted?.height, 100)
  }

  func testSourceImageScale_retinaImage() {
    guard let cgImage = TestImageFactory.solidColor(width: 400, height: 400) else {
      XCTFail("Failed to create test image")
      return
    }
    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
    // sourceImageScale is private; we test indirectly via bestCGImage + size
    XCTAssertEqual(AnnotateExporter.bestCGImage(from: nsImage)?.width, 400)
  }

  // MARK: - imageData

  func testImageData_pngEncoding() {
    guard let cgImage = TestImageFactory.solidColor(width: 10, height: 10) else {
      XCTFail("Failed to create test image")
      return
    }
    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 10, height: 10))
    let data = AnnotateExporter.imageData(from: nsImage, for: "png")
    XCTAssertNotNil(data)
    XCTAssertGreaterThan(data?.count ?? 0, 0)
  }

  func testImageData_jpegEncoding() {
    guard let cgImage = TestImageFactory.solidColor(width: 10, height: 10) else {
      XCTFail("Failed to create test image")
      return
    }
    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 10, height: 10))
    let data = AnnotateExporter.imageData(from: nsImage, for: "jpg")
    XCTAssertNotNil(data)
    XCTAssertGreaterThan(data?.count ?? 0, 0)
  }

  func testImageData_unknownExtension_fallsBackToPNG() {
    guard let cgImage = TestImageFactory.solidColor(width: 10, height: 10) else {
      XCTFail("Failed to create test image")
      return
    }
    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 10, height: 10))
    let data = AnnotateExporter.imageData(from: nsImage, for: "xyz")
    XCTAssertNotNil(data)
    XCTAssertGreaterThan(data?.count ?? 0, 0)
  }

  func testImageData_nilImage_returnsNil() {
    let empty = NSImage(size: NSSize(width: 0, height: 0))
    let data = AnnotateExporter.imageData(from: empty, for: "png")
    XCTAssertNil(data)
  }

  // MARK: - Canvas shadow rendering

  func testRenderCanvasEffects_rendersRoundedShadowOutsideScreenshot() throws {
    let sourceImage = try makeSolidImage(width: 80, height: 60, pointSize: CGSize(width: 40, height: 30))
    let effects = AnnotationCanvasEffects(
      backgroundStyle: .solidColor(.white),
      padding: 30,
      shadowIntensity: 0.8,
      cornerRadius: 12,
      aspectRatio: .free
    )

    let rendered = try XCTUnwrap(AnnotateExporter.renderCanvasEffects(sourceImage: sourceImage, effects: effects))
    var effectsWithoutShadow = effects
    effectsWithoutShadow.shadowIntensity = 0
    let baseline = try XCTUnwrap(
      AnnotateExporter.renderCanvasEffects(sourceImage: sourceImage, effects: effectsWithoutShadow)
    )

    let renderedCG = try XCTUnwrap(AnnotateExporter.bestCGImage(from: rendered))
    let baselineCG = try XCTUnwrap(AnnotateExporter.bestCGImage(from: baseline))
    let renderedBytes = try rgbaBytes(from: renderedCG)
    let baselineBytes = try rgbaBytes(from: baselineCG)
    let screenshotPixelRect = CGRect(x: 60, y: 60, width: 80, height: 60)

    XCTAssertGreaterThan(
      countDarkenedPixels(
        renderedBytes,
        comparedTo: baselineBytes,
        imageWidth: renderedCG.width,
        imageHeight: renderedCG.height,
        outside: screenshotPixelRect
      ),
      100
    )

    let center = rgbaPixel(in: renderedBytes, x: 100, y: 90, width: renderedCG.width)
    XCTAssertEqual(center, [128, 128, 128, 255])

    let roundedCorner = rgbaPixel(in: renderedBytes, x: 60, y: 60, width: renderedCG.width)
    XCTAssertNotEqual(roundedCorner, [128, 128, 128, 255])
  }

  func testRenderCanvasEffects_zeroShadowLeavesBackgroundPixelsUnchanged() throws {
    let sourceImage = try makeSolidImage(width: 40, height: 30)
    let effects = AnnotationCanvasEffects(
      backgroundStyle: .solidColor(.white),
      padding: 30,
      shadowIntensity: 0,
      cornerRadius: 0,
      aspectRatio: .free
    )

    let rendered = try XCTUnwrap(AnnotateExporter.renderCanvasEffects(sourceImage: sourceImage, effects: effects))
    let renderedCG = try XCTUnwrap(AnnotateExporter.bestCGImage(from: rendered))
    let bytes = try rgbaBytes(from: renderedCG)
    let screenshotRect = CGRect(x: 30, y: 30, width: 40, height: 30)

    for y in 0..<renderedCG.height {
      for x in 0..<renderedCG.width where !screenshotRect.contains(CGPoint(x: x, y: y)) {
        XCTAssertEqual(rgbaPixel(in: bytes, x: x, y: y, width: renderedCG.width), [255, 255, 255, 255])
      }
    }
  }

  func testRenderCanvasEffects_rendersSquareShadowOverGradient() throws {
    let sourceImage = try makeSolidImage(width: 40, height: 30)
    let effects = AnnotationCanvasEffects(
      backgroundStyle: .gradient(.orangeRed),
      padding: 30,
      shadowIntensity: 0.8,
      cornerRadius: 0,
      aspectRatio: .free
    )

    let rendered = try XCTUnwrap(AnnotateExporter.renderCanvasEffects(sourceImage: sourceImage, effects: effects))
    var effectsWithoutShadow = effects
    effectsWithoutShadow.shadowIntensity = 0
    let baseline = try XCTUnwrap(
      AnnotateExporter.renderCanvasEffects(sourceImage: sourceImage, effects: effectsWithoutShadow)
    )
    let renderedCG = try XCTUnwrap(AnnotateExporter.bestCGImage(from: rendered))
    let baselineCG = try XCTUnwrap(AnnotateExporter.bestCGImage(from: baseline))

    XCTAssertGreaterThan(
      countDarkenedPixels(
        try rgbaBytes(from: renderedCG),
        comparedTo: try rgbaBytes(from: baselineCG),
        imageWidth: renderedCG.width,
        imageHeight: renderedCG.height,
        outside: CGRect(x: 30, y: 30, width: 40, height: 30)
      ),
      25
    )
  }

  func testRenderFinalImage_rendersShadowWithoutSofteningRetinaSource() throws {
    let sourceCG = try XCTUnwrap(TestImageFactory.verticalEdge(width: 80, height: 60))
    let sourceImage = NSImage(cgImage: sourceCG, size: CGSize(width: 40, height: 30))
    let state = AnnotateState()
    Self.retainedAnnotateStates.append(state)
    state.loadImage(sourceImage)
    state.backgroundStyle = .solidColor(.white)
    state.padding = 30
    state.shadowIntensity = 0.8
    state.cornerRadius = 0
    state.aspectRatio = .free

    let rendered = try XCTUnwrap(AnnotateExporter.renderFinalImage(state: state))
    let renderedCG = try XCTUnwrap(AnnotateExporter.bestCGImage(from: rendered))
    let renderedBytes = try rgbaBytes(from: renderedCG)
    let sourceBytes = try rgbaBytes(from: sourceCG)

    XCTAssertEqual(renderedCG.width, 200)
    XCTAssertEqual(renderedCG.height, 180)
    for y in 0..<sourceCG.height {
      for x in 0..<sourceCG.width {
        XCTAssertEqual(
          rgbaPixel(in: renderedBytes, x: x + 60, y: y + 60, width: renderedCG.width),
          rgbaPixel(in: sourceBytes, x: x, y: y, width: sourceCG.width)
        )
      }
    }

    var intermediateEdgePixels = 0
    for x in 60..<140 {
      let red = rgbaPixel(in: renderedBytes, x: x, y: 90, width: renderedCG.width)[0]
      if red > 0 && red < 255 {
        intermediateEdgePixels += 1
      }
    }
    XCTAssertEqual(intermediateEdgePixels, 0)
  }

  private func makeSolidImage(
    width: Int,
    height: Int,
    pointSize: CGSize? = nil
  ) throws -> NSImage {
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: width, height: height))
    return NSImage(cgImage: cgImage, size: pointSize ?? CGSize(width: width, height: height))
  }

  private func rgbaBytes(from image: CGImage) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try bytes.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(CGContext(
        data: buffer.baseAddress,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: image.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: rgbaBitmapInfo.rawValue
      ))
      context.interpolationQuality = .none
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
  }

  private func rgbaPixel(in bytes: [UInt8], x: Int, y: Int, width: Int) -> [UInt8] {
    let index = (y * width + x) * 4
    return Array(bytes[index..<(index + 4)])
  }

  private func countDarkenedPixels(
    _ rendered: [UInt8],
    comparedTo baseline: [UInt8],
    imageWidth: Int,
    imageHeight: Int,
    outside screenshotRect: CGRect
  ) -> Int {
    var count = 0
    for y in 0..<imageHeight {
      for x in 0..<imageWidth where !screenshotRect.contains(CGPoint(x: x, y: y)) {
        let index = (y * imageWidth + x) * 4
        let renderedLuminance = Int(rendered[index]) + Int(rendered[index + 1]) + Int(rendered[index + 2])
        let baselineLuminance = Int(baseline[index]) + Int(baseline[index + 1]) + Int(baseline[index + 2])
        if renderedLuminance + 6 < baselineLuminance {
          count += 1
        }
      }
    }
    return count
  }

  private var rgbaBitmapInfo: CGBitmapInfo {
    CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
  }
}
