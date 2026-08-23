//
//  ScrollingCaptureWindowSharingTests.swift
//  SnapzyTests
//
//  Unit tests for scrolling capture session chrome capture exclusion.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class ScrollingCaptureWindowSharingTests: XCTestCase {

  func testPreviewWindow_isExcludedFromScreenCapture() {
    let model = ScrollingCaptureSessionModel(selectedRect: sampleAnchorRect)
    let window = ScrollingCapturePreviewWindow(anchorRect: sampleAnchorRect, model: model)
    defer { window.close() }

    XCTAssertEqual(window.sharingType, NSWindow.SharingType.none)
  }

  func testHUDWindow_isExcludedFromScreenCapture() {
    let model = ScrollingCaptureSessionModel(selectedRect: sampleAnchorRect)
    let window = ScrollingCaptureHUDWindow(
      anchorRect: sampleAnchorRect,
      model: model,
      onStart: {},
      onDone: {},
      onCancel: {},
      onToggleAutoScroll: {}
    )
    defer { window.close() }

    XCTAssertEqual(window.sharingType, NSWindow.SharingType.none)
  }

  func testAreaSelectionWindow_isVisibleToExternalScreenCapture() throws {
    let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
    let window = AreaSelectionWindow(screen: screen, pooled: true)
    defer { window.close() }

    XCTAssertEqual(window.sharingType, NSWindow.SharingType.readOnly)
  }

  func testRecordingRegionOverlay_isVisibleToExternalScreenCapture() throws {
    let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
    let window = RecordingRegionOverlayWindow(screen: screen, highlightRect: sampleAnchorRect)
    defer { window.close() }

    XCTAssertEqual(window.sharingType, NSWindow.SharingType.readOnly)
  }

  func testRecordingToolbar_isVisibleToExternalScreenCapture() {
    let window = RecordingToolbarWindow(anchorRect: sampleAnchorRect)
    defer { window.close() }

    XCTAssertEqual(window.sharingType, NSWindow.SharingType.readOnly)
  }

  func testSmartElementOverlay_isVisibleToExternalScreenCapture() throws {
    let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
    let window = SmartElementOverlayWindow(screen: screen)
    defer { window.close() }

    XCTAssertEqual(window.sharingType, NSWindow.SharingType.readOnly)
  }

  private var sampleAnchorRect: CGRect {
    CGRect(x: 120, y: 120, width: 360, height: 480)
  }
}

final class ScrollingCaptureAutoScrollPolicyTests: XCTestCase {

  func testCanToggleAutoScrollOnlyAfterFirstFrameLocks() {
    assertCanToggleAutoScroll(
      phase: .ready,
      acceptedFrameCount: 0,
      isAutoScrolling: false,
      expected: false
    )
    assertCanToggleAutoScroll(
      phase: .capturing,
      acceptedFrameCount: 0,
      isAutoScrolling: false,
      expected: false
    )
    assertCanToggleAutoScroll(
      phase: .capturing,
      acceptedFrameCount: 1,
      isAutoScrolling: false,
      expected: true
    )
    assertCanToggleAutoScroll(
      phase: .capturing,
      acceptedFrameCount: 0,
      isAutoScrolling: true,
      expected: true
    )
    assertCanToggleAutoScroll(
      phase: .finalizing,
      acceptedFrameCount: 1,
      isAutoScrolling: true,
      expected: false
    )
    assertCanToggleAutoScroll(
      phase: .saving,
      acceptedFrameCount: 1,
      isAutoScrolling: true,
      expected: false
    )
  }

  func testPlaceMouseInsideSelectionGuidance_usesWarningTone() {
    let guidance = ScrollingCaptureSelectionGuidanceKind.placeMouseInsideSelection.guidance

    XCTAssertFalse(guidance.title.isEmpty)
    XCTAssertFalse(guidance.detail?.isEmpty ?? true)
    if case .warning = guidance.tone {
      return
    }
    XCTFail("Expected warning guidance tone")
  }

  func testHUDWindowContentSize_usesMinimumForCompactContent() {
    XCTAssertEqual(
      ScrollingCaptureHUDWindow.resolvedContentSize(for: CGSize(width: 240.1, height: 32.4)),
      CGSize(width: 380, height: 44)
    )
  }

  func testHUDWindowContentSize_expandsToFitAutoScrollControls() {
    XCTAssertEqual(
      ScrollingCaptureHUDWindow.resolvedContentSize(for: CGSize(width: 431.2, height: 45.1)),
      CGSize(width: 432, height: 46)
    )
  }

  func testAutoScrollPolicy_usesCurrentPointerAsScrollTarget() {
    let mouseLocation = CGPoint(x: 180, y: 220)

    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.scrollTargetPoint(
        mouseLocation: mouseLocation,
        selectedRect: sampleAnchorRect
      ),
      mouseLocation
    )
  }

  func testAutoScrollPolicy_allowsSmallHoverPadding() {
    let mouseLocation = CGPoint(x: sampleAnchorRect.minX - 10, y: sampleAnchorRect.midY)

    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.scrollTargetPoint(
        mouseLocation: mouseLocation,
        selectedRect: sampleAnchorRect
      ),
      mouseLocation
    )
  }

  func testAutoScrollPolicy_rejectsPointerOutsideHoverPadding() {
    let mouseLocation = CGPoint(x: sampleAnchorRect.minX - 40, y: sampleAnchorRect.midY)

    XCTAssertNil(
      ScrollingCaptureAutoScrollPolicy.scrollTargetPoint(
        mouseLocation: mouseLocation,
        selectedRect: sampleAnchorRect
      )
    )
  }

  func testAutoScrollPolicy_finishesOnBoundaryOrHeightLimit() {
    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.stitchAction(
        for: stitchUpdate(outcome: .ignoredNoMovement, likelyReachedBoundary: true)
      ),
      .finishCapture
    )
    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.stitchAction(
        for: stitchUpdate(outcome: .reachedHeightLimit)
      ),
      .finishCapture
    )
  }

  func testAutoScrollPolicy_stopsAfterRepeatedAlignmentFailures() {
    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.stitchAction(
        for: stitchUpdate(outcome: .ignoredAlignmentFailed, matchFailureCount: 2)
      ),
      .keepScrolling
    )
    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.stitchAction(
        for: stitchUpdate(outcome: .ignoredAlignmentFailed, matchFailureCount: 3)
      ),
      .stopScrolling
    )
  }

  private var sampleAnchorRect: CGRect {
    CGRect(x: 120, y: 120, width: 360, height: 480)
  }

  private func assertCanToggleAutoScroll(
    phase: ScrollingCapturePhase,
    acceptedFrameCount: Int,
    isAutoScrolling: Bool,
    expected: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.canToggle(
        phase: phase,
        acceptedFrameCount: acceptedFrameCount,
        isAutoScrolling: isAutoScrolling
      ),
      expected,
      "phase=\(phase), acceptedFrameCount=\(acceptedFrameCount), isAutoScrolling=\(isAutoScrolling)",
      file: file,
      line: line
    )
  }

  private func stitchUpdate(
    outcome: ScrollingCaptureStitchOutcome,
    matchFailureCount: Int = 0,
    likelyReachedBoundary: Bool = false
  ) -> ScrollingCaptureStitchUpdate {
    ScrollingCaptureStitchUpdate(
      outcome: outcome,
      mergedImage: nil,
      acceptedFrameCount: 1,
      outputHeight: 480,
      matchFailureCount: matchFailureCount,
      mergeDirection: .appendFromBottom,
      likelyReachedBoundary: likelyReachedBoundary,
      safety: .confirmed,
      alignmentDebug: nil
    )
  }
}
