import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class KeystrokeOverlayWindowTests: XCTestCase {
  func testOverlayStaysAboveStatusLevelWindowsWithoutInterceptingInput() {
    let window = KeystrokeOverlayWindow(recordingRect: CGRect(x: 0, y: 0, width: 400, height: 200))
    defer { window.close() }

    XCTAssertGreaterThan(window.level.rawValue, NSWindow.Level.statusBar.rawValue)
    XCTAssertTrue(window.ignoresMouseEvents)
    XCTAssertFalse(window.canBecomeKey)
    XCTAssertFalse(window.canBecomeMain)
    XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
  }
}
