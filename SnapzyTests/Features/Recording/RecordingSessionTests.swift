//
//  RecordingSessionTests.swift
//  SnapzyTests
//
//  Unit tests for RecordingSession thread-safe state management.
//

import XCTest
import CoreMedia
@testable import Snapzy

final class RecordingSessionTests: XCTestCase {

  private var session: RecordingSession!

  override func setUp() {
    super.setUp()
    session = RecordingSession()
  }

  override func tearDown() {
    session = nil
    super.tearDown()
  }

  func testInitialState() {
    XCTAssertFalse(session.sessionStarted)
    XCTAssertFalse(session.isCapturing)
    XCTAssertNil(session.assetWriter)
    XCTAssertNil(session.videoInput)
    XCTAssertNil(session.audioInput)
    XCTAssertNil(session.microphoneInput)
  }

  func testCanWriteFrames_whenNotCapturing_returnsFalse() {
    XCTAssertFalse(session.canWriteFrames())
  }

  func testReset_clearsState() {
    session.isCapturing = true
    session.sessionStarted = true
    session.reset()
    XCTAssertFalse(session.isCapturing)
    XCTAssertFalse(session.sessionStarted)
  }

  func testVideoWriteStats_initiallyZero() {
    let stats = session.videoWriteStats()
    XCTAssertEqual(stats.receivedFrames, 0)
    XCTAssertEqual(stats.appendedFrames, 0)
    XCTAssertEqual(stats.droppedFramesDueToBackpressure, 0)
    XCTAssertEqual(stats.failedAppendFrames, 0)
    XCTAssertEqual(stats.microphoneSamplesReceived, 0)
    XCTAssertEqual(stats.microphoneSamplesAppended, 0)
  }

  func testSetOnFirstVideoFrame_doesNotCrash() {
    var called = false
    session.setOnFirstVideoFrame { called = true }
    // Cannot trigger without real sample buffer
  }

  func testConfigureExpectedVideoDimensions_doesNotCrash() {
    session.configureExpectedVideoDimensions(width: 1920, height: 1080)
  }

  func testResume_returnsAccumulatedPausedDuration() {
    session.pause(atHostTime: CMTime(seconds: 10, preferredTimescale: 600))
    let offset = session.resume(atHostTime: CMTime(seconds: 15, preferredTimescale: 600))
    XCTAssertEqual(offset.seconds, 5, accuracy: 0.001)
  }

  func testReset_clearsPauseOffset() {
    session.pause(atHostTime: CMTime(seconds: 10, preferredTimescale: 600))
    session.resume(atHostTime: CMTime(seconds: 15, preferredTimescale: 600))
    session.reset()
    session.pause(atHostTime: CMTime(seconds: 20, preferredTimescale: 600))
    let offset = session.resume(atHostTime: CMTime(seconds: 21, preferredTimescale: 600))
    XCTAssertEqual(offset.seconds, 1, accuracy: 0.001)
  }
}
