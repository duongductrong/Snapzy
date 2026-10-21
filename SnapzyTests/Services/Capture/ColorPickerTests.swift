//
//  ColorPickerTests.swift
//  SnapzyTests
//
//  Unit tests for the standalone Pick Color session, its loupe, and pixel sampling.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class ColorPickerTests: XCTestCase {

  override func setUp() {
    super.setUp()
    UserDefaults.standard.removeObject(forKey: PreferencesKeys.colorPickerLoupeCellSizeIndex)
    UserDefaults.standard.removeObject(forKey: PreferencesKeys.colorPickerLoupeDiameterIndex)
  }

  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: PreferencesKeys.colorPickerLoupeCellSizeIndex)
    UserDefaults.standard.removeObject(forKey: PreferencesKeys.colorPickerLoupeDiameterIndex)
    super.tearDown()
  }

  // MARK: - Pixel sampler

  func testSampler_mapsBottomLeftPointsToTopLeftPixels() {
    let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)

    // 2× snapshot: each point covers 2×2 pixels.
    XCTAssertEqual(
      ColorPickerPixelSampler.pixel(at: CGPoint(x: 0.2, y: 49.9), bounds: bounds, imageWidth: 200, imageHeight: 100),
      ColorPickerPixel(x: 0, y: 0)
    )
    XCTAssertEqual(
      ColorPickerPixelSampler.pixel(at: CGPoint(x: 10.6, y: 0.1), bounds: bounds, imageWidth: 200, imageHeight: 100),
      ColorPickerPixel(x: 21, y: 99)
    )
    XCTAssertEqual(
      ColorPickerPixelSampler.pixel(at: CGPoint(x: 500, y: -20), bounds: bounds, imageWidth: 200, imageHeight: 100),
      ColorPickerPixel(x: 199, y: 99)
    )
  }

  func testSampler_pixelCenterRoundTrips() {
    let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
    for pixel in [ColorPickerPixel(x: 0, y: 0), ColorPickerPixel(x: 37, y: 61), ColorPickerPixel(x: 199, y: 99)] {
      let center = ColorPickerPixelSampler.point(forCenterOf: pixel, bounds: bounds, imageWidth: 200, imageHeight: 100)
      XCTAssertEqual(
        ColorPickerPixelSampler.pixel(at: center, bounds: bounds, imageWidth: 200, imageHeight: 100),
        pixel
      )
    }
  }

  func testSampler_readsExactSRGBValues() throws {
    let image = makeImage(width: 4, height: 4, colorSpace: srgb) { x, _ in
      x < 2 ? (0x1A, 0x2B, 0x3C) : (0xFF, 0x80, 0x00)
    }

    XCTAssertEqual(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 1, y: 2), in: image)?.hex, "#1A2B3C")
    XCTAssertEqual(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 3, y: 0), in: image)?.hex, "#FF8000")
  }

  func testSampler_convertsDisplayP3ToSRGB() throws {
    // sRGB #3366CC expressed in Display P3, as a wide-gamut display would hold it.
    let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
    let source = CGColor(srgbRed: 0x33 / 255.0, green: 0x66 / 255.0, blue: 0xCC / 255.0, alpha: 1)
    let inP3 = try XCTUnwrap(source.converted(to: p3, intent: .relativeColorimetric, options: nil)?.components)
    let image = makeImage(width: 1, height: 1, colorSpace: p3) { _, _ in
      (UInt8((inP3[0] * 255).rounded()), UInt8((inP3[1] * 255).rounded()), UInt8((inP3[2] * 255).rounded()))
    }

    let color = try XCTUnwrap(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 0, y: 0), in: image))
    XCTAssertEqual(Int(color.red), 0x33, accuracy: 1)
    XCTAssertEqual(Int(color.green), 0x66, accuracy: 1)
    XCTAssertEqual(Int(color.blue), 0xCC, accuracy: 1)
  }

  func testSampler_neighborhoodIsCenteredAndBlackOutsideImage() throws {
    let image = makeImage(width: 5, height: 5, colorSpace: srgb) { x, y in
      (x == 0 && y == 0) ? (255, 255, 255) : (0, 0, 255)
    }

    let neighborhood = try XCTUnwrap(
      ColorPickerPixelSampler.neighborhood(of: ColorPickerPixel(x: 0, y: 0), radius: 1, in: image)
    )
    XCTAssertEqual(neighborhood.width, 3)
    XCTAssertEqual(neighborhood.height, 3)
    // Center = the sampled pixel; above/left of it is off the image.
    XCTAssertEqual(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 1, y: 1), in: neighborhood)?.hex, "#FFFFFF")
    XCTAssertEqual(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 0, y: 0), in: neighborhood)?.hex, "#000000")
    XCTAssertEqual(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 2, y: 2), in: neighborhood)?.hex, "#0000FF")
  }

  // MARK: - Pixel buffer reader (live stream frames)

  func testPixelBufferReader_readsBGRAFrames() throws {
    let buffer = try makePixelBuffer(width: 6, height: 4) { x, y in
      x == 2 && y == 1 ? (0x1A, 0x2B, 0x3C) : (0, 0, 255)
    }

    XCTAssertEqual(ColorPickerPixelBufferReader.color(of: ColorPickerPixel(x: 2, y: 1), in: buffer)?.hex, "#1A2B3C")
    XCTAssertEqual(ColorPickerPixelBufferReader.color(of: ColorPickerPixel(x: 99, y: 99), in: buffer)?.hex, "#0000FF")

    let neighborhood = try XCTUnwrap(
      ColorPickerPixelBufferReader.neighborhood(of: ColorPickerPixel(x: 2, y: 1), radius: 2, in: buffer)
    )
    XCTAssertEqual(neighborhood.width, 5)
    XCTAssertEqual(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 2, y: 2), in: neighborhood)?.hex, "#1A2B3C")
    // Row above the frame is black; the row below the center is still inside the frame.
    XCTAssertEqual(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 2, y: 0), in: neighborhood)?.hex, "#000000")
    XCTAssertEqual(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 2, y: 3), in: neighborhood)?.hex, "#0000FF")
  }

  // MARK: - Overlay view and loupe

  // Tests that create main-actor objects are `async`: their isolated deinits then run inside a
  // task. Run outside one after other async tests, the back-deployed deinit hop aborts on
  // macOS 13–15 (see `ColorPickerStreamPixelSource`).

  func testOverlayView_showsNothingUntilPixelsArriveThenFollowsPointer() async throws {
    let view = ColorPickerOverlayView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
    view.testPointerMoved(to: CGPoint(x: 10.5, y: 10.5))
    XCTAssertNil(view.currentColor)
    XCTAssertNil(view.testLoupe.containerLayer)

    view.pixelSource = try await startedSource(makeSplitImage(width: 800, height: 600))

    // 2× content: (10.5, 10.5) pt is pixel (21, 579), whose center is (10.75, 10.25) pt.
    XCTAssertEqual(view.currentPixel, ColorPickerPixel(x: 21, y: 579))
    XCTAssertEqual(view.currentColor?.hex, "#FF0000")
    let container = try XCTUnwrap(view.testLoupe.containerLayer)
    XCTAssertFalse(container.isHidden)
    XCTAssertEqual(container.frame.midX, 10.75, accuracy: 0.001)
    XCTAssertEqual(container.frame.midY, 10.25, accuracy: 0.001)
    XCTAssertEqual(view.testLoupe.hexTextLayer?.string as? String, "#FF0000")
  }

  func testOverlayView_newFramesResampleTheSamePixel() async throws {
    let view = ColorPickerOverlayView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
    let source = MutablePixelSource(image: makeSplitImage(width: 800, height: 600))
    view.pixelSource = source
    view.testPointerMoved(to: CGPoint(x: 10, y: 10))
    XCTAssertEqual(view.currentColor?.hex, "#FF0000")

    source.image = makeImage(width: 800, height: 600, colorSpace: srgb) { _, _ in (0, 255, 0) }
    source.onUpdate?()

    XCTAssertEqual(view.currentColor?.hex, "#00FF00")
    XCTAssertEqual(view.testLoupe.hexTextLayer?.string as? String, "#00FF00")
  }

  func testOverlayView_detachingSourceHidesLoupe() async throws {
    let view = try await makeOverlayView()
    view.testPointerMoved(to: CGPoint(x: 10, y: 10))
    XCTAssertFalse(view.testLoupe.containerLayer?.isHidden ?? true)

    view.pixelSource = nil

    XCTAssertNil(view.currentColor)
    XCTAssertTrue(view.testLoupe.containerLayer?.isHidden ?? false)
  }

  func testOverlayView_arrowNudgesMoveOnePixelAndClamp() async throws {
    let view = try await makeOverlayView()
    view.testPointerMoved(to: CGPoint(x: 199.5, y: 150))
    // Last red pixel column is 399 of 800.
    XCTAssertEqual(view.currentPixel?.x, 399)
    XCTAssertEqual(view.currentColor?.hex, "#FF0000")

    view.nudge(dx: 1, dy: 0)
    XCTAssertEqual(view.currentPixel?.x, 400)
    XCTAssertEqual(view.currentColor?.hex, "#0000FF")

    view.nudge(dx: 10_000, dy: -10_000)
    XCTAssertEqual(view.currentPixel, ColorPickerPixel(x: 799, y: 0))
  }

  func testOverlayView_clickCopiesTheNudgedPixel() async throws {
    let view = try await makeOverlayView()
    let delegate = RecordingDelegate()
    view.delegate = delegate
    view.testPointerMoved(to: CGPoint(x: 199.5, y: 150))
    view.nudge(dx: 1, dy: 0)

    // The click lands on the red half, but the loupe shows (and copies) the nudged blue pixel.
    view.mouseDown(with: try mouseEvent(.leftMouseDown, at: CGPoint(x: 199.5, y: 150)))

    XCTAssertEqual(delegate.pickedColors, ["#0000FF"])
  }

  func testOverlayView_scrollZoomsAndOptionScrollResizesWithinLimits() async throws {
    let view = try await makeOverlayView()
    view.testPointerMoved(to: CGPoint(x: 50, y: 50))
    let loupe = view.testLoupe
    let startCell = loupe.cellSizeIndex
    let startDiameter = loupe.diameterIndex

    view.applyScroll(delta: 1, hasPreciseScrollingDeltas: false, resizesLoupe: false)
    XCTAssertNotEqual(loupe.cellSizeIndex, startCell)
    XCTAssertEqual(loupe.diameterIndex, startDiameter)

    view.applyScroll(delta: 1, hasPreciseScrollingDeltas: false, resizesLoupe: true)
    XCTAssertNotEqual(loupe.diameterIndex, startDiameter)

    for _ in 0..<50 {
      view.applyScroll(delta: 1, hasPreciseScrollingDeltas: false, resizesLoupe: false)
      view.applyScroll(delta: 1, hasPreciseScrollingDeltas: false, resizesLoupe: true)
    }
    XCTAssertTrue([0, ColorPickerLoupe.cellSizes.count - 1].contains(loupe.cellSizeIndex))
    XCTAssertTrue([0, ColorPickerLoupe.diameters.count - 1].contains(loupe.diameterIndex))
    XCTAssertFalse(loupe.containerLayer?.isHidden ?? true)
  }

  func testOverlayView_preciseScrollNeedsAFullStep() async throws {
    let view = try await makeOverlayView()
    view.testPointerMoved(to: CGPoint(x: 50, y: 50))
    let start = view.testLoupe.cellSizeIndex

    view.applyScroll(delta: 3, hasPreciseScrollingDeltas: true, resizesLoupe: false)
    XCTAssertEqual(view.testLoupe.cellSizeIndex, start)

    for _ in 0..<4 {
      view.applyScroll(delta: 3, hasPreciseScrollingDeltas: true, resizesLoupe: false)
    }
    XCTAssertNotEqual(view.testLoupe.cellSizeIndex, start)
  }

  func testOverlayView_rightClickCancels() async throws {
    let view = ColorPickerOverlayView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
    let delegate = RecordingDelegate()
    view.delegate = delegate

    view.rightMouseDown(with: try mouseEvent(.rightMouseDown, at: CGPoint(x: 10, y: 10)))

    XCTAssertEqual(delegate.cancelCount, 1)
    XCTAssertTrue(delegate.pickedColors.isEmpty)
  }

  func testLoupe_radiusAlwaysCoversTheCircle() {
    for cellIndex in ColorPickerLoupe.cellSizes.indices {
      for diameterIndex in ColorPickerLoupe.diameters.indices {
        let loupe = ColorPickerLoupe(cellSizeIndex: cellIndex, diameterIndex: diameterIndex, hintText: "")
        XCTAssertGreaterThanOrEqual(CGFloat(loupe.radiusInPixels * 2 + 1) * loupe.cellSize, loupe.diameter)
      }
    }
  }

  // MARK: - Controller

  func testController_overlaysAreSeeThroughAndExcludedFromCapture() async throws {
    let capture = FakeCapture(image: makeSplitImage)
    let controller = makeController(capture: capture)

    controller.start()
    let windows = controller.testWindows
    XCTAssertEqual(windows.count, NSScreen.screens.count)
    XCTAssertTrue(windows.allSatisfy { !$0.isOpaque && $0.sharingType == .none })
    try await waitUntil { controller.testStreamingDisplayID != nil }

    XCTAssertEqual(Set(capture.excludedWindowNumbers), Set(windows.map(\.windowNumber)))
    controller.cancel()
  }

  func testController_pickCopiesHexAndEndsSession() async throws {
    var copied: [String] = []
    var toasts: [(String, AppToastStyle)] = []
    let controller = makeController(
      capture: FakeCapture(image: makeSplitImage),
      copied: { copied.append($0) },
      toasts: { toasts.append(($0, $1)) }
    )

    controller.start()
    XCTAssertTrue(controller.isActive)
    let window = try XCTUnwrap(controller.testWindows.first)

    controller.colorPickerOverlayView(window.overlayView, didPickColor: "#12AB34")

    XCTAssertFalse(controller.isActive)
    XCTAssertTrue(controller.testWindows.isEmpty)
    XCTAssertNil(controller.testStreamingDisplayID)
    XCTAssertEqual(copied, ["#12AB34"])
    XCTAssertEqual(toasts.map(\.0), [L10n.ScreenCapture.colorPickerCopied("#12AB34")])
    XCTAssertEqual(toasts.map(\.1), [.success])
  }

  func testController_cancelCopiesNothing() async throws {
    var copied: [String] = []
    let controller = makeController(capture: FakeCapture(image: makeSplitImage), copied: { copied.append($0) })

    controller.start()
    let window = try XCTUnwrap(controller.testWindows.first)
    controller.colorPickerOverlayViewDidCancel(window.overlayView)

    XCTAssertFalse(controller.isActive)
    XCTAssertTrue(controller.testWindows.isEmpty)
    XCTAssertTrue(copied.isEmpty)
  }

  func testController_toggleWhilePreparingNeverStreams() async throws {
    let capture = FakeCapture(image: makeSplitImage)
    let controller = makeController(capture: capture)

    controller.toggle()
    XCTAssertTrue(controller.isActive)
    controller.toggle()
    XCTAssertFalse(controller.isActive)

    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertTrue(controller.testWindows.isEmpty)
    XCTAssertNil(controller.testStreamingDisplayID)
    XCTAssertFalse(controller.isActive)
  }

  func testController_captureFailureShowsErrorAndEnds() async throws {
    var toasts: [(String, AppToastStyle)] = []
    let capture = FakeCapture(image: makeSplitImage)
    capture.prepareError = CaptureError.permissionDenied
    let controller = makeController(capture: capture, toasts: { toasts.append(($0, $1)) })

    controller.start()
    try await waitUntil { !controller.isActive }

    XCTAssertTrue(controller.testWindows.isEmpty)
    XCTAssertEqual(toasts.map(\.0), [L10n.ScreenCapture.colorPickerUnavailable])
    XCTAssertEqual(toasts.map(\.1), [.error])
  }

  // MARK: - Shortcut wiring

  func testPickColorShortcutShipsUnbound() {
    XCTAssertEqual(GlobalShortcutKind.pickColor.configKey, "pick_color")
    XCTAssertFalse(GlobalShortcutKind.pickColor.isSystemConflictRelevant)
    XCTAssertEqual(GlobalShortcutKind.pickColor.displayName, L10n.Actions.pickColor)
    XCTAssertEqual(MenuBarItemKind.pickColor.group, .tools)
  }

  // MARK: - Helpers

  private nonisolated final class RecordingDelegate: ColorPickerOverlayViewDelegate {
    var pickedColors: [String] = []
    var cancelCount = 0

    func colorPickerOverlayView(_ view: ColorPickerOverlayView, didPickColor hex: String) {
      pickedColors.append(hex)
    }

    func colorPickerOverlayViewDidCancel(_ view: ColorPickerOverlayView) {
      cancelCount += 1
    }

    func colorPickerOverlayViewDidReceivePointer(_ view: ColorPickerOverlayView) {}
  }

  private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

  /// A pixel source whose content tests can swap, like a stream delivering a new frame.
  /// Nonisolated like the real sources (see `ColorPickerStreamPixelSource`).
  private nonisolated final class MutablePixelSource: ColorPickerPixelSource {
    var onUpdate: (() -> Void)?
    var image: CGImage

    init(image: CGImage) {
      self.image = image
    }

    var pixelSize: (width: Int, height: Int)? { (image.width, image.height) }

    func neighborhood(of pixel: ColorPickerPixel, radius: Int) -> CGImage? {
      ColorPickerPixelSampler.neighborhood(of: pixel, radius: radius, in: image)
    }

    func color(of pixel: ColorPickerPixel) -> ColorPickerColor? {
      ColorPickerPixelSampler.color(of: pixel, in: image)
    }

    func start() async throws {}
    func stop() {}
  }

  private final class FakeCapture: ColorPickerCapturing {
    var prepareError: Error?
    private(set) var excludedWindowNumbers: [Int] = []
    private let image: (Int, Int) -> CGImage

    init(image: @escaping (Int, Int) -> CGImage) {
      self.image = image
    }

    func prepare(excludingWindowNumbers windowNumbers: [Int]) async throws {
      excludedWindowNumbers = windowNumbers
      await Task.yield()
      if let prepareError { throw prepareError }
    }

    func source(for screen: NSScreen) -> ColorPickerPixelSource? {
      ColorPickerImagePixelSource(image: image(Int(screen.frame.width), Int(screen.frame.height)))
    }
  }

  private func startedSource(_ image: CGImage) async throws -> ColorPickerImagePixelSource {
    let source = ColorPickerImagePixelSource(image: image)
    try await source.start()
    return source
  }

  /// 400×300 pt view over 800×600 (2×) content: left half red, right half blue.
  private func makeOverlayView() async throws -> ColorPickerOverlayView {
    let view = ColorPickerOverlayView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
    view.warpPointer = { _ in }
    view.pixelSource = try await startedSource(makeSplitImage(width: 800, height: 600))
    return view
  }

  private func makeController(
    capture: FakeCapture,
    copied: @escaping (String) -> Void = { _ in },
    toasts: @escaping (String, AppToastStyle) -> Void = { _, _ in }
  ) -> ColorPickerController {
    ColorPickerController(
      makeCapture: { capture },
      copyToPasteboard: copied,
      showToast: toasts,
      setsCursorHidden: false
    )
  }

  private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
      guard Date() < deadline else {
        XCTFail("Timed out waiting for condition")
        return
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
  }

  private func mouseEvent(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
    try XCTUnwrap(NSEvent.mouseEvent(
      with: type,
      location: point,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: 1
    ))
  }

  /// A 32BGRA buffer, the format the live stream delivers. `pixel(x, y)` is top-left based.
  private func makePixelBuffer(
    width: Int,
    height: Int,
    pixel: (Int, Int) -> (UInt8, UInt8, UInt8)
  ) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
    XCTAssertEqual(status, kCVReturnSuccess)
    let pixelBuffer = try XCTUnwrap(buffer)
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer)).assumingMemoryBound(to: UInt8.self)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    for y in 0..<height {
      for x in 0..<width {
        let (r, g, b) = pixel(x, y)
        let offset = y * bytesPerRow + x * 4
        base[offset] = b
        base[offset + 1] = g
        base[offset + 2] = r
        base[offset + 3] = 255
      }
    }
    return pixelBuffer
  }

  private func makeSplitImage(width: Int, height: Int) -> CGImage {
    makeImage(width: width, height: height, colorSpace: srgb) { x, _ in
      x < width / 2 ? (255, 0, 0) : (0, 0, 255)
    }
  }

  /// `pixel(x, y)` uses top-left pixel coordinates, like `ColorPickerPixel`.
  private func makeImage(
    width: Int,
    height: Int,
    colorSpace: CGColorSpace,
    pixel: (Int, Int) -> (UInt8, UInt8, UInt8)
  ) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let (r, g, b) = pixel(x, y)
        let offset = (y * width + x) * 4
        bytes[offset] = r
        bytes[offset + 1] = g
        bytes[offset + 2] = b
      }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )!
  }
}
