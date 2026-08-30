//
//  CaptureSubjectFlowTests.swift
//  SnapzyTests
//
//  PixelSnap-style Capture Subject: drag locks a snapped preview; clicking
//  the camera button captures. Hovering or clicking the preview itself does not.
//

import XCTest
@testable import Snapzy

@MainActor
final class CaptureSubjectFlowTests: XCTestCase {
  func testCursor_usesHighContrastCrosshairAndRestoresArrowOnCancel() {
    let (controller, _, _, _) = makeCaptureSubjectController()
    var cursors: [NSCursor] = []
    controller.cursorSetEffect = { cursors.append($0) }

    controller.startCapture()
    XCTAssertTrue(cursors.last === NSCursor.vectorScreenshotCrosshairHighContrast)

    controller.cancel()
    XCTAssertTrue(cursors.last === NSCursor.arrow)
  }

  func testDragRelease_locksPreviewWithoutCapturing() async throws {
    let screen = try XCTUnwrap(NSScreen.screens.first)
    let (controller, performer, windowBox, _) = makeCaptureSubjectController()
    defer { controller.cancel() }

    controller.startCapture()
    let window = try XCTUnwrap(windowBox.windows.first)
    let origin = CGPoint(x: screen.frame.minX + 40, y: screen.frame.minY + 40)
    let end = CGPoint(x: origin.x + 120, y: origin.y + 80)
    let expected = CGRect(x: origin.x, y: origin.y, width: 120, height: 80)

    controller.captureSubjectOverlayWindow(window, mouseDownAt: origin)
    controller.captureSubjectOverlayWindow(window, mouseDraggedAt: end)
    controller.captureSubjectOverlayWindow(window, mouseUpAt: end)
    await Task.yield()

    XCTAssertTrue(performer.capturedPreviews.isEmpty)
    XCTAssertEqual(window.currentPreviewRect, expected)
    XCTAssertTrue(windowBox.windows.allSatisfy { $0.orderOutCount == 1 })
    XCTAssertTrue(windowBox.windows.allSatisfy { $0.orderFrontCount == 2 })
  }

  func testClickLockedPreview_doesNotCapture() async throws {
    let screen = try XCTUnwrap(NSScreen.screens.first)
    let (controller, performer, windowBox, _) = makeCaptureSubjectController()
    defer { controller.cancel() }

    controller.startCapture()
    let window = try XCTUnwrap(windowBox.windows.first)
    let origin = CGPoint(x: screen.frame.minX + 40, y: screen.frame.minY + 40)
    let end = CGPoint(x: origin.x + 120, y: origin.y + 80)
    let previewRect = CGRect(x: origin.x, y: origin.y, width: 120, height: 80)

    controller.captureSubjectOverlayWindow(window, mouseDownAt: origin)
    controller.captureSubjectOverlayWindow(window, mouseDraggedAt: end)
    controller.captureSubjectOverlayWindow(window, mouseUpAt: end)

    let inside = CGPoint(x: previewRect.minX + 10, y: previewRect.minY + 10)
    controller.captureSubjectOverlayWindow(window, mouseDownAt: inside)
    await Task.yield()

    XCTAssertTrue(performer.capturedPreviews.isEmpty)
    XCTAssertEqual(window.currentPreviewRect, previewRect)
  }

  func testClickCamera_captures() async throws {
    let screen = try XCTUnwrap(NSScreen.screens.first)
    let (controller, performer, windowBox, _) = makeCaptureSubjectController()
    defer { controller.cancel() }

    controller.startCapture()
    let window = try XCTUnwrap(windowBox.windows.first)
    let origin = CGPoint(x: screen.frame.minX + 40, y: screen.frame.minY + 40)
    let end = CGPoint(x: origin.x + 120, y: origin.y + 80)
    let previewRect = CGRect(x: origin.x, y: origin.y, width: 120, height: 80)

    controller.captureSubjectOverlayWindow(window, mouseDownAt: origin)
    controller.captureSubjectOverlayWindow(window, mouseDraggedAt: end)
    controller.captureSubjectOverlayWindow(window, mouseUpAt: end)

    window.isCameraHovered = true
    controller.captureSubjectOverlayWindowDidRequestCapture(window)
    await Task.yield()
    await Task.yield()

    XCTAssertEqual(performer.capturedPreviews.map(\.rect), [previewRect])
  }

  func testMouseDownOnHoveredCamera_captures() async throws {
    let screen = try XCTUnwrap(NSScreen.screens.first)
    let (controller, performer, windowBox, _) = makeCaptureSubjectController()
    defer { controller.cancel() }

    controller.startCapture()
    let window = try XCTUnwrap(windowBox.windows.first)
    let origin = CGPoint(x: screen.frame.minX + 40, y: screen.frame.minY + 40)
    let end = CGPoint(x: origin.x + 120, y: origin.y + 80)
    let previewRect = CGRect(x: origin.x, y: origin.y, width: 120, height: 80)

    controller.captureSubjectOverlayWindow(window, mouseDownAt: origin)
    controller.captureSubjectOverlayWindow(window, mouseDraggedAt: end)
    controller.captureSubjectOverlayWindow(window, mouseUpAt: end)

    window.isCameraHovered = true
    controller.captureSubjectOverlayWindow(
      window,
      mouseDownAt: CGPoint(x: previewRect.midX, y: previewRect.midY)
    )
    await Task.yield()
    await Task.yield()

    XCTAssertEqual(performer.capturedPreviews.map(\.rect), [previewRect])
  }

  func testClickOutsideLockedPreview_unlocksWithoutCapture() async throws {
    let screen = try XCTUnwrap(NSScreen.screens.first)
    let (controller, performer, windowBox, _) = makeCaptureSubjectController()
    defer { controller.cancel() }

    controller.startCapture()
    let window = try XCTUnwrap(windowBox.windows.first)
    let origin = CGPoint(x: screen.frame.minX + 40, y: screen.frame.minY + 40)
    let end = CGPoint(x: origin.x + 120, y: origin.y + 80)
    let previewRect = CGRect(x: origin.x, y: origin.y, width: 120, height: 80)

    controller.captureSubjectOverlayWindow(window, mouseDownAt: origin)
    controller.captureSubjectOverlayWindow(window, mouseDraggedAt: end)
    controller.captureSubjectOverlayWindow(window, mouseUpAt: end)
    XCTAssertEqual(window.currentPreviewRect, previewRect)

    let outside = CGPoint(x: previewRect.maxX + 40, y: previewRect.maxY + 40)
    controller.captureSubjectOverlayWindow(window, mouseDownAt: outside)
    await Task.yield()

    XCTAssertNil(window.currentPreviewRect)
    XCTAssertTrue(performer.capturedPreviews.isEmpty)
  }

  func testEscape_onLockedPreview_unlocksWithoutCancelingSession() async throws {
    let screen = try XCTUnwrap(NSScreen.screens.first)
    let (controller, performer, windowBox, _) = makeCaptureSubjectController()
    defer { controller.cancel() }

    controller.startCapture()
    let window = try XCTUnwrap(windowBox.windows.first)
    let origin = CGPoint(x: screen.frame.minX + 40, y: screen.frame.minY + 40)
    let end = CGPoint(x: origin.x + 120, y: origin.y + 80)

    controller.captureSubjectOverlayWindow(window, mouseDownAt: origin)
    controller.captureSubjectOverlayWindow(window, mouseDraggedAt: end)
    controller.captureSubjectOverlayWindow(window, mouseUpAt: end)
    XCTAssertTrue(controller.isSessionActive)

    controller.captureSubjectOverlayWindowDidCancel(window)
    await Task.yield()

    XCTAssertTrue(controller.isSessionActive)
    XCTAssertNil(window.currentPreviewRect)
    XCTAssertTrue(performer.capturedPreviews.isEmpty)
  }

  func testEscape_withoutLockedPreview_cancelsSession() async throws {
    let (controller, performer, windowBox, _) = makeCaptureSubjectController()
    defer { controller.cancel() }

    controller.startCapture()
    let window = try XCTUnwrap(windowBox.windows.first)
    XCTAssertTrue(controller.isSessionActive)

    controller.captureSubjectOverlayWindowDidCancel(window)
    await Task.yield()

    XCTAssertFalse(controller.isSessionActive)
    XCTAssertTrue(performer.capturedPreviews.isEmpty)
  }

  func testHoverCamera_doesNotCapture() async throws {
    let screen = try XCTUnwrap(NSScreen.screens.first)
    let (controller, performer, windowBox, _) = makeCaptureSubjectController()
    defer { controller.cancel() }

    controller.startCapture()
    let window = try XCTUnwrap(windowBox.windows.first)
    let origin = CGPoint(x: screen.frame.minX + 40, y: screen.frame.minY + 40)
    let end = CGPoint(x: origin.x + 120, y: origin.y + 80)
    let previewRect = CGRect(x: origin.x, y: origin.y, width: 120, height: 80)

    controller.captureSubjectOverlayWindow(window, mouseDownAt: origin)
    controller.captureSubjectOverlayWindow(window, mouseDraggedAt: end)
    controller.captureSubjectOverlayWindow(window, mouseUpAt: end)

    window.isCameraHovered = true
    controller.captureSubjectOverlayWindow(
      window,
      mouseMovedAt: CGPoint(x: previewRect.midX, y: previewRect.midY)
    )
    await Task.yield()

    XCTAssertTrue(performer.capturedPreviews.isEmpty)
    XCTAssertEqual(window.currentPreviewRect, previewRect)
    XCTAssertTrue(controller.isSessionActive)
  }
}

@MainActor
final class FakeCaptureSubjectPerformer: CaptureSubjectCapturePerforming {
  private(set) var capturedPreviews: [CaptureSubjectSnappedPreview] = []

  func captureSubject(preview: CaptureSubjectSnappedPreview) async {
    capturedPreviews.append(preview)
  }
}

@MainActor
final class FakeCaptureSubjectPreviewCapturer: CaptureSubjectPreviewCapturing {
  func capturePreview(of rect: CGRect) -> CaptureSubjectPreviewFrame? {
    CaptureSubjectPreviewFrame(
      rect: rect.integral,
      image: TestImageFactory.solidColor(
        width: max(1, Int(rect.width.rounded())),
        height: max(1, Int(rect.height.rounded()))
      ) ?? TestImageFactory.solidColor(width: 8, height: 8)!,
      displayID: 1
    )
  }
}

@MainActor
final class FakeCaptureSubjectOverlayWindow: CaptureSubjectOverlayWindowProviding {
  let displayID: CGDirectDisplayID?
  var frame: CGRect
  var currentPreviewRect: CGRect?
  var currentDragRect: CGRect?
  var isCameraHovered = false
  weak var eventDelegate: CaptureSubjectOverlayWindowDelegate?
  private(set) var pointerPoints: [CGPoint?] = []
  private(set) var orderFrontCount = 0
  private(set) var orderOutCount = 0

  init(displayID: CGDirectDisplayID?, frame: CGRect) {
    self.displayID = displayID
    self.frame = frame
  }

  func setFrame(_ frameRect: NSRect, display flag: Bool) { frame = frameRect }
  func orderFrontRegardless() { orderFrontCount += 1 }
  func orderOut(_ sender: Any?) { orderOutCount += 1 }
  func close() {}
  func makeKey() {}
  func makeFirstResponder(_ responder: NSResponder?) -> Bool { true }
  func updateBounds(_ screenFrame: CGRect) { frame = screenFrame }

  func updatePreview(_ preview: CaptureSubjectSnappedPreview?) {
    currentPreviewRect = preview?.rect
  }

  func updateDragRect(_ rect: CGRect?) {
    currentDragRect = rect
  }

  func setPointer(_ point: CGPoint?) {
    pointerPoints.append(point)
  }
}

@MainActor
final class CaptureSubjectWindowBox {
  var windows: [FakeCaptureSubjectOverlayWindow] = []
}

@MainActor
func makeCaptureSubjectController() -> (
  CaptureSubjectController,
  FakeCaptureSubjectPerformer,
  CaptureSubjectWindowBox,
  FakeCaptureSubjectPreviewCapturer
) {
  let performer = FakeCaptureSubjectPerformer()
  let previewCapturer = FakeCaptureSubjectPreviewCapturer()
  let windowBox = CaptureSubjectWindowBox()
  let controller = CaptureSubjectController(
    capturePerformer: performer,
    previewCapturer: previewCapturer,
    windowFactory: { screen in
      let window = FakeCaptureSubjectOverlayWindow(displayID: screen.displayID, frame: screen.frame)
      windowBox.windows.append(window)
      return window
    }
  )
  return (controller, performer, windowBox, previewCapturer)
}
