//
//  RecordingDisplaySelectionLogicTests.swift
//  SnapzyTests
//
//  Unit tests for picking a whole display in the recording overlay: the mode transition
//  table, plain-click resolution, display hit-testing on a real 3-display layout, the
//  Fullscreen toggle's display choice, and the last-area persistence rule.
//

import CoreGraphics
@testable import Snapzy
import XCTest

final class RecordingDisplaySelectionLogicTests: XCTestCase {
  private typealias Logic = RecordingDisplaySelectionLogic

  // MARK: - Mode transitions

  func testEnter_fromManualRegion_entersFullDisplay() {
    XCTAssertEqual(next(.manualRegion, .enter), .fullDisplay)
  }

  func testEnter_fromApplicationWindow_entersFullDisplay() {
    XCTAssertEqual(next(.applicationWindow, .enter), .fullDisplay)
  }

  func testEnter_fromFullDisplay_returnsToManualRegion() {
    XCTAssertEqual(next(.fullDisplay, .enter), .manualRegion)
  }

  func testEnter_needsNoWindowData() {
    XCTAssertEqual(next(.applicationWindow, .enter, allowsApplicationWindow: false), .fullDisplay)
    XCTAssertEqual(next(.manualRegion, .enter, allowsApplicationWindow: false), .fullDisplay)
  }

  func testApplicationToggle_fromManualRegion_entersApplicationWindow() {
    XCTAssertEqual(next(.manualRegion, .applicationToggle), .applicationWindow)
  }

  func testApplicationToggle_fromApplicationWindow_returnsToManualRegion() {
    XCTAssertEqual(next(.applicationWindow, .applicationToggle), .manualRegion)
  }

  func testApplicationToggle_fromFullDisplay_entersApplicationWindow() {
    XCTAssertEqual(next(.fullDisplay, .applicationToggle), .applicationWindow)
  }

  func testApplicationToggle_withoutWindowData_isRefused() {
    for mode in [AreaSelectionInteractionMode.manualRegion, .applicationWindow, .fullDisplay] {
      XCTAssertNil(next(mode, .applicationToggle, allowsApplicationWindow: false), "\(mode)")
    }
  }

  func testEveryTransition_isRefusedWhileDragging() {
    for mode in [AreaSelectionInteractionMode.manualRegion, .applicationWindow, .fullDisplay] {
      XCTAssertNil(next(mode, .enter, isDragging: true), "Enter from \(mode)")
      XCTAssertNil(next(mode, .applicationToggle, isDragging: true), "A from \(mode)")
    }
  }

  // MARK: - Plain-click resolution

  func testClick_withAutoDetectOff_alwaysSelectsDisplay() {
    for hasElement in [false, true] {
      for hasWindow in [false, true] {
        XCTAssertEqual(
          Logic.clickResolution(hasHoveredElement: hasElement, hasHoveredWindow: hasWindow, autoDetect: false),
          .display,
          "element=\(hasElement) window=\(hasWindow)"
        )
      }
    }
  }

  func testClick_withAutoDetectOn_prefersElementThenWindowThenDisplay() {
    XCTAssertEqual(Logic.clickResolution(hasHoveredElement: true, hasHoveredWindow: true, autoDetect: true), .element)
    XCTAssertEqual(Logic.clickResolution(hasHoveredElement: true, hasHoveredWindow: false, autoDetect: true), .element)
    XCTAssertEqual(Logic.clickResolution(hasHoveredElement: false, hasHoveredWindow: true, autoDetect: true), .window)
    XCTAssertEqual(Logic.clickResolution(hasHoveredElement: false, hasHoveredWindow: false, autoDetect: true), .display)
  }

  // MARK: - Display hit-testing

  /// The user's layout in AppKit global coordinates: a 2560x1440 main display at the origin,
  /// a 1440x2560 portrait display to its left (negative x, extending below the main display),
  /// and a 2560x1440 display to the right, raised 200 pt so it is misaligned with the main one.
  private let mainFrame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
  private let portraitFrame = CGRect(x: -1440, y: -560, width: 1440, height: 2560)
  private let rightFrame = CGRect(x: 2560, y: 200, width: 2560, height: 1440)

  private var screens: [(id: CGDirectDisplayID, frame: CGRect)] {
    [(id: 1, frame: mainFrame), (id: 2, frame: portraitFrame), (id: 3, frame: rightFrame)]
  }

  private func displayID(at point: CGPoint) -> CGDirectDisplayID? {
    Logic.display(containing: point, screens: screens)?.id
  }

  func testDisplay_resolvesInteriorPointOfEachDisplay() {
    XCTAssertEqual(displayID(at: CGPoint(x: 1280, y: 720)), 1)
    XCTAssertEqual(displayID(at: CGPoint(x: -720, y: 700)), 2)
    XCTAssertEqual(displayID(at: CGPoint(x: 3840, y: 900)), 3)
  }

  func testDisplay_resolvesNegativeOriginDisplay() {
    let result = Logic.display(containing: CGPoint(x: -1, y: -500), screens: screens)
    XCTAssertEqual(result?.id, 2)
    XCTAssertEqual(result?.frame, portraitFrame)
  }

  func testDisplay_sharedVerticalEdge_resolvesToExactlyOneDisplay() {
    // x == 0 is the portrait display's maxX and the main display's minX.
    XCTAssertEqual(displayID(at: CGPoint(x: 0, y: 700)), 1)
    // x == 2560 is the main display's maxX and the right display's minX.
    XCTAssertEqual(displayID(at: CGPoint(x: 2560, y: 700)), 3)
  }

  func testDisplay_topEdgeBelongsToDisplay_bottomEdgeDoesNot() {
    // AppKit mouse locations run over (minY, maxY], matching NSMouseInRect for unflipped views.
    XCTAssertEqual(displayID(at: CGPoint(x: 1280, y: 1440)), 1)
    XCTAssertNil(displayID(at: CGPoint(x: 1280, y: 0)))
  }

  func testDisplay_pointInGapBetweenMisalignedDisplays_returnsNil() {
    // Right of the main display's top edge, below the raised right display.
    XCTAssertNil(displayID(at: CGPoint(x: 2600, y: 100)))
    // Above the main display.
    XCTAssertNil(displayID(at: CGPoint(x: 1280, y: 1500)))
  }

  // MARK: - Fullscreen toggle keeps the picked display

  func testDisplayFrame_forPickedDisplayFrame_returnsThatDisplay() {
    XCTAssertEqual(
      Logic.displayFrame(bestMatching: rightFrame, screenFrames: [mainFrame, portraitFrame, rightFrame]),
      rightFrame
    )
    XCTAssertEqual(
      Logic.displayFrame(bestMatching: portraitFrame, screenFrames: [mainFrame, portraitFrame, rightFrame]),
      portraitFrame
    )
  }

  func testDisplayFrame_forAreaSpanningDisplays_returnsLargestOverlap() {
    let area = CGRect(x: 2400, y: 400, width: 600, height: 300) // 160 pt on main, 440 pt on right
    XCTAssertEqual(
      Logic.displayFrame(bestMatching: area, screenFrames: [mainFrame, portraitFrame, rightFrame]),
      rightFrame
    )
  }

  func testDisplayFrame_withoutSelectionOrOverlap_returnsNil() {
    XCTAssertNil(Logic.displayFrame(bestMatching: nil, screenFrames: [mainFrame]))
    XCTAssertNil(Logic.displayFrame(bestMatching: CGRect(x: 9000, y: 9000, width: 10, height: 10), screenFrames: [mainFrame]))
  }

  // MARK: - Last-area persistence

  func testDisplaySelection_doesNotOverwriteSavedLastArea() {
    XCTAssertFalse(Logic.shouldSaveLastArea(for: .fullscreen))
  }

  func testAreaAndWindowSelections_stillSaveLastArea() {
    XCTAssertTrue(Logic.shouldSaveLastArea(for: .area))
    XCTAssertTrue(Logic.shouldSaveLastArea(for: .application))
  }

  // MARK: - Display target

  func testDisplayTarget_rectIsItsFrame_andHasNoWindowTarget() {
    let target = AreaSelectionTarget.display(3, frame: rightFrame)
    XCTAssertEqual(target.rect, rightFrame)
    XCTAssertNil(target.windowTarget)
  }

  // MARK: - Helpers

  private func next(
    _ mode: AreaSelectionInteractionMode,
    _ key: RecordingDisplaySelectionLogic.ModeKey,
    allowsApplicationWindow: Bool = true,
    isDragging: Bool = false
  ) -> AreaSelectionInteractionMode? {
    Logic.nextMode(from: mode, key: key, allowsApplicationWindow: allowsApplicationWindow, isDragging: isDragging)
  }
}
