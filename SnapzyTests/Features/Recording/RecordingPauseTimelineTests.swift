//
//  RecordingPauseTimelineTests.swift
//  SnapzyTests
//
//  Unit tests for mapping capture timestamps across pause/resume.
//

import CoreMedia
import XCTest
@testable import Snapzy

final class RecordingPauseTimelineTests: XCTestCase {

  private func t(_ seconds: Double) -> CMTime {
    CMTime(seconds: seconds, preferredTimescale: 600)
  }

  func testOutputTime_withoutPause_isUnchanged() {
    let timeline = RecordingPauseTimeline()
    XCTAssertEqual(timeline.outputTime(for: t(3)), t(3))
  }

  func testOutputTime_dropsSamplesCapturedWhilePaused() {
    var timeline = RecordingPauseTimeline()
    timeline.pause(at: t(10))

    XCTAssertEqual(timeline.outputTime(for: t(9.9)), t(9.9), "in-flight pre-pause sample still lands")
    XCTAssertNil(timeline.outputTime(for: t(10)))
    XCTAssertNil(timeline.outputTime(for: t(12)))
  }

  func testOutputTime_afterResume_shiftsByPausedDuration() {
    var timeline = RecordingPauseTimeline()
    timeline.pause(at: t(10))
    timeline.resume(at: t(14))

    XCTAssertEqual(timeline.accumulatedOffset, t(4))
    XCTAssertEqual(timeline.outputTime(for: t(14.5)), t(10.5))
  }

  func testOutputTime_afterResume_dropsLateSamplesFromPausedSpan() {
    var timeline = RecordingPauseTimeline()
    timeline.pause(at: t(10))
    timeline.resume(at: t(14))

    // Captured during the pause but delivered after resume: mapping it would go backwards.
    XCTAssertNil(timeline.outputTime(for: t(12)))
  }

  func testOutputTime_accumulatesAcrossMultiplePauses() {
    var timeline = RecordingPauseTimeline()
    timeline.pause(at: t(10))
    timeline.resume(at: t(12))
    timeline.pause(at: t(20))
    timeline.resume(at: t(23))

    XCTAssertEqual(timeline.outputTime(for: t(24)), t(19))
  }

  func testResume_withoutPause_isIgnored() {
    var timeline = RecordingPauseTimeline()
    timeline.resume(at: t(5))
    XCTAssertEqual(timeline.accumulatedOffset, .zero)
    XCTAssertEqual(timeline.outputTime(for: t(1)), t(1))
  }

  func testResume_beforePausePoint_doesNotAddNegativeOffset() {
    var timeline = RecordingPauseTimeline()
    timeline.pause(at: t(10))
    timeline.resume(at: t(9))
    XCTAssertEqual(timeline.accumulatedOffset, .zero)
    XCTAssertFalse(timeline.isPaused)
    XCTAssertNil(timeline.outputTime(for: t(9.5)), "samples before the pause point stay cut")
    XCTAssertEqual(timeline.outputTime(for: t(10)), t(10))
  }

  func testAcceptVideoFrame_rejectsNonIncreasingTimestamps() {
    var timeline = RecordingPauseTimeline()
    XCTAssertEqual(timeline.acceptVideoFrame(at: t(1)), t(1))
    XCTAssertNil(timeline.acceptVideoFrame(at: t(1)))
    XCTAssertNil(timeline.acceptVideoFrame(at: t(0.5)))
    XCTAssertEqual(timeline.acceptVideoFrame(at: t(1.1)), t(1.1))
  }

  func testAcceptVideoFrame_acrossPause_staysStrictlyIncreasing() {
    var timeline = RecordingPauseTimeline()
    XCTAssertEqual(timeline.acceptVideoFrame(at: t(9.9)), t(9.9))
    timeline.pause(at: t(10))
    XCTAssertNil(timeline.acceptVideoFrame(at: t(11)))
    timeline.resume(at: t(15))
    XCTAssertNil(timeline.acceptVideoFrame(at: t(14.9)))

    let resumed = timeline.acceptVideoFrame(at: t(15))
    XCTAssertEqual(resumed, t(10))
    XCTAssertEqual(timeline.lastVideoTime, t(10))
  }

  func testOutputTime_rejectsInvalidTimestamp() {
    var timeline = RecordingPauseTimeline()
    XCTAssertNil(timeline.outputTime(for: .invalid))
    XCTAssertNil(timeline.acceptVideoFrame(at: .invalid))
  }
}
