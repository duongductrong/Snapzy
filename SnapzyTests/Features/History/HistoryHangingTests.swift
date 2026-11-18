import AppKit
import AVFoundation
@testable import Snapzy
import SwiftUI
import XCTest

@MainActor
final class HistoryHangingTests: XCTestCase {
  func testTraditionalIsDefaultAndUnknownStyleFallsBack() throws {
    let name = "HistoryHanging-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    XCTAssertEqual(HistoryDisplayStyle.stored(userDefaults: defaults), .traditional)
    defaults.set("unknown", forKey: PreferencesKeys.historyDisplayStyle)
    XCTAssertEqual(HistoryDisplayStyle.stored(userDefaults: defaults), .traditional)
    defaults.set(HistoryDisplayStyle.hanging.rawValue, forKey: PreferencesKeys.historyDisplayStyle)
    XCTAssertEqual(HistoryDisplayStyle.stored(userDefaults: defaults), .hanging)
    defaults.set(HistoryDisplayStyle.traditional.rawValue, forKey: PreferencesKeys.historyDisplayStyle)
    XCTAssertEqual(HistoryDisplayStyle.stored(userDefaults: defaults), .traditional)
  }

  func testPanelFitsSmallAndOffsetDisplays() {
    for screen in [
      CGRect(x: 0, y: 0, width: 1440, height: 900),
      CGRect(x: -1920, y: 200, width: 1920, height: 1040),
      CGRect(x: 500, y: -900, width: 640, height: 280),
    ] {
      let frame = HistoryHangingLayout.frame(screenFrame: screen, visibleFrame: screen, safeAreaTop: 0)
      XCTAssertTrue(screen.contains(frame))
      XCTAssertEqual(frame.midX, screen.midX)
      XCTAssertEqual(frame.maxY, screen.maxY - 8)
      XCTAssertLessThanOrEqual(frame.width, HistoryHangingLayout.maximumWidth)
    }
  }

  func testCableSpansPhysicalDisplayRegardlessOfDockScaleAndOrientation() {
    let screens = [
      CGRect(x: 0, y: 0, width: 1512, height: 982),
      CGRect(x: -2560, y: -200, width: 2560, height: 1440),
      CGRect(x: 1512, y: 300, width: 1080, height: 1920),
      CGRect(x: -500, y: 982, width: 3440, height: 1440),
      CGRect(x: 0, y: -768, width: 1024, height: 768),
    ]
    for screen in screens {
      for dockWidth: CGFloat in [0, 72] {
        let visible = CGRect(x: screen.minX + dockWidth, y: screen.minY + 64,
                             width: screen.width - dockWidth, height: screen.height - 96)
        let panel = HistoryHangingLayout.frame(screenFrame: screen, visibleFrame: visible, safeAreaTop: 32)
        let cable = HistoryHangingCableLayout(panelFrame: panel, screenFrame: screen)
        XCTAssertEqual(cable.frame.minX, screen.minX)
        XCTAssertEqual(cable.frame.maxX, screen.maxX)
        XCTAssertEqual(cable.frame.maxY, screen.maxY)
        XCTAssertTrue(screen.contains(cable.frame))
        XCTAssertTrue(visible.contains(panel))
        let row = HistoryHangingRowLayout(width: panel.width)
        for index in 0 ..< row.capacity {
          let x = row.center(at: index, count: row.capacity)
          let t = (panel.minX - screen.minX + x) / screen.width
          XCTAssertEqual(cable.attachmentHeight(at: x), 4 * cable.depth * t * (1 - t) - (screen.maxY - panel.maxY),
                         accuracy: 0.001)
          XCTAssertGreaterThanOrEqual(cable.attachmentHeight(at: x), 12 - 0.001)
          XCTAssertLessThanOrEqual(cable.attachmentHeight(at: x), cable.maximumAttachmentHeight)
        }
        XCTAssertEqual(
          cable.attachmentHeight(at: screen.minX - panel.minX),
          -(screen.maxY - panel.maxY),
          accuracy: 0.001
        )
        XCTAssertEqual(
          cable.attachmentHeight(at: screen.maxX - panel.minX),
          -(screen.maxY - panel.maxY),
          accuracy: 0.001
        )
      }
    }
  }

  func testRowFitsWithoutScrollingAtEveryCapacity() {
    for width: CGFloat in [140, 320, 608, 800, 1048, 1120] {
      let row = HistoryHangingRowLayout(width: width)
      for count in 1 ... row.capacity {
        XCTAssertGreaterThanOrEqual(row.center(at: 0, count: count) - row.cardWidth / 2, 24)
        XCTAssertLessThanOrEqual(row.center(at: count - 1, count: count) + row.cardWidth / 2, width - 24)
        XCTAssertEqual(
          row.center(at: 0, count: count) + row.center(at: count - 1, count: count),
          width,
          accuracy: 0.001
        )
      }
    }
    XCTAssertEqual(HistoryHangingRowLayout(width: 1120).capacity, 5)
  }

  func testSelectionCapsConfiguredMaximumAndFiltersBeforeLimiting() {
    let records = (0 ..< 12).map { selectionRecord(index: $0, type: $0.isMultiple(of: 2) ? .screenshot : .video) }
    let visible = HistoryHangingLayout.visibleRecords(records, filter: .video, maximum: 20, width: 1120)
    XCTAssertEqual(visible.map(\.id), records.filter { $0.captureType == .video }.prefix(5).map(\.id))
    XCTAssertEqual(HistoryHangingLayout.visibleRecords(records, filter: nil, maximum: 3, width: 1120).count, 3)
    XCTAssertTrue(HistoryHangingLayout.visibleRecords(records, filter: .gif, maximum: 20, width: 1120).isEmpty)
  }

  func testNewCaptureDisplacesOnlyLastVisibleRecordWithoutDeletingHistory() {
    var records = (0 ..< 10).map { selectionRecord(index: $0) }
    let before = HistoryHangingLayout.visibleRecords(records, filter: nil, maximum: 20, width: 1120)
    let newRecord = selectionRecord(index: 100)
    records.insert(newRecord, at: 0)
    let after = HistoryHangingLayout.visibleRecords(records, filter: nil, maximum: 20, width: 1120)
    XCTAssertEqual(after.map(\.id), [newRecord.id] + before.dropLast().map(\.id))
    XCTAssertTrue(records.contains { $0.id == before.last?.id })
    XCTAssertEqual(records.count, 11)
    records[0].thumbnailPath = "/tmp/updated-thumbnail.jpg"
    XCTAssertEqual(
      HistoryHangingLayout.visibleRecords(records, filter: nil, maximum: 20, width: 1120).map(\.id),
      after.map(\.id)
    )
  }

  func testBurstAndDeletedRecordsDoNotOverflowTheRow() {
    var records = (0 ..< 40).map { selectionRecord(index: $0) }
    records[0].isDeleted = true
    let visible = HistoryHangingLayout.visibleRecords(records, filter: nil, maximum: 20, width: 608)
    XCTAssertEqual(visible.map(\.id), Array(records.dropFirst().prefix(2)).map(\.id))
    XCTAssertFalse(visible.contains { $0.isDeleted })
  }

  private func selectionRecord(index: Int, type: CaptureHistoryType = .screenshot) -> CaptureHistoryRecord {
    CaptureHistoryRecord(id: UUID(), filePath: "/tmp/history-selection-\(index).png", fileName: "Capture \(index)",
                         captureType: type, fileSize: 1000, capturedAt: Date().addingTimeInterval(-Double(index)),
                         width: 640, height: 400, thumbnailPath: nil, isDeleted: false)
  }

  func testShortGalleryKeepsRoomForClipsAndActions() {
    XCTAssertEqual(HistoryHangingLayout.thumbnailHeight(galleryHeight: 251), 126)
    XCTAssertEqual(HistoryHangingLayout.thumbnailHeight(galleryHeight: 171), 63)
    XCTAssertLessThanOrEqual(HistoryHangingLayout.thumbnailHeight(galleryHeight: 171) + 108, 171)
  }

  private final class EscapeProbeView: NSView {
    var escapeCount = 0
    override var acceptsFirstResponder: Bool {
      true
    }

    override func keyDown(with event: NSEvent) {
      if event.keyCode == 53 {
        escapeCount += 1
      }
    }
  }

  private var hangingWindow: NSWindow? {
    NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "SnapzyHistoryHanging" }
  }

  private func withCaptureWindows(
    _ body: (HistoryHangingManager, NSWindow, NSWindow, NSScreen) async throws -> Void
  ) async throws {
    let screen = try XCTUnwrap(NSScreen.main)
    let recorder = ScreenRecordingManager.shared
    guard recorder.state == .idle else { throw XCTSkip("Recording already active") }
    let history = HistoryFloatingManager.shared
    let shelf = HistoryHangingManager.shared
    let style = history.displayStyle
    let enabled = UserDefaults.standard.object(forKey: PreferencesKeys.historyEnabled)
    let windows = (0 ..< 2).map { _ in
      let window = NSWindow(contentRect: CGRect(x: screen.frame.minX, y: screen.frame.minY, width: 40, height: 40),
                            styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      return window
    }
    defer {
      shelf.stop()
      for window in windows {
        CaptureChromeWindowRegistry.shared.unregister(window)
        window.close()
      }
      recorder.setStateForTesting(.idle)
      history.displayStyle = style
      UserDefaults.standard.set(enabled, forKey: PreferencesKeys.historyEnabled)
    }
    history.hide()
    UserDefaults.standard.set(true, forKey: PreferencesKeys.historyEnabled)
    history.displayStyle = .hanging
    shelf.start()
    CaptureChromeWindowRegistry.configure(windows[0], role: .captureOverlay)
    CaptureChromeWindowRegistry.configure(windows[1], role: .recordingControls)
    try await body(shelf, windows[0], windows[1], screen)
  }

  private func assertWhiteCapture(_ bitmap: NSBitmapImageRep, file: StaticString = #filePath, line: UInt = #line) {
    for x in [0.1, 0.3, 0.5, 0.7, 0.9] {
      for y in [0.2, 0.5, 0.8] {
        let color = bitmap.colorAt(x: Int(Double(bitmap.pixelsWide) * x),
                                   y: Int(Double(bitmap.pixelsHigh) * y))?.usingColorSpace(.deviceRGB)
        XCTAssertGreaterThan(color?.redComponent ?? 0, 0.95, file: file, line: line)
        XCTAssertGreaterThan(color?.greenComponent ?? 0, 0.95, file: file, line: line)
        XCTAssertGreaterThan(color?.blueComponent ?? 0, 0.95, file: file, line: line)
      }
    }
  }

  private func waitForCaptureInteraction(_ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(12)
    while !condition(), Date() < deadline {
      try await Task.sleep(nanoseconds: 30_000_000)
    }
    guard condition() else {
      XCTFail("Native capture interaction did not reach expected state")
      throw NSError(domain: "HistoryHangingCaptureTest", code: 1)
    }
  }

  private var previewWindow: NSWindow? {
    NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "SnapzyHistoryPreview" }
  }

  private func update(_ state: inout HistoryEdgeHoverState, edge: Bool = false, visible: Bool = false,
                      inside: Bool = false, keepOpen: Bool = false, suppressed: Bool = false,
                      time: TimeInterval) -> HistoryEdgeHoverState.Action {
    state.update(atEdge: edge, insideShelf: inside, visible: visible, keepOpen: keepOpen,
                 suppressed: suppressed, now: time)
  }

  private func waitForInteraction(_ condition: () -> Bool) throws {
    let deadline = Date().addingTimeInterval(90)
    while !condition(), Date() < deadline {
      if let event = NSApp.nextEvent(
        matching: .any,
        until: Date().addingTimeInterval(0.01),
        inMode: .default,
        dequeue: true
      ) {
        NSApp.sendEvent(event)
      }
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    XCTAssertTrue(condition(), "Native History interaction did not reach expected state")
    if !condition() {
      throw NSError(domain: "HistoryHangingTest", code: 1)
    }
  }

  private func makeImage(index: Int, directory: URL) throws -> URL {
    let image = NSImage(size: CGSize(width: 640, height: 400))
    image.lockFocus()
    NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
    CGRect(x: 0, y: 0, width: 640, height: 400).fill()
    let color = [NSColor.systemIndigo, .systemTeal, .systemOrange, .systemPink, .systemBlue, .systemMint][index % 6]
    color.withAlphaComponent(0.3).setFill()
    NSBezierPath(roundedRect: CGRect(x: 20, y: 20, width: 140, height: 360), xRadius: 16, yRadius: 16).fill()
    color.setFill()
    NSBezierPath(roundedRect: CGRect(x: 180, y: 180, width: 440, height: 200), xRadius: 16, yRadius: 16).fill()
    for column in 0 ..< 3 {
      NSColor(calibratedWhite: 0.15 + Double(column) * 0.025, alpha: 1).setFill()
      NSBezierPath(
        roundedRect: CGRect(x: CGFloat(180 + column * 150), y: 20, width: 140, height: 140),
        xRadius: 12,
        yRadius: 12
      ).fill()
    }
    ("Workspace \(index + 1)" as NSString).draw(at: CGPoint(x: 200, y: 320),
                                                withAttributes: [
                                                  .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
                                                  .foregroundColor: NSColor.white,
                                                ])
    image.unlockFocus()
    let representation = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
    let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    let url = directory.appendingPathComponent("Workspace \(index + 1).png")
    try data.write(to: url)
    return url
  }
}
