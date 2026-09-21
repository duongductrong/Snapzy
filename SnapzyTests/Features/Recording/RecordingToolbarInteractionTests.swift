//
//  RecordingToolbarInteractionTests.swift
//  SnapzyTests
//
//  Regression coverage for recording toolbar hit targets.
//

import AppKit
@testable import Snapzy
import SwiftUI
import XCTest

@MainActor
final class RecordingToolbarInteractionTests: XCTestCase {
  func testRecordButton_dispatchesFromPaddedSurface() throws {
    var didRecord = false
    let state = RecordingToolbarState()
    let host = NSHostingView(
      rootView: RecordButtonWithBadge(state: state, onRecord: { didRecord = true })
    )
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    let window = NSWindow(
      contentRect: host.frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.contentView = host
    window.orderFrontRegardless()
    window.makeKey()
    defer { window.close() }

    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))

    let clickPoint = CGPoint(x: 2, y: host.bounds.midY)
    try window.sendEvent(XCTUnwrap(mouseEvent(.leftMouseDown, at: clickPoint, window: window)))
    try window.sendEvent(XCTUnwrap(mouseEvent(.leftMouseUp, at: clickPoint, window: window)))

    XCTAssertTrue(didRecord)
  }

  private func mouseEvent(
    _ type: NSEvent.EventType,
    at location: CGPoint,
    window: NSWindow
  ) -> NSEvent? {
    NSEvent.mouseEvent(
      with: type,
      location: location,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: 1
    )
  }
}
