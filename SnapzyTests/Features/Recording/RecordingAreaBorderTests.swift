//
//  RecordingAreaBorderTests.swift
//  SnapzyTests
//
//  Recording area border shown during recording, independent of the dim preference (#545).
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class RecordingAreaBorderTests: XCTestCase {

  private var defaults: UserDefaults!
  private let suiteName = "RecordingAreaBorderTests"

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    super.tearDown()
  }

  func testShowAreaBorder_defaultsToTrue() {
    XCTAssertTrue(RecordingToolbarPreferences.showAreaBorder(defaults: defaults))
  }

  func testShowAreaBorder_respectsStoredValue() {
    defaults.set(false, forKey: PreferencesKeys.recordingShowAreaBorder)
    XCTAssertFalse(RecordingToolbarPreferences.showAreaBorder(defaults: defaults))
  }

  func testShowAreaBorder_isIndependentOfDim() {
    defaults.set(false, forKey: PreferencesKeys.recordingDimNonSelectedArea)
    XCTAssertFalse(RecordingToolbarPreferences.dimNonSelectedArea(defaults: defaults))
    XCTAssertTrue(RecordingToolbarPreferences.showAreaBorder(defaults: defaults))
  }

  func testRecordingFrame_isOffUntilEnabled() throws {
    let (overlay, _) = try makeOverlay()
    defer { overlay.close() }
    XCTAssertFalse(overlay.isRecordingFrameEnabled)
    overlay.setRecordingFrameEnabled(true)
    XCTAssertTrue(overlay.isRecordingFrameEnabled)
    overlay.setRecordingFrameEnabled(false)
    XCTAssertFalse(overlay.isRecordingFrameEnabled)
  }

  func testRecordingFrame_drawsOutsideRegionWithDimOff() throws {
    let (overlay, localRect) = try makeOverlay()
    defer { overlay.close() }
    overlay.hideBorder()
    overlay.setDimEnabled(false)

    overlay.setRecordingFrameEnabled(true)
    let outside = try sample(overlay, at: CGPoint(x: localRect.minX - 1, y: localRect.midY))
    let inside = try sample(overlay, at: CGPoint(x: localRect.minX + 4, y: localRect.midY))
    XCTAssertGreaterThan(outside.alphaComponent, 0.5, "frame should be drawn just outside the region")
    XCTAssertGreaterThan(outside.redComponent, outside.greenComponent)
    XCTAssertEqual(inside.alphaComponent, 0, accuracy: 0.01, "captured pixels must stay untouched")

    overlay.setRecordingFrameEnabled(false)
    let cleared = try sample(overlay, at: CGPoint(x: localRect.minX - 1, y: localRect.midY))
    XCTAssertEqual(cleared.alphaComponent, 0, accuracy: 0.01)
  }

  func testRecordingFrame_hiddenWhileSelectionBorderShown() throws {
    let (overlay, localRect) = try makeOverlay()
    defer { overlay.close() }
    overlay.setDimEnabled(false)
    overlay.setRecordingFrameEnabled(true)
    // Pre-record selection keeps its own white border; the red frame must not stack on it.
    let point = CGPoint(x: localRect.minX - 1, y: localRect.midY + 30)
    let color = try sample(overlay, at: point)
    XCTAssertFalse(color.alphaComponent > 0.5 && color.redComponent > 0.8 && color.greenComponent < 0.5)
  }

  // MARK: - Helpers

  private func makeOverlay() throws -> (RecordingRegionOverlayWindow, CGRect) {
    guard let screen = NSScreen.screens.first else {
      throw XCTSkip("Overlay rendering needs a display")
    }
    let origin = screen.frame.origin
    let highlight = CGRect(x: origin.x + 120, y: origin.y + 120, width: 240, height: 160)
    let overlay = RecordingRegionOverlayWindow(screen: screen, highlightRect: highlight)
    overlay.setFrame(screen.frame, display: false)
    let local = highlight.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
    return (overlay, local)
  }

  /// Renders a small patch of the overlay around `point` (view coordinates) and
  /// returns the color at its center.
  private func sample(_ overlay: RecordingRegionOverlayWindow, at point: CGPoint) throws -> NSColor {
    let view = try XCTUnwrap(overlay.contentView)
    let patch = CGRect(x: point.x - 0.5, y: point.y - 0.5, width: 1, height: 1)
    let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: patch))
    view.cacheDisplay(in: patch, to: rep)
    let color = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2))
    return try XCTUnwrap(color.usingColorSpace(.deviceRGB))
  }
}
