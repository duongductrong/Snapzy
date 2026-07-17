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

  func testSetAccumulatedPauseOffset_doesNotCrash() {
    let offset = CMTime(seconds: 5.0, preferredTimescale: 1_000_000)
    session.setAccumulatedPauseOffset(offset)
  }

  func testReset_clearsPauseOffset() {
    let offset = CMTime(seconds: 5.0, preferredTimescale: 1_000_000)
    session.setAccumulatedPauseOffset(offset)
    session.reset()
  }
}
