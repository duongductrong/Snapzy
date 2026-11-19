import AppKit
import AVFoundation
@testable import Snapzy
import SwiftUI
import XCTest

@MainActor
final class HistoryHangingTests: XCTestCase {
  deinit {}

  override func tearDown() {
    let hangingManager = HistoryHangingManager.shared
    hangingManager.stop()
    HistoryFloatingManager.shared.hide()

    let hangingWindowIdentifiers: Set<String> = [
      "SnapzyHistoryHanging",
      "SnapzyHistoryCable",
      "SnapzyHistoryPreview",
    ]
    for window in NSApp.windows where hangingWindowIdentifiers.contains(window.identifier?.rawValue ?? "") {
      CaptureChromeWindowRegistry.shared.unregister(window)
      window.orderOut(nil)
      window.contentView = nil
      window.close()
    }

    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    super.tearDown()
  }

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

  func testCompactCardsStayAboveToolbarWithMenuBarAndDock() {
    for width: CGFloat in [640, 1152, 3440] {
      let screen = CGRect(x: 0, y: 0, width: width, height: 280)
      let visible = CGRect(x: 0, y: 64, width: width, height: 192)
      let panel = HistoryHangingLayout.frame(screenFrame: screen, visibleFrame: visible, safeAreaTop: 24)
      let cable = HistoryHangingCableLayout(panelFrame: panel, screenFrame: screen)
      let galleryHeight = panel.height - HistoryHangingLayout.toolbarHeight - Spacing.md - Spacing.sm
      let imageHeight = HistoryHangingLayout.thumbnailHeight(galleryHeight: galleryHeight,
                                                             anchorDepth: cable.maximumAttachmentHeight, compact: true)
      XCTAssertLessThanOrEqual(panel.width, 680)
      XCTAssertLessThanOrEqual(cable.maximumAttachmentHeight + imageHeight + 54, galleryHeight)
    }
  }

  func testPreviewFitsOffsetPortraitAndSmallDisplays() {
    for visible in [CGRect(x: 0, y: 72, width: 1680, height: 940),
                    CGRect(x: -1080, y: 200, width: 1080, height: 1880),
                    CGRect(x: 800, y: -280, width: 640, height: 256)] {
      let shelf = HistoryHangingLayout.frame(screenFrame: visible, visibleFrame: visible, safeAreaTop: 0)
      for imageSize in [CGSize(width: 1200, height: 750), CGSize(width: 300, height: 1200)] {
        for x in [visible.minX, visible.midX, visible.maxX] {
          let preview = HistoryHangingPreviewController.previewFrame(
            visibleFrame: visible, shelfFrame: shelf,
            anchor: CGRect(x: x, y: shelf.minY, width: 1, height: 1), imageSize: imageSize
          )
          XCTAssertTrue(visible.contains(preview))
          XCTAssertLessThanOrEqual(preview.width, 600)
          XCTAssertLessThanOrEqual(preview.height, 420)
        }
      }
    }
  }

  func testCancelledHoverCannotReopenPreview() async throws {
    let screen = try XCTUnwrap(NSScreen.main)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryHover-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = try makeImage(index: 0, directory: directory)
    var record = selectionRecord(index: 0)
    record.filePath = url.path
    let controller = HistoryHangingPreviewController()
    let shelf = HistoryHangingLayout.frame(screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
                                           safeAreaTop: screen.safeAreaInsets.top)
    controller.request(record, anchor: shelf, shelfFrame: shelf, screen: screen)
    controller.dismiss()
    try await Task.sleep(nanoseconds: 400_000_000)
    XCTAssertFalse(controller.isVisible)
    XCTAssertNil(controller.recordID)
  }

  func testHiddenMenuBarStillRespectsMacBookNotch() {
    let screen = CGRect(x: -1512, y: 200, width: 1512, height: 982)
    let panel = HistoryHangingLayout.frame(screenFrame: screen, visibleFrame: screen, safeAreaTop: 38)
    XCTAssertEqual(panel.maxY, screen.maxY - 46)
    XCTAssertEqual(HistoryHangingCableLayout(panelFrame: panel, screenFrame: screen).frame.maxY, screen.maxY)
  }

  func testStackedDisplaysDoNotTriggerTheWrongScreenAtSharedBoundary() {
    let lower = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let upper = CGRect(x: 0, y: 900, width: 1440, height: 900)
    XCTAssertNil(HistoryHangingLayout.edgeScreenIndex(at: CGPoint(x: 720, y: 900), frames: [lower, upper]))
    XCTAssertNil(HistoryHangingLayout.edgeScreenIndex(at: CGPoint(x: 720, y: 900), frames: [upper, lower]))
    XCTAssertEqual(HistoryHangingLayout.edgeScreenIndex(at: CGPoint(x: 720, y: 899), frames: [lower, upper]), 0)
    XCTAssertEqual(HistoryHangingLayout.edgeScreenIndex(at: CGPoint(x: 720, y: 1800), frames: [lower, upper]), 1)
  }

  func testSideBySideDisplaysUseTheirOwnTopEdgeAndIgnoreGaps() {
    let frames = [CGRect(x: 0, y: 0, width: 1440, height: 900),
                  CGRect(x: -1920, y: 200, width: 1920, height: 1080)]
    XCTAssertEqual(HistoryHangingLayout.edgeScreenIndex(at: CGPoint(x: -1, y: 1279), frames: frames), 1)
    XCTAssertEqual(HistoryHangingLayout.edgeScreenIndex(at: CGPoint(x: 0, y: 899), frames: frames), 0)
    XCTAssertNil(HistoryHangingLayout.edgeScreenIndex(at: CGPoint(x: -100, y: 100), frames: frames))
    XCTAssertNil(HistoryHangingLayout.edgeScreenIndex(at: CGPoint(x: 1500, y: 900), frames: frames))
  }

  func testCableWindowTracksEachConnectedDisplayWithoutInterceptingClicks() throws {
    guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires WindowServer") }
    let history = HistoryFloatingManager.shared
    let shelf = HistoryHangingManager.shared
    let style = history.displayStyle
    defer {
      shelf.stop()
      history.displayStyle = style
    }
    history.displayStyle = .hanging
    for screen in NSScreen.screens {
      shelf.show(on: screen)
      let cable = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "SnapzyHistoryCable" })
      let panel = try XCTUnwrap(NSApp.windows
        .first { $0.isVisible && $0.identifier?.rawValue == "SnapzyHistoryHanging" })
      XCTAssertEqual(cable.frame.minX, screen.frame.minX)
      XCTAssertEqual(cable.frame.maxX, screen.frame.maxX)
      XCTAssertEqual(cable.frame.maxY, screen.frame.maxY)
      XCTAssertLessThanOrEqual(panel.frame.maxY, screen.frame.maxY - screen.safeAreaInsets.top - 8)
      XCTAssertTrue(cable.ignoresMouseEvents)
      XCTAssertFalse(cable.canBecomeKey)
      shelf.hide(animated: false)
      XCTAssertFalse(cable.isVisible)
      XCTAssertFalse(panel.isVisible)
    }
  }

  func testTriggerUsesVeryTopAcrossEntireDisplayNotVisibleMenuBarEdge() {
    let screen = CGRect(x: -1440, y: 100, width: 1440, height: 900)
    for x: CGFloat in [-1440, -800, -1] {
      XCTAssertTrue(HistoryHangingLayout.isAtTopEdge(CGPoint(x: x, y: 999), screenFrame: screen))
      XCTAssertFalse(HistoryHangingLayout.isAtTopEdge(CGPoint(x: x, y: 976), screenFrame: screen))
    }
    XCTAssertFalse(HistoryHangingLayout.isAtTopEdge(CGPoint(x: 1, y: 999), screenFrame: screen))
    XCTAssertFalse(HistoryHangingLayout.isAtTopEdge(CGPoint(x: -800, y: 1001), screenFrame: screen))
  }

  func testPointerCanCrossMenuBarGapWithoutDismissal() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let panel = HistoryHangingLayout.frame(screenFrame: screen,
                                           visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 876), safeAreaTop: 0)
    XCTAssertTrue(HistoryHangingLayout.containsPointer(CGPoint(x: 10, y: 890), panelFrame: panel, screenFrame: screen))
    XCTAssertTrue(HistoryHangingLayout.containsPointer(
      CGPoint(x: panel.midX, y: panel.midY),
      panelFrame: panel,
      screenFrame: screen
    ))
    XCTAssertFalse(HistoryHangingLayout.containsPointer(
      CGPoint(x: panel.midX, y: panel.minY - 20),
      panelFrame: panel,
      screenFrame: screen
    ))
  }

  func testEdgeRequiresDwellAndResetsOnLeaving() {
    var state = HistoryEdgeHoverState()
    XCTAssertEqual(update(&state, edge: true, time: 0), .none)
    XCTAssertEqual(update(&state, edge: true, time: 0.1), .none)
    XCTAssertEqual(update(&state, edge: false, time: 0.15), .none)
    XCTAssertEqual(update(&state, edge: true, time: 0.2), .none)
    XCTAssertEqual(update(&state, edge: true, time: 0.4), .reveal)
  }

  func testLeavingShelfWaitsBeforeHidingAndReentryCancels() {
    var state = HistoryEdgeHoverState()
    XCTAssertEqual(update(&state, visible: true, inside: false, time: 0), .none)
    XCTAssertEqual(update(&state, visible: true, inside: true, time: 0.5), .none)
    XCTAssertEqual(update(&state, visible: true, time: 0.6), .none)
    XCTAssertEqual(update(&state, visible: true, time: 1), .none)
    XCTAssertEqual(update(&state, visible: true, time: 1.3), .dismiss)
  }

  func testPinnedShelfAndActiveDragStayOpen() {
    var state = HistoryEdgeHoverState()
    XCTAssertEqual(update(&state, visible: true, keepOpen: true, time: 0), .none)
    XCTAssertEqual(update(&state, visible: true, keepOpen: true, time: 10), .none)
    XCTAssertEqual(update(&state, visible: true, time: 11), .none)
    XCTAssertEqual(update(&state, visible: true, time: 12), .dismiss)
  }

  func testModalSuppressionHidesEvenPinnedAndRequiresLeavingEdge() {
    var state = HistoryEdgeHoverState()
    XCTAssertEqual(update(&state, edge: true, visible: true, keepOpen: true, suppressed: true, time: 0), .dismiss)
    XCTAssertEqual(update(&state, edge: true, time: 1), .none)
    XCTAssertEqual(update(&state, edge: true, time: 2), .none)
    XCTAssertEqual(update(&state, edge: false, time: 3), .none)
    XCTAssertEqual(update(&state, edge: true, time: 4), .none)
    XCTAssertEqual(update(&state, edge: true, time: 4.2), .reveal)
  }

  func testEscapeDoesNotImmediatelyReopenAtEdge() {
    var state = HistoryEdgeHoverState()
    state.dismiss()
    XCTAssertEqual(update(&state, edge: true, time: 0), .none)
    XCTAssertEqual(update(&state, edge: true, time: 10), .none)
    XCTAssertEqual(update(&state, edge: false, time: 11), .none)
    XCTAssertEqual(update(&state, edge: true, time: 12), .none)
    XCTAssertEqual(update(&state, edge: true, time: 12.2), .reveal)
  }

  func testSuppressedEdgeCannotAccumulateDwell() {
    var state = HistoryEdgeHoverState()
    XCTAssertEqual(update(&state, edge: true, suppressed: true, time: 0), .none)
    XCTAssertEqual(update(&state, edge: true, suppressed: true, time: 2), .none)
    XCTAssertEqual(update(&state, edge: true, time: 3), .none)
  }

  func testHangingOpensWhenTraditionalFloatingPanelDisabledAndStopsOnStyleChange() throws {
    guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires WindowServer") }
    let history = HistoryFloatingManager.shared
    let style = history.displayStyle
    let enabled = history.isEnabled
    let shelf = HistoryHangingManager.shared
    defer {
      shelf.stop()
      history.displayStyle = style
      history.isEnabled = enabled
    }
    history.hide()
    history.isEnabled = false
    history.displayStyle = .hanging
    shelf.start()
    history.show()
    XCTAssertTrue(shelf.isVisible)
    history.displayStyle = .traditional
    XCTAssertFalse(shelf.isVisible)
  }

  func testDisabledHistoryMonitorsOnlyWhileManuallyOpened() throws {
    guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires WindowServer") }
    let history = HistoryFloatingManager.shared
    let shelf = HistoryHangingManager.shared
    let style = history.displayStyle
    let enabled = UserDefaults.standard.object(forKey: PreferencesKeys.historyEnabled)
    defer {
      shelf.stop()
      history.displayStyle = style
      UserDefaults.standard.set(enabled, forKey: PreferencesKeys.historyEnabled)
    }
    UserDefaults.standard.set(false, forKey: PreferencesKeys.historyEnabled)
    history.displayStyle = .hanging
    shelf.start()
    shelf.updateConfiguration()
    XCTAssertFalse(shelf.isMonitoring)
    shelf.show()
    XCTAssertTrue(shelf.isVisible)
    XCTAssertTrue(shelf.isMonitoring)
    shelf.updateConfiguration()
    XCTAssertTrue(shelf.isMonitoring)
    shelf.hide(animated: false)
    XCTAssertFalse(shelf.isMonitoring)
    UserDefaults.standard.set(true, forKey: PreferencesKeys.historyEnabled)
    shelf.updateConfiguration()
    XCTAssertTrue(shelf.isMonitoring)
    history.displayStyle = .traditional
    XCTAssertFalse(shelf.isMonitoring)
  }

  func testCaptureSuspensionPreservesExplicitEdgeDismissal() {
    var state = HistoryEdgeHoverState()
    state.dismiss()
    state.suspend(atEdge: true)
    XCTAssertEqual(update(&state, edge: true, time: 1), .none)
    XCTAssertEqual(update(&state, edge: true, time: 2), .none)
    state.suspend(atEdge: false)
    XCTAssertEqual(update(&state, edge: true, time: 3), .none)
    XCTAssertEqual(update(&state, edge: true, time: 3.2), .reveal)
  }

  func testCaptureSuspensionRestartsDwellWithoutRequiringEdgeExit() {
    var state = HistoryEdgeHoverState()
    XCTAssertEqual(update(&state, edge: true, time: 0), .none)
    state.suspend(atEdge: true)
    XCTAssertEqual(update(&state, edge: true, time: 1), .none)
    XCTAssertEqual(update(&state, edge: true, time: 1.2), .reveal)
  }

  func testRecordingControlsDoNotDismissOrBlockHanging() async throws {
    try await withCaptureWindows { shelf, _, controls, screen in
      controls.orderFrontRegardless()
      for state: RecordingState in [.preparing, .recording, .paused, .stopping] {
        ScreenRecordingManager.shared.setStateForTesting(state)
        shelf.show(on: screen, fromEdge: true)
        shelf.keepOpen = true
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(shelf.isVisible, "Recording state: \(state)")
        XCTAssertTrue(shelf.isRevealed)
        shelf.hide(animated: false)
      }
    }
  }

  func testCaptureOverlayTemporarilyHidesAndRestoresSamePinnedShelf() async throws {
    try await withCaptureWindows { shelf, overlay, controls, screen in
      shelf.show(on: screen)
      shelf.keepOpen = true
      try await Task.sleep(nanoseconds: 250_000_000)
      let panel = try XCTUnwrap(self.hangingWindow)
      let cable = try XCTUnwrap(NSApp.windows.first { $0.identifier?.rawValue == "SnapzyHistoryCable" && $0.isVisible })
      controls.orderFrontRegardless()
      overlay.orderFrontRegardless()
      try await Task.sleep(nanoseconds: 250_000_000)
      XCTAssertFalse(shelf.isVisible)
      XCTAssertFalse(panel.isVisible)
      XCTAssertFalse(cable.isVisible)
      XCTAssertTrue(shelf.keepOpen)
      XCTAssertTrue(shelf.isMonitoring)
      shelf.show(on: screen)
      XCTAssertFalse(shelf.isVisible)
      overlay.orderOut(nil)
      try await Task.sleep(nanoseconds: 250_000_000)
      XCTAssertTrue(shelf.isVisible)
      XCTAssertTrue(panel.isVisible)
      XCTAssertTrue(cable.isVisible)
      XCTAssertTrue(shelf.keepOpen)
      XCTAssertTrue(self.hangingWindow === panel)
    }
  }

  func testCaptureDuringOpeningPreservesShelfForRestoration() async throws {
    try await withCaptureWindows { shelf, overlay, _, screen in
      shelf.show(on: screen)
      let panel = try XCTUnwrap(self.hangingWindow)
      overlay.orderFrontRegardless()
      try await Task.sleep(nanoseconds: 250_000_000)
      XCTAssertFalse(shelf.isVisible)
      overlay.orderOut(nil)
      try await Task.sleep(nanoseconds: 250_000_000)
      XCTAssertTrue(shelf.isVisible)
      XCTAssertTrue(shelf.isRevealed)
      XCTAssertTrue(self.hangingWindow === panel)
    }
  }

  func testCaptureDuringDismissalDoesNotRestoreShelf() async throws {
    try await withCaptureWindows { shelf, overlay, _, screen in
      shelf.show(on: screen)
      try await Task.sleep(nanoseconds: 250_000_000)
      shelf.hide(animated: true)
      overlay.orderFrontRegardless()
      try await Task.sleep(nanoseconds: 150_000_000)
      XCTAssertFalse(shelf.isVisible)
      overlay.orderOut(nil)
      try await Task.sleep(nanoseconds: 250_000_000)
      XCTAssertFalse(shelf.isVisible)
      XCTAssertNil(self.hangingWindow)
    }
  }

  func testManuallyOpenedShelfResumesEvenWhenHistoryStorageIsDisabled() async throws {
    try await withCaptureWindows { shelf, overlay, _, screen in
      UserDefaults.standard.set(false, forKey: PreferencesKeys.historyEnabled)
      shelf.show(on: screen)
      try await Task.sleep(nanoseconds: 250_000_000)
      overlay.orderFrontRegardless()
      try await Task.sleep(nanoseconds: 250_000_000)
      shelf.updateConfiguration()
      XCTAssertFalse(shelf.isVisible)
      XCTAssertTrue(shelf.isMonitoring)
      overlay.orderOut(nil)
      try await Task.sleep(nanoseconds: 250_000_000)
      XCTAssertTrue(shelf.isVisible)
      shelf.hide(animated: false)
      XCTAssertFalse(shelf.isMonitoring)
    }
  }

  func testExplicitDismissDuringCaptureDoesNotRestoreShelf() async throws {
    try await withCaptureWindows { shelf, overlay, _, screen in
      shelf.show(on: screen)
      try await Task.sleep(nanoseconds: 250_000_000)
      overlay.orderFrontRegardless()
      try await Task.sleep(nanoseconds: 250_000_000)
      XCTAssertFalse(shelf.isVisible)
      shelf.toggle()
      overlay.orderOut(nil)
      try await Task.sleep(nanoseconds: 250_000_000)
      XCTAssertFalse(shelf.isVisible)
      XCTAssertNil(self.hangingWindow)
    }
  }

  func testChangingStyleDuringCaptureCancelsRestoration() async throws {
    try await withCaptureWindows { shelf, overlay, _, screen in
      shelf.show(on: screen)
      try await Task.sleep(nanoseconds: 250_000_000)
      overlay.orderFrontRegardless()
      try await Task.sleep(nanoseconds: 250_000_000)
      HistoryFloatingManager.shared.displayStyle = .traditional
      overlay.orderOut(nil)
      try await Task.sleep(nanoseconds: 250_000_000)
      XCTAssertFalse(shelf.isVisible)
      XCTAssertFalse(shelf.isMonitoring)
      XCTAssertNil(self.hangingWindow)
    }
  }

  func testBrowserModelsReleaseWithoutAnIsolatedDeinitHop() {
    weak var search: HistorySearchViewModel?
    weak var scroll: HistoryScrollController?
    autoreleasepool {
      let searchModel = HistorySearchViewModel()
      let scrollController = HistoryScrollController()
      search = searchModel
      scroll = scrollController
      XCTAssertNotNil(search)
      XCTAssertNotNil(scroll)
    }
    XCTAssertNil(search)
    XCTAssertNil(scroll)
  }

  func testReturningFromBrowserReleasesEscapeAndPinState() async throws {
    try await withCaptureWindows { shelf, _, _, _ in
      let history = HistoryFloatingManager.shared
      let probe = EscapeProbeView()
      let window = NSWindow(contentRect: CGRect(x: 300, y: 300, width: 100, height: 100),
                            styleMask: .titled, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = probe
      defer { window.close() }
      for action in [history.show, history.showCompact, history.collapse] {
        history.showExpanded()
        history.togglePin()
        XCTAssertTrue(history.isPinned)
        action()
        XCTAssertFalse(history.isPinned)
        shelf.hide(animated: false)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(probe)
        let event = try XCTUnwrap(NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
          windowNumber: window.windowNumber, context: nil, characters: "\u{1B}",
          charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53
        ))
        let previousCount = probe.escapeCount
        NSApp.sendEvent(event)
        XCTAssertEqual(probe.escapeCount, previousCount + 1)
      }
    }
  }

  private final class EscapeProbeView: NSView {
    deinit {}

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

  func testNativeHangingDuringScreenRecordingAndScreenshot() async throws {
    guard ProcessInfo.processInfo.environment["SNAPZY_HANGING_CAPTURE_INTERACTIVE"] == "1" else {
      throw XCTSkip("Opt-in native capture interaction")
    }
    guard CGPreflightScreenCaptureAccess() else { throw XCTSkip("Screen Recording permission required") }
    try await withCaptureWindows { shelf, overlay, controls, screen in
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HangingCapture-\(UUID())")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let frame = HistoryHangingLayout.frame(screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
                                             safeAreaTop: screen.safeAreaInsets.top)
      let fixture = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
      fixture.isReleasedWhenClosed = false
      fixture.backgroundColor = .white
      fixture.sharingType = .readOnly
      fixture.title = "Hanging Capture Test Background"
      fixture.orderFrontRegardless()
      let defaults = UserDefaults.standard
      let inclusion = defaults.object(forKey: PreferencesKeys.screenshotIncludeOwnApp)
      defaults.set(false, forKey: PreferencesKeys.screenshotIncludeOwnApp)
      defer {
        fixture.close()
        defaults.set(inclusion, forKey: PreferencesKeys.screenshotIncludeOwnApp)
        try? FileManager.default.removeItem(at: directory)
      }
      let recorder = ScreenRecordingManager.shared
      let originalPointer = NSEvent.mouseLocation
      let primaryTop = NSScreen.screens[0].frame.maxY
      func movePointer(to point: CGPoint) {
        CGWarpMouseCursorPosition(CGPoint(x: point.x, y: primaryTop - point.y))
      }
      defer { movePointer(to: originalPointer) }
      do {
        controls.orderFrontRegardless()
        try await recorder.prepareRecording(rect: frame, format: .mp4, quality: .high, fps: 15,
                                            maxResolution: .native, captureSystemAudio: false,
                                            captureMicrophone: false, showCursor: false,
                                            saveDirectory: directory, fileName: "Hanging Capture Test",
                                            excludeOwnApplication: true)
        await recorder.addExceptedWindow(windowID: CGWindowID(fixture.windowNumber))
        try await recorder.startRecording()
        movePointer(to: CGPoint(x: screen.frame.midX, y: screen.frame.minY + 30))
        try await Task.sleep(nanoseconds: 150_000_000)
        movePointer(to: CGPoint(x: screen.frame.midX, y: screen.frame.maxY))
        print("HANGING_CAPTURE_RECORDING pid=\(ProcessInfo.processInfo.processIdentifier)")
        try await self.waitForCaptureInteraction { shelf.isVisible && shelf.isRevealed }
        shelf.keepOpen = true
        print("HANGING_CAPTURE_REVEALED")
        try await Task.sleep(nanoseconds: 1_200_000_000)
        recorder.pauseRecording()
        shelf.hide(animated: false)
        movePointer(to: CGPoint(x: screen.frame.midX, y: screen.frame.minY + 30))
        try await Task.sleep(nanoseconds: 150_000_000)
        movePointer(to: CGPoint(x: screen.frame.midX, y: screen.frame.maxY))
        print("HANGING_CAPTURE_PAUSED")
        try await self.waitForCaptureInteraction { shelf.isVisible && shelf.isRevealed }
        shelf.keepOpen = true
        recorder.resumeRecording()
        let panel = try XCTUnwrap(self.hangingWindow)
        overlay.orderFrontRegardless()
        try await self.waitForCaptureInteraction { !shelf.isVisible }
        overlay.orderOut(nil)
        try await self.waitForCaptureInteraction { shelf.isVisible }
        XCTAssertTrue(self.hangingWindow === panel)
        XCTAssertTrue(shelf.keepOpen)
        let capture = await ScreenCaptureManager.shared.captureArea(
          rect: frame, saveDirectory: directory, fileName: "Hanging Screenshot Test",
          excludeOwnApplication: false, invocation: .headless(includeWindowShadow: false)
        )
        guard case .success(let screenshotURL) = capture else {
          XCTFail("Screenshot capture failed")
          await recorder.cancelRecording()
          return
        }
        try await self.waitForCaptureInteraction { shelf.isVisible }
        XCTAssertTrue(shelf.keepOpen)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: screenshotURL)))
        self.assertWhiteCapture(bitmap)
        try await Task.sleep(nanoseconds: 700_000_000)
        let recordingURL = await recorder.stopRecording()
        let asset = try AVURLAsset(url: XCTUnwrap(recordingURL))
        let duration = try await asset.load(.duration).seconds
        XCTAssertGreaterThan(duration, 1)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        for seconds in stride(from: 0.3, to: duration - 0.1, by: 0.3) {
          let result = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
          self.assertWhiteCapture(NSBitmapImageRep(cgImage: result.image))
        }
        XCTAssertTrue(shelf.isVisible)
        print("HANGING_CAPTURE_VERIFIED duration=\(duration)")
      } catch {
        await recorder.cancelRecording()
        throw error
      }
    }
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

  func testNativeHangingHistoryInteraction() throws {
    guard ProcessInfo.processInfo.environment["SNAPZY_HANGING_INTERACTIVE"] == "1" else {
      throw XCTSkip("Opt-in native History interaction")
    }
    guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires WindowServer") }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HangingHistory-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let history = HistoryFloatingManager.shared
    let shelf = HistoryHangingManager.shared
    let store = CaptureHistoryStore.shared
    let style = history.displayStyle
    let enabled = history.isEnabled
    let oldDefaults = store.userDefaults
    let oldFilter = history.defaultFilter
    let oldMaximum = history.maxDisplayedItems
    history.defaultFilter = nil
    history.maxDisplayedItems = 20
    let defaultsName = "HangingHistory-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
    defaults.set(true, forKey: PreferencesKeys.historyEnabled)
    store.userDefaults = defaults
    var ids: [UUID] = []
    let window = NSWindow(contentRect: CGRect(x: 400, y: 120, width: 720, height: 620),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.title = "History Settings Test"
    let originalAppearance = NSApp.appearance
    NSApp.appearance = NSAppearance(named: .darkAqua)
    defer {
      window.close()
      shelf.stop()
      history.hide()
      history.displayStyle = style
      history.isEnabled = enabled
      store.remove(ids: ids)
      store.userDefaults = oldDefaults
      history.defaultFilter = oldFilter
      history.maxDisplayedItems = oldMaximum
      defaults.removePersistentDomain(forName: defaultsName)
      NSApp.appearance = originalAppearance
      try? FileManager.default.removeItem(at: directory)
    }
    for index in 0 ..< 6 {
      let url = try makeImage(index: index, directory: directory)
      let record = CaptureHistoryRecord(id: UUID(), filePath: url.path, fileName: url.lastPathComponent,
                                        captureType: .screenshot, fileSize: 1000,
                                        capturedAt: Date().addingTimeInterval(-Double(index) * 60),
                                        width: 640, height: 400, thumbnailPath: nil, isDeleted: false)
      ids.append(record.id)
      store.add(record)
    }
    store.refreshRecords()
    history.displayStyle = .traditional
    shelf.start()
    window.contentView = NSHostingView(rootView: HistorySettingsView())
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    print("HANGING_UI_READY pid=\(ProcessInfo.processInfo.processIdentifier)")
    try waitForInteraction { history.displayStyle == .hanging }
    print("HANGING_STYLE_SELECTED monitoring=\(shelf.isMonitoring)")
    try waitForInteraction { shelf.isVisible && shelf.isRevealed }
    print("HANGING_REVEALED")
    try waitForInteraction { !shelf.isVisible }
    print("HANGING_AUTOHIDDEN")
    try waitForInteraction { shelf.isVisible && shelf.isRevealed }
    print("HANGING_REVEALED_AGAIN")
    try waitForInteraction { shelf.keepOpen }
    print("HANGING_KEEP_OPEN")
    try waitForInteraction { !shelf.pinnedIDs.isEmpty }
    print("HANGING_PINNED")
    try waitForInteraction { self.previewWindow != nil }
    let preview = try XCTUnwrap(previewWindow)
    XCTAssertTrue(preview.ignoresMouseEvents)
    XCTAssertFalse(preview.canBecomeKey)
    XCTAssertTrue(NSScreen.screens.contains { $0.visibleFrame.contains(preview.frame) })
    print("HANGING_PREVIEW")
    try waitForInteraction { self.previewWindow == nil }
    let url = try makeImage(index: 6, directory: directory)
    let newest = CaptureHistoryRecord(id: UUID(), filePath: url.path, fileName: url.lastPathComponent,
                                      captureType: .screenshot, fileSize: 1000, capturedAt: Date(),
                                      width: 640, height: 400, thumbnailPath: nil, isDeleted: false)
    ids.append(newest.id)
    store.add(newest)
    store.refreshRecords()
    print("HANGING_INSERTED id=\(newest.id)")
    try waitForInteraction { !shelf.keepOpen }
    shelf.toggleKeepOpen()
    for type: CaptureHistoryType in [.video, .gif] {
      history.defaultFilter = type
      let settledAt = Date().addingTimeInterval(0.8)
      try waitForInteraction { Date() >= settledAt }
      print("HANGING_EMPTY_\(type.rawValue.uppercased())")
      try waitForInteraction { !shelf.keepOpen }
      shelf.toggleKeepOpen()
      XCTAssertNil(previewWindow)
    }
    history.defaultFilter = nil
    print("HANGING_FINISHED")
    try waitForInteraction { history.isTraditionalPanelVisible }
    XCTAssertEqual(store.records.filter { ids.contains($0.id) }.count, 7)
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
