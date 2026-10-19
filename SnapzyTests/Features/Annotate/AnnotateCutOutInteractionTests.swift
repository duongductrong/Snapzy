//
//  AnnotateCutOutInteractionTests.swift
//  SnapzyTests
//
//  Esc/cancel behavior while the Cut Out tool owns the editor: Esc discards
//  the drawn strip first, then leaves the mode and restores the prior tool.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class AnnotateCutOutInteractionTests: XCTestCase {
  private static var retainedAnnotateStates: [AnnotateState] = []

  private func makeCutOutState() -> AnnotateState {
    let state = AnnotateState()
    Self.retainedAnnotateStates.append(state)
    state.sourceImage = NSImage(size: CGSize(width: 100, height: 80))
    state.selectedTool = .rectangle
    state.beginCutOutInteraction()
    return state
  }

  func testCancelInteraction_withStrip_clearsStripAndStaysInMode() {
    let state = makeCutOutState()
    state.updateCutOutStrip(CGRect(x: 0, y: 20, width: 100, height: 10))
    XCTAssertNotNil(state.cutOutPreviewStrip)

    state.cancelCutOutInteraction()

    XCTAssertNil(state.cutOutPreviewStrip)
    XCTAssertTrue(state.isCutOutInteractionActive)
  }

  func testCancelInteraction_withoutStrip_exitsModeAndRestoresTool() {
    let state = makeCutOutState()
    XCTAssertTrue(state.isCutOutInteractionActive)

    state.cancelCutOutInteraction()

    XCTAssertFalse(state.isCutOutInteractionActive)
    XCTAssertEqual(state.selectedTool, .rectangle)
  }

  // MARK: - Session persistence

  private func makePixelState(width: Int, height: Int) throws -> AnnotateState {
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: width, height: height))
    let state = AnnotateState(image: NSImage(cgImage: cgImage, size: CGSize(width: width, height: height)), url: URL(fileURLWithPath: "/tmp/snapzy-cutout-test.png"))
    Self.retainedAnnotateStates.append(state)
    return state
  }

  private func pixelSize(of data: Data) throws -> CGSize {
    let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
    return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
  }

  func testSessionSnapshot_untransformed_keepsLoadedBytes() throws {
    let state = try makePixelState(width: 100, height: 80)
    let loadedBytes = Data([0x01, 0x02, 0x03])

    let snapshot = try XCTUnwrap(AnnotateManager.shared.makeSessionData(for: state, originalImageData: loadedBytes))

    XCTAssertEqual(snapshot.originalImageData, loadedBytes)
  }

  func testSessionSnapshot_afterCutOut_persistsCutPixels() throws {
    let state = try makePixelState(width: 100, height: 80)
    let loadedBytes = try XCTUnwrap(AnnotateExporter.imageData(from: try XCTUnwrap(state.sourceImage), for: "png"))
    state.beginCutOutInteraction()
    state.updateCutOutStrip(CGRect(x: 0, y: 20, width: 100, height: 10))
    state.commitCutOut()

    let snapshot = try XCTUnwrap(AnnotateManager.shared.makeSessionData(for: state, originalImageData: loadedBytes))

    XCTAssertEqual(try pixelSize(of: snapshot.originalImageData), CGSize(width: 100, height: 70))
    XCTAssertEqual(snapshot.sourceLogicalSize, CGSize(width: 100, height: 70))
  }

  func testSessionSnapshot_afterUndoingCutOut_returnsToLoadedBytes() throws {
    let state = try makePixelState(width: 100, height: 80)
    let loadedBytes = Data([0x01, 0x02, 0x03])
    state.beginCutOutInteraction()
    state.updateCutOutStrip(CGRect(x: 0, y: 20, width: 100, height: 10))
    state.commitCutOut()
    state.undo()

    let snapshot = try XCTUnwrap(AnnotateManager.shared.makeSessionData(for: state, originalImageData: loadedBytes))

    XCTAssertEqual(snapshot.originalImageData, loadedBytes)
  }

  /// Repeated cut → save → reopen cycles with fractional strips must keep the
  /// persisted pixels and logical size in a constant 2x ratio (no scale drift).
  func testSessionCycles_withFractionalStrips_keepRetinaScale() throws {
    let cg = try XCTUnwrap(TestImageFactory.solidColor(width: 200, height: 160))
    var image = NSImage(cgImage: cg, size: CGSize(width: 100, height: 80))
    var sessionBytes = try XCTUnwrap(AnnotateExporter.imageData(from: image, for: "png"))

    for cycle in 1...3 {
      let state = AnnotateState(image: image, url: URL(fileURLWithPath: "/tmp/snapzy-cutout-test.png"))
      Self.retainedAnnotateStates.append(state)
      let width = try XCTUnwrap(state.sourceImage).size.width
      state.beginCutOutInteraction()
      state.updateCutOutStrip(CGRect(x: 0, y: 20.3, width: width, height: 7.37))
      state.commitCutOut()

      let snapshot = try XCTUnwrap(AnnotateManager.shared.makeSessionData(for: state, originalImageData: sessionBytes))
      let logical = try XCTUnwrap(snapshot.sourceLogicalSize)
      let pixels = try pixelSize(of: snapshot.originalImageData)
      XCTAssertEqual(pixels.width, logical.width * 2, "cycle \(cycle)")
      XCTAssertEqual(pixels.height, logical.height * 2, "cycle \(cycle)")

      sessionBytes = snapshot.originalImageData
      let decoded = try XCTUnwrap(NSImage(data: sessionBytes))
      image = AnnotateWindowController.restoredSessionImage(decoded, sourceLogicalSize: logical)
    }

    // 160px - 3 cuts of round(7.37 * 2) = 15px each.
    XCTAssertEqual(try pixelSize(of: sessionBytes), CGSize(width: 200, height: 115))
  }

  func testUpdateStrip_afterCancel_isIgnored() {
    let state = makeCutOutState()
    state.cancelCutOut()

    state.updateCutOutStrip(CGRect(x: 0, y: 20, width: 100, height: 10))

    XCTAssertNil(state.cutOutPreviewStrip)
  }
}
