//
//  ColorPickerSessionTests.swift
//  SnapzyTests
//
//  Pick Color overlay view and session tests. They put real overlay windows on screen and
//  rely on main-actor deinits running on a live run loop, which the headless GitHub Actions
//  runner does not provide (it aborts in the back-deployed `swift_task_deinitOnExecutor`),
//  so they are skipped in CI (`SNAPZY_CI_SKIP_TESTS` in .github/workflows/ci.yml) and run
//  locally.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class ColorPickerSessionTests: XCTestCase {

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

  // MARK: - Overlay view and loupe

  func testOverlayView_showsNothingUntilPixelsArriveThenFollowsPointer() async throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    let view = ColorPickerOverlayView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
    view.testPointerMoved(to: CGPoint(x: 10.5, y: 10.5))
    XCTAssertNil(view.currentColor)
    XCTAssertNil(view.testLoupe.containerLayer)

    view.pixelSource = try await startedSource(ColorPickerTestImages.splitImage(width: 800, height: 600))

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
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    let view = ColorPickerOverlayView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
    let source = MutablePixelSource(image: ColorPickerTestImages.splitImage(width: 800, height: 600))
    view.pixelSource = source
    view.testPointerMoved(to: CGPoint(x: 10, y: 10))
    XCTAssertEqual(view.currentColor?.hex, "#FF0000")

    source.image = ColorPickerTestImages.image(width: 800, height: 600, colorSpace: ColorPickerTestImages.sRGB) { _, _ in (0, 255, 0) }
    source.onUpdate?()

    XCTAssertEqual(view.currentColor?.hex, "#00FF00")
    XCTAssertEqual(view.testLoupe.hexTextLayer?.string as? String, "#00FF00")
  }

  func testOverlayView_detachingSourceHidesLoupe() async throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    let view = try await makeOverlayView()
    view.testPointerMoved(to: CGPoint(x: 10, y: 10))
    XCTAssertFalse(view.testLoupe.containerLayer?.isHidden ?? true)

    view.pixelSource = nil

    XCTAssertNil(view.currentColor)
    XCTAssertTrue(view.testLoupe.containerLayer?.isHidden ?? false)
  }

  func testOverlayView_arrowNudgesMoveOnePixelAndClamp() async throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
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
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
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
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
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
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
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
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    let view = ColorPickerOverlayView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
    let delegate = RecordingDelegate()
    view.delegate = delegate

    view.rightMouseDown(with: try mouseEvent(.rightMouseDown, at: CGPoint(x: 10, y: 10)))

    XCTAssertEqual(delegate.cancelCount, 1)
    XCTAssertTrue(delegate.pickedColors.isEmpty)
  }

  // MARK: - Controller

  func testController_overlaysAreSeeThroughVisibleToRecordersAndExcludedFromSampling() async throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    let capture = FakeCapture(image: ColorPickerTestImages.splitImage)
    let controller = makeController(capture: capture)

    controller.start()
    let windows = controller.testWindows
    XCTAssertEqual(windows.count, NSScreen.screens.count)
    XCTAssertTrue(windows.allSatisfy { !$0.isOpaque && $0.sharingType == .readOnly })
    try await waitUntil { controller.testStreamingDisplayID != nil }

    XCTAssertEqual(Set(capture.excludedWindowNumbers), Set(windows.map(\.windowNumber)))
    controller.cancel()
  }

  func testController_pickCopiesInTheChosenFormatShowsResultAndEndsSession() async throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    var copied: [String] = []
    var toasts: [(String, AppToastStyle)] = []
    var results: [(ColorPickerColor, ColorPickerFormat)] = []
    let preferences = ColorPickerPreferences(defaults: UserDefaultsFactory.make())
    preferences.copyFormat = .rgb
    let controller = makeController(
      capture: FakeCapture(image: ColorPickerTestImages.splitImage),
      copied: { copied.append($0) },
      toasts: { toasts.append(($0, $1)) },
      results: { results.append(($0, $1)) },
      preferences: preferences
    )

    controller.start()
    XCTAssertTrue(controller.isActive)
    let window = try XCTUnwrap(controller.testWindows.first)
    let picked = ColorPickerColor(red: 0x12, green: 0xAB, blue: 0x34)

    controller.colorPickerOverlayView(window.overlayView, didPick: picked)

    XCTAssertFalse(controller.isActive)
    XCTAssertTrue(controller.testWindows.isEmpty)
    XCTAssertNil(controller.testStreamingDisplayID)
    XCTAssertEqual(copied, ["rgb(18, 171, 52)"])
    XCTAssertEqual(results.map(\.0), [picked])
    XCTAssertEqual(results.map(\.1), [.rgb])
    XCTAssertTrue(toasts.isEmpty)
  }

  func testController_cancelCopiesNothing() async throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    var copied: [String] = []
    let controller = makeController(capture: FakeCapture(image: ColorPickerTestImages.splitImage), copied: { copied.append($0) })

    controller.start()
    let window = try XCTUnwrap(controller.testWindows.first)
    controller.colorPickerOverlayViewDidCancel(window.overlayView)

    XCTAssertFalse(controller.isActive)
    XCTAssertTrue(controller.testWindows.isEmpty)
    XCTAssertTrue(copied.isEmpty)
  }

  func testController_toggleWhilePreparingNeverStreams() async throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    let capture = FakeCapture(image: ColorPickerTestImages.splitImage)
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
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    var toasts: [(String, AppToastStyle)] = []
    let capture = FakeCapture(image: ColorPickerTestImages.splitImage)
    capture.prepareError = CaptureError.permissionDenied
    let controller = makeController(capture: capture, toasts: { toasts.append(($0, $1)) })

    controller.start()
    try await waitUntil { !controller.isActive }

    XCTAssertTrue(controller.testWindows.isEmpty)
    XCTAssertEqual(toasts.map(\.0), [L10n.ScreenCapture.colorPickerUnavailable])
    XCTAssertEqual(toasts.map(\.1), [.error])
  }

  // MARK: - Result window

  func testResultWindow_isANativeWindowThatCopiesFormatsAndStaysForPickAgain() async throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    var copied: [String] = []
    var pickAgainCount = 0
    let preferences = ColorPickerPreferences(defaults: UserDefaultsFactory.make())
    let controller = ColorPickerResultWindowController(
      copyToPasteboard: { copied.append($0) },
      onPickAgain: { pickAgainCount += 1 },
      preferences: preferences
    )
    let color = ColorPickerColor(red: 0x1A, green: 0x2B, blue: 0x3C)

    controller.show(color: color, copiedFormat: .hex, near: CGPoint(x: 200, y: 400))
    let window = try XCTUnwrap(controller.testWindow)
    XCTAssertTrue(controller.isVisible)
    XCTAssertTrue(window.styleMask.contains(.titled))
    XCTAssertTrue(window.styleMask.contains(.closable))
    XCTAssertTrue(window.styleMask.contains(.miniaturizable))
    XCTAssertEqual(window.title, L10n.Actions.pickColor)
    XCTAssertEqual(controller.testRecentColors, [color])

    controller.testCopy(.hsl)
    XCTAssertEqual(copied, ["hsl(210, 40%, 17%)"])
    XCTAssertEqual(controller.testCopiedFormat, .hsl)

    controller.testPickAgain()
    XCTAssertEqual(pickAgainCount, 1)
    XCTAssertTrue(controller.isVisible)

    // A second pick reuses the same window and joins the recent colors.
    let red = ColorPickerColor(red: 255, green: 0, blue: 0)
    controller.show(color: red, copiedFormat: .hex, near: .zero)
    XCTAssertTrue(controller.testWindow === window)
    XCTAssertEqual(controller.testCopiedFormat, .hex)
    XCTAssertEqual(controller.testRecentColors, [red, color])

    // Choosing a recent color brings it back and copies it the way a pick would.
    controller.testSetCopyOnPickFormat(.swiftUI)
    XCTAssertEqual(preferences.copyFormat, .swiftUI)
    controller.testSelectRecent(color)
    XCTAssertEqual(controller.testColor, color)
    XCTAssertEqual(copied.last, "Color(red: 0.102, green: 0.169, blue: 0.235)")
    XCTAssertEqual(controller.testCopiedFormat, .swiftUI)
    XCTAssertEqual(controller.testRecentColors, [color, red])

    controller.close()
    XCTAssertFalse(controller.isVisible)
  }

  // MARK: - Helpers

  private nonisolated final class RecordingDelegate: ColorPickerOverlayViewDelegate {
    var pickedColors: [String] = []
    var cancelCount = 0

    func colorPickerOverlayView(_ view: ColorPickerOverlayView, didPick color: ColorPickerColor) {
      pickedColors.append(color.hex)
    }

    func colorPickerOverlayViewDidCancel(_ view: ColorPickerOverlayView) {
      cancelCount += 1
    }

    func colorPickerOverlayViewDidReceivePointer(_ view: ColorPickerOverlayView) {}
  }

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
    view.pixelSource = try await startedSource(ColorPickerTestImages.splitImage(width: 800, height: 600))
    return view
  }

  private func makeController(
    capture: FakeCapture,
    copied: @escaping (String) -> Void = { _ in },
    toasts: @escaping (String, AppToastStyle) -> Void = { _, _ in },
    results: @escaping (ColorPickerColor, ColorPickerFormat) -> Void = { _, _ in },
    preferences: ColorPickerPreferences = ColorPickerPreferences(defaults: UserDefaultsFactory.make())
  ) -> ColorPickerController {
    ColorPickerController(
      makeCapture: { capture },
      copyToPasteboard: copied,
      showToast: toasts,
      presentResult: { color, format, _ in results(color, format) },
      preferences: preferences,
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
}
