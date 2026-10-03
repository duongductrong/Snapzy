//
//  VideoEditorZoomAndAutoFocusTests.swift
//  SnapzyTests
//
//  Unit tests for video editor zoom math and Smart Camera autofocus paths.
//

import CoreGraphics
@testable import Snapzy
import XCTest

final class VideoEditorZoomAndAutoFocusTests: XCTestCase {
  func testCalculateCropRect_flipsYAndClampsToFrameBounds() {
    let rect = ZoomCalculator.calculateCropRect(
      center: CGPoint(x: 0.25, y: 0.25),
      zoomLevel: 2,
      frameSize: CGSize(width: 1920, height: 1080)
    )

    assertEqual(rect.origin.x, 0)
    assertEqual(rect.origin.y, 540)
    assertEqual(rect.width, 960)
    assertEqual(rect.height, 540)
  }

  func testCalculateCropRect_noZoomReturnsFullFrame() {
    let frameSize = CGSize(width: 1280, height: 720)

    let rect = ZoomCalculator.calculateCropRect(
      center: CGPoint(x: 0.9, y: 0.1),
      zoomLevel: 1,
      frameSize: frameSize
    )

    XCTAssertEqual(rect, CGRect(origin: .zero, size: frameSize))
  }

  func testInterpolateZoom_shortSegmentKeepsTransitionsInsideDuration() {
    let segment = ZoomSegment(
      startTime: 10,
      duration: 0.5,
      zoomLevel: 3,
      zoomCenter: CGPoint(x: 0.2, y: 0.8)
    )

    let start = ZoomCalculator.interpolateZoom(segment: segment, currentTime: 10, transitionDuration: 0.4)
    let middle = ZoomCalculator.interpolateZoom(segment: segment, currentTime: 10.25, transitionDuration: 0.4)
    let end = ZoomCalculator.interpolateZoom(segment: segment, currentTime: 10.5, transitionDuration: 0.4)

    assertEqual(start.level, 1)
    XCTAssertEqual(start.progress, 0, accuracy: 0.0001)
    XCTAssertGreaterThan(middle.level, 2.5)
    XCTAssertEqual(middle.progress, 1, accuracy: 0.0001)
    assertEqual(middle.center.x, 0.2)
    assertEqual(middle.center.y, 0.8)
    assertEqual(end.level, 1)
    XCTAssertEqual(end.progress, 0, accuracy: 0.0001)
  }

  func testActiveSegment_prefersLatestEnabledOverlappingSegment() {
    let first = ZoomSegment(id: UUID(), startTime: 0, duration: 4)
    let disabled = ZoomSegment(id: UUID(), startTime: 2, duration: 4, isEnabled: false)
    let latest = ZoomSegment(id: UUID(), startTime: 2.5, duration: 4)

    let active = ZoomCalculator.activeSegment(at: 3, in: [first, disabled, latest])

    XCTAssertEqual(active?.id, latest.id)
  }

  func testZoomTimelineRange_staysIndependentAfterClipReorder() {
    let first = TimelineClip(source: .primary, sourceDuration: 10, sourceStart: 0, sourceEnd: 5)
    let second = TimelineClip(source: .primary, sourceDuration: 10, sourceStart: 5, sourceEnd: 10)
    let clips = [second, first]
    let zoom = ZoomSegment(startTime: 1, duration: 2)

    let pieces = TimelineSequence.project(
      timelineRange: zoom.startTime ... zoom.endTime,
      from: TimelineSequence.layout(clips),
      to: TimelineSequence.playableLayout(clips)
    )

    XCTAssertEqual(pieces, [1 ... 3])
    XCTAssertEqual(ZoomCalculator.activeSegment(at: 2, in: [zoom])?.id, zoom.id)
  }

  func testHasOverlap_honorsExcludedSegment() {
    let existing = ZoomSegment(id: UUID(), startTime: 2, duration: 3)

    XCTAssertTrue(ZoomCalculator.hasOverlap(at: 4, duration: 1, in: [existing]))
    XCTAssertFalse(ZoomCalculator.hasOverlap(at: 4, duration: 1, in: [existing], excluding: existing.id))
    XCTAssertFalse(ZoomCalculator.hasOverlap(at: 6, duration: 1, in: [existing]))
  }

  func testCalculateTransform_offsetsFromNormalizedCenter() {
    let transform = ZoomCalculator.calculateTransform(
      zoomLevel: 2,
      center: CGPoint(x: 0.75, y: 0.25),
      viewSize: CGSize(width: 800, height: 600)
    )

    assertEqual(transform.scale, 2)
    assertEqual(transform.offset.width, -400)
    assertEqual(transform.offset.height, 300)
  }

  func testAutoFocusBuildPath_returnsEmptyForManualOrInsufficientSamples() {
    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 100, height: 100),
      samplesPerSecond: 60,
      mouseSamples: [
        RecordedMouseSample(time: 0, normalizedX: 0.5, normalizedY: 0.5, isInsideCapture: true),
      ]
    )

    XCTAssertTrue(VideoEditorAutoFocusEngine.buildPath(
      from: metadata,
      segment: ZoomSegment(startTime: 0, zoomType: .manual)
    ).isEmpty)
    XCTAssertTrue(VideoEditorAutoFocusEngine.buildPath(
      from: metadata,
      segment: ZoomSegment(startTime: 0, zoomType: .auto)
    ).isEmpty)
  }

  func testAutoFocusBuildPath_canonicalizesBottomLeftCoordinatesAndClampsInitialCenter() throws {
    let metadata = RecordingMetadata(
      coordinateSpace: .bottomLeftNormalized,
      captureSize: CGSize(width: 100, height: 100),
      samplesPerSecond: 60,
      mouseSamples: [
        RecordedMouseSample(time: 0, normalizedX: 0.2, normalizedY: 0.2, isInsideCapture: true),
        RecordedMouseSample(time: 0.2, normalizedX: 0.8, normalizedY: 0.8, isInsideCapture: true),
      ]
    )
    let segment = ZoomSegment(
      startTime: 0,
      duration: 2,
      zoomLevel: 2,
      zoomType: .auto,
      followSpeed: 1,
      focusMargin: 0.2
    )

    let path = VideoEditorAutoFocusEngine.buildPath(from: metadata, segment: segment)

    let first = try XCTUnwrap(path.first)
    assertEqual(first.time, 0)
    assertEqual(first.center.x, 0.25)
    assertEqual(first.center.y, 0.75)
    XCTAssertGreaterThan(path.count, 2)
    XCTAssertGreaterThanOrEqual(path.last?.time ?? 0, 0.2)
  }

  func testAutoFocusTrimmedPath_interpolatesBoundarySamplesAndRebasesTime() {
    let path = [
      AutoFocusCameraSample(time: 0, center: CGPoint(x: 0.2, y: 0.2)),
      AutoFocusCameraSample(time: 1, center: CGPoint(x: 0.4, y: 0.6)),
      AutoFocusCameraSample(time: 2, center: CGPoint(x: 0.8, y: 0.4)),
    ]

    let trimmed = VideoEditorAutoFocusEngine.trimmedPath(path, trimStart: 0.5, trimEnd: 1.5)

    XCTAssertEqual(trimmed.count, 3)
    assertEqual(trimmed[0].time, 0)
    assertEqual(trimmed[0].center.x, 0.3)
    assertEqual(trimmed[0].center.y, 0.4)
    assertEqual(trimmed[1].time, 0.5)
    assertEqual(trimmed[1].center.x, 0.4)
    assertEqual(trimmed[1].center.y, 0.6)
    assertEqual(trimmed[2].time, 1)
    assertEqual(trimmed[2].center.x, 0.6)
    assertEqual(trimmed[2].center.y, 0.5)
  }

  func testAutoFocusCameraState_usesPathCenterAfterTransition() {
    let segment = ZoomSegment(
      startTime: 0,
      duration: 3,
      zoomLevel: 2,
      zoomCenter: CGPoint(x: 0.1, y: 0.1),
      zoomType: .auto
    )
    let path = [
      AutoFocusCameraSample(time: 0, center: CGPoint(x: 0.5, y: 0.5)),
      AutoFocusCameraSample(time: 1, center: CGPoint(x: 0.75, y: 0.25)),
    ]

    let state = VideoEditorAutoFocusEngine.cameraState(
      at: 1,
      segment: segment,
      path: path,
      transitionDuration: 0.2
    )

    assertEqual(state.zoomLevel, 2)
    assertEqual(state.center.x, 0.75)
    assertEqual(state.center.y, 0.25)
  }

  func testAutoFocusTimelinePath_followsPrimaryMaterialAfterReorder() throws {
    let first = TimelineClip(source: .primary, sourceDuration: 10, sourceStart: 0, sourceEnd: 5)
    let second = TimelineClip(source: .primary, sourceDuration: 10, sourceStart: 5, sourceEnd: 10)
    let placements = TimelineSequence.layout([second, first])
    let path = [
      AutoFocusCameraSample(time: 1, center: CGPoint(x: 0.2, y: 0.3)),
      AutoFocusCameraSample(time: 6, center: CGPoint(x: 0.8, y: 0.7)),
    ]

    let mapped = VideoEditorAutoFocusEngine.timelinePath(path, placements: placements)

    let firstMapped = try XCTUnwrap(mapped.first(where: { abs($0.time - 1) < 0.0001 }))
    let secondMapped = try XCTUnwrap(mapped.first(where: { abs($0.time - 6) < 0.0001 }))
    assertEqual(firstMapped.center.x, 0.8)
    assertEqual(secondMapped.center.x, 0.2)
  }

  func testAutoFocusSequencePath_holdsCenterAcrossInsertedClip() throws {
    let first = TimelineClip(source: .primary, sourceDuration: 10, sourceStart: 0, sourceEnd: 5)
    let inserted = TimelineClip(
      source: .file(url: URL(fileURLWithPath: "/tmp/intro.mov")),
      sourceDuration: 2
    )
    let second = TimelineClip(source: .primary, sourceDuration: 10, sourceStart: 5, sourceEnd: 10)
    let placements = TimelineSequence.playableLayout([first, inserted, second])
    let path = [
      AutoFocusCameraSample(time: 0, center: CGPoint(x: 0.2, y: 0.3)),
      AutoFocusCameraSample(time: 10, center: CGPoint(x: 0.8, y: 0.7)),
    ]

    let mapped = VideoEditorAutoFocusEngine.sequencePath(path, placements: placements, trimStart: 0)
    let insertedStart = try XCTUnwrap(mapped.first(where: { abs($0.time - 5) < 0.0001 }))
    let insertedEnd = try XCTUnwrap(mapped.first(where: { abs($0.time - 7) < 0.0001 }))

    assertEqual(insertedStart.center.x, insertedEnd.center.x)
    assertEqual(insertedStart.center.y, insertedEnd.center.y)
  }

  private func assertEqual(
    _ actual: CGFloat,
    _ expected: CGFloat,
    accuracy: CGFloat = 0.0001,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(Double(actual), Double(expected), accuracy: Double(accuracy), file: file, line: line)
  }

  private func assertEqual(
    _ actual: TimeInterval,
    _ expected: TimeInterval,
    accuracy: TimeInterval = 0.0001,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(actual, expected, accuracy: accuracy, file: file, line: line)
  }
}
