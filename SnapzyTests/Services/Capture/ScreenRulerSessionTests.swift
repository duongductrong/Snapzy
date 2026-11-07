//
//  ScreenRulerSessionTests.swift
//  SnapzyTests
//
//  Screen Ruler overlay view and session tests. Like `ColorPickerSessionTests` they put real
//  overlay windows on screen and need a live main run loop, so they are skipped in CI
//  (`SNAPZY_CI_SKIP_TESTS`) and run locally.
//

import AppKit
import Carbon.HIToolbox
import XCTest
import SnapzyMeasureCore
@testable import Snapzy

@MainActor
final class ScreenRulerSessionTests: XCTestCase {

  // MARK: - Overlay view

  func testOverlayView_pointerMeasuresSpanAroundIt() throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    let view = try makeView()

    // 2× snapshot: (30, 280) pt in a 400×300 pt view is pixel (60, 40), inside the box.
    view.pointerMoved(to: CGPoint(x: 30, y: 280))

    XCTAssertEqual(view.pointerPixel, ColorPickerPixel(x: 60, y: 40))
    guard case .span(let span) = view.live else { return XCTFail("Expected a span") }
    XCTAssertEqual(span.width, 78) // pixels 41…118
    XCTAssertEqual(span.height, 58) // pixels 21…78
    XCTAssertEqual(ScreenRulerFormatter.label(for: try XCTUnwrap(view.live), scaleX: view.scaleX, scaleY: view.scaleY, unit: .points), "39 × 29")
  }

  func testOverlayView_axisLockAndUnitChangeTheLiveMeasurement() throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    let view = try makeView()
    view.pointerMoved(to: CGPoint(x: 30, y: 280))

    view.axis = .horizontal
    XCTAssertNil(view.live?.pixelHeight)
    XCTAssertEqual(view.live?.pixelWidth, 78)
    view.unit = .pixels
    XCTAssertEqual(ScreenRulerFormatter.label(for: try XCTUnwrap(view.live), scaleX: view.scaleX, scaleY: view.scaleY, unit: view.unit), "78")
  }

  func testOverlayView_clickPinsTheSpanAndDeleteRemovesIt() throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    let view = try makeView()
    view.pointerMoved(to: CGPoint(x: 30, y: 280))

    view.press(at: CGPoint(x: 30, y: 280))
    view.release()
    XCTAssertEqual(view.pins.count, 1)
    XCTAssertEqual(view.pins.first, view.live)

    view.removeLastPin()
    XCTAssertTrue(view.pins.isEmpty)
  }

  func testOverlayView_dragPinsABoxSnappedToContent() throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    let view = try makeView()
    view.commandKeyIsDown = { false }

    // From pixel (10, 10) to (150, 100): around the box at pixels 40…119 × 20…79.
    view.press(at: CGPoint(x: 5, y: 295))
    view.drag(to: CGPoint(x: 75, y: 250))
    XCTAssertNotNil(view.dragBox)
    view.release()

    XCTAssertNil(view.dragBox)
    XCTAssertEqual(view.pins, [.box(ScreenRulerPixelRect(minX: 40, minY: 20, maxX: 119, maxY: 79))])
  }

  func testOverlayView_commandDragKeepsTheRawBox() throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    let view = try makeView()
    view.commandKeyIsDown = { true }

    view.press(at: CGPoint(x: 5, y: 295))
    view.drag(to: CGPoint(x: 75, y: 250))
    view.release()

    XCTAssertEqual(view.pins, [.box(ScreenRulerPixelRect(minX: 10, minY: 10, maxX: 150, maxY: 100))])
  }

  func testOverlayView_smallPointerTravelIsStillAClick() throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    let view = try makeView()
    view.press(at: CGPoint(x: 30, y: 280))
    view.drag(to: CGPoint(x: 30.5, y: 280))
    XCTAssertNil(view.dragBox)
    view.release()
    guard case .span = view.pins.first else { return XCTFail("Expected a pinned span") }
  }

  func testOverlayView_clickJitterUnderFourPointsIsStillAClick() throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    let view = try makeView()
    view.press(at: CGPoint(x: 30, y: 280))
    // 3 pt of travel on a 2× snapshot is 6 px: still below the 4 pt drag threshold.
    view.drag(to: CGPoint(x: 33, y: 280))
    XCTAssertNil(view.dragBox)
    view.drag(to: CGPoint(x: 34.5, y: 280))
    XCTAssertNotNil(view.dragBox)
  }

  func testOverlayView_exportDrawingDropsTheReticleAndHint() throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    let view = try makeView()
    view.hint = "hint"
    view.pointerMoved(to: CGPoint(x: 30, y: 280))

    let screen = view.drawing(forExport: false)
    XCTAssertNotNil(screen.pointer)
    XCTAssertEqual(screen.hint, "hint")

    let export = view.drawing(forExport: true)
    XCTAssertNil(export.pointer)
    XCTAssertNil(export.hint)
    XCTAssertEqual(export.live, view.live, "With no pins, the file keeps the live measurement")

    view.press(at: CGPoint(x: 30, y: 280))
    view.release()
    XCTAssertNil(view.drawing(forExport: true).live, "Pins replace the live measurement in the file")
  }

  func testRenderer_imageKeepsSnapshotPixelSize() throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    let view = try makeView()
    view.pointerMoved(to: CGPoint(x: 30, y: 280))

    let image = try XCTUnwrap(ScreenRulerRenderer.renderImage(view.snapshot.image, drawing: view.drawing(forExport: true)))

    XCTAssertEqual(image.width, 800)
    XCTAssertEqual(image.height, 600)
    // The horizontal span runs along pixel row 40 (the pointer's row), top-left based.
    let onLine = try XCTUnwrap(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 80, y: 40), in: image))
    XCTAssertGreaterThan(onLine.red, 200)
    XCTAssertLessThan(onLine.green, 140)
    let offLine = try XCTUnwrap(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 80, y: 50), in: image))
    XCTAssertEqual(offLine.hex, "#FFFFFF")
  }

  func testRenderer_followsPerAxisScaleOnNonUniformDisplays() throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    // 800×600 px shown in 400×320 pt: 2× across, 1.875× down.
    let snapshot = FrozenDisplaySnapshot(
      displayID: 1,
      screenFrame: CGRect(x: 0, y: 0, width: 400, height: 320),
      scaleFactor: 2,
      colorSpaceName: CGColorSpace.sRGB,
      image: Self.boxedImage()
    )
    let view = ScreenRulerOverlayView(frame: CGRect(x: 0, y: 0, width: 400, height: 320), snapshot: snapshot)
    view.raster = try XCTUnwrap(ScreenRulerRaster(image: snapshot.image))
    XCTAssertEqual(view.scaleX, 2)
    XCTAssertEqual(view.scaleY, 1.875)

    // Pixel row 40 sits at 40.5 / 1.875 = 21.6 pt from the top.
    view.pointerMoved(to: CGPoint(x: 30, y: 320 - 21.6))
    XCTAssertEqual(view.pointerPixel, ColorPickerPixel(x: 60, y: 40))
    let image = try XCTUnwrap(ScreenRulerRenderer.renderImage(snapshot.image, drawing: view.drawing(forExport: true)))
    let onLine = try XCTUnwrap(ColorPickerPixelSampler.color(of: ColorPickerPixel(x: 80, y: 40), in: image))
    XCTAssertGreaterThan(onLine.red, 200)
    XCTAssertLessThan(onLine.green, 140)
  }

  // MARK: - Controller

  func testController_opensOneOverlayPerDisplayAndCancels() async throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    let controller = makeController()
    controller.start(snapshots: { Self.snapshotsForAllScreens() }, save: { _, _ in })
    XCTAssertTrue(controller.isActive)
    try await waitUntil { !controller.testWindows.isEmpty }

    XCTAssertEqual(controller.testWindows.count, NSScreen.screens.count)
    XCTAssertTrue(controller.testWindows.allSatisfy { $0.sharingType == .readOnly })

    XCTAssertTrue(controller.handleKeyDown(try keyEvent(kVK_Escape)))
    XCTAssertFalse(controller.isActive)
    XCTAssertTrue(controller.testWindows.isEmpty)
  }

  func testController_keysLockAxisToggleUnitAndAdjustTolerance() async throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    let defaults = UserDefaultsFactory.make()
    let preferences = ScreenRulerPreferences(defaults: defaults)
    let controller = makeController(preferences: preferences)
    controller.start(snapshots: { Self.snapshotsForAllScreens() }, save: { _, _ in })
    try await waitUntil { !controller.testWindows.isEmpty }
    let view = try XCTUnwrap(controller.testWindows.first?.overlayView)

    XCTAssertTrue(controller.handleKeyDown(try keyEvent(kVK_ANSI_H)))
    XCTAssertEqual(view.axis, .horizontal)
    XCTAssertTrue(controller.handleKeyDown(try keyEvent(kVK_ANSI_V)))
    XCTAssertEqual(view.axis, .vertical)
    XCTAssertTrue(controller.handleKeyDown(try keyEvent(kVK_ANSI_V)))
    XCTAssertEqual(view.axis, .both)

    XCTAssertTrue(controller.handleKeyDown(try keyEvent(kVK_ANSI_U)))
    XCTAssertEqual(view.unit, .pixels)
    XCTAssertEqual(preferences.unit, .pixels)

    XCTAssertTrue(controller.handleKeyDown(try keyEvent(kVK_ANSI_RightBracket)))
    XCTAssertEqual(view.tolerance, ScreenRulerEdgeScanner.defaultTolerance + 2)
    XCTAssertEqual(preferences.edgeTolerance, ScreenRulerEdgeScanner.defaultTolerance + 2)

    controller.cancel()
  }

  func testController_copyAndSave() async throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    var copied: [String] = []
    var saved: [(CGImage, CGFloat)] = []
    let controller = makeController(copied: { copied.append($0) })
    controller.start(snapshots: { Self.snapshotsForAllScreens() }, save: { saved.append(($0, $1)) })
    try await waitUntil { !controller.testWindows.isEmpty }
    let window = try XCTUnwrap(controller.testWindows.first)
    let view = window.overlayView
    controller.screenRulerOverlayViewDidReceivePointer(view)
    try await waitUntil { view.raster != nil }
    view.pointerMoved(to: CGPoint(x: 5, y: 5))

    XCTAssertTrue(controller.handleKeyDown(try keyEvent(kVK_ANSI_C)))
    XCTAssertEqual(copied.count, 1)
    XCTAssertTrue(copied.first?.hasSuffix(" pt") ?? false)
    XCTAssertTrue(controller.isActive, "Copy keeps the session open")

    XCTAssertTrue(controller.handleKeyDown(try keyEvent(kVK_Return)))
    XCTAssertFalse(controller.isActive)
    XCTAssertEqual(saved.count, 1)
    XCTAssertEqual(saved.first?.0.width, view.snapshot.image.width)
    XCTAssertEqual(saved.first?.1, view.snapshot.pixelScaleFactor)
  }

  func testController_snapshotFailureShowsErrorAndEnds() async throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    var toasts: [(String, AppToastStyle)] = []
    let controller = makeController(toasts: { toasts.append(($0, $1)) })

    controller.start(snapshots: { throw CaptureError.permissionDenied }, save: { _, _ in })
    try await waitUntil { !controller.isActive }

    XCTAssertTrue(controller.testWindows.isEmpty)
    XCTAssertEqual(toasts.map(\.0), [L10n.ScreenCapture.screenRulerUnavailable])
    XCTAssertEqual(toasts.map(\.1), [.error])
  }

  func testController_cancelWhileFreezingNeverShowsOverlays() async throws {
    try skipIfRunningInCI("Requires onscreen overlay windows and a live main run loop")
    let controller = makeController()
    controller.start(
      snapshots: {
        try await Task.sleep(nanoseconds: 50_000_000)
        return Self.snapshotsForAllScreens()
      },
      save: { _, _ in }
    )
    controller.cancel()
    try await Task.sleep(nanoseconds: 120_000_000)

    XCTAssertFalse(controller.isActive)
    XCTAssertTrue(controller.testWindows.isEmpty)
  }

  // MARK: - Wiring

  func testMeasureScreenShortcutWiring() {
    XCTAssertEqual(GlobalShortcutKind.measureScreen.configKey, "measure_screen")
    XCTAssertFalse(GlobalShortcutKind.measureScreen.isSystemConflictRelevant)
    XCTAssertEqual(GlobalShortcutKind.measureScreen.displayName, L10n.Actions.measureScreen)
    XCTAssertEqual(MenuBarItemKind.measureScreen.group, .tools)
    XCTAssertEqual(ShortcutConfig.defaultMeasureScreen.keyCode, UInt32(kVK_ANSI_M))
    XCTAssertEqual(ShortcutConfig.defaultMeasureScreen.modifiers, UInt32(optionKey | shiftKey))
    XCTAssertEqual(ShortcutConfig.defaultMeasureScreen.displayString, "⇧ ⌥ M")
  }

  // MARK: - Helpers

  /// White 800×600 px (2× of 400×300 pt) with a black 1px-bordered box at x 40…119, y 20…79.
  private static func boxedImage(width: Int = 800, height: Int = 600) -> CGImage {
    ColorPickerTestImages.image(width: width, height: height, colorSpace: ColorPickerTestImages.sRGB) { x, y in
      let onBorder = (x == 40 || x == 119) && (20...79).contains(y)
        || (y == 20 || y == 79) && (40...119).contains(x)
      return onBorder ? (0, 0, 0) : (255, 255, 255)
    }
  }

  private static func snapshotsForAllScreens() -> [FrozenDisplaySnapshot] {
    NSScreen.screens.compactMap { screen in
      guard let displayID = screen.displayID else { return nil }
      let scale = screen.backingScaleFactor
      return FrozenDisplaySnapshot(
        displayID: displayID,
        screenFrame: screen.frame,
        scaleFactor: scale,
        colorSpaceName: CGColorSpace.sRGB,
        image: boxedImage(
          width: Int((screen.frame.width * scale).rounded()),
          height: Int((screen.frame.height * scale).rounded())
        )
      )
    }
  }

  private func makeView() throws -> ScreenRulerOverlayView {
    let snapshot = FrozenDisplaySnapshot(
      displayID: 1,
      screenFrame: CGRect(x: 0, y: 0, width: 400, height: 300),
      scaleFactor: 2,
      colorSpaceName: CGColorSpace.sRGB,
      image: Self.boxedImage()
    )
    let view = ScreenRulerOverlayView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), snapshot: snapshot)
    view.raster = try XCTUnwrap(ScreenRulerRaster(image: snapshot.image))
    view.warpPointer = { _ in }
    return view
  }

  private func makeController(
    copied: @escaping (String) -> Void = { _ in },
    toasts: @escaping (String, AppToastStyle) -> Void = { _, _ in },
    preferences: ScreenRulerPreferences = ScreenRulerPreferences(defaults: UserDefaultsFactory.make())
  ) -> ScreenRulerController {
    ScreenRulerController(
      copyToPasteboard: copied,
      showToast: toasts,
      setProcessing: { _ in },
      preferences: preferences,
      setsCursorHidden: false
    )
  }

  private func keyEvent(_ keyCode: Int, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: modifiers,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "",
      charactersIgnoringModifiers: "",
      isARepeat: false,
      keyCode: UInt16(keyCode)
    ))
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
}
