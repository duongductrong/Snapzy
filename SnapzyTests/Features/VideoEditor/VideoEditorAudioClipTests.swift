//
//  VideoEditorAudioClipTests.swift
//  SnapzyTests
//

@testable import Snapzy
import XCTest

final class VideoEditorAudioClipTests: XCTestCase {
  func testAudioClip_moveAndTrimRespectBoundsAndMinDuration() {
    let clip = AudioTimelineClip(
      source: .primary,
      name: "Mic",
      timelineStart: 2.0,
      sourceDuration: 10.0,
      sourceStart: 1.0,
      sourceEnd: 6.0
    )

    let moved = clip.moved(to: -5.0)
    XCTAssertEqual(moved.timelineStart, 0.0, accuracy: 0.001)
    XCTAssertEqual(moved.duration, 5.0, accuracy: 0.001)

    let trimmedLead = clip.trimmedLeading(by: 1.5)
    XCTAssertEqual(trimmedLead.timelineStart, 3.5, accuracy: 0.001)
    XCTAssertEqual(trimmedLead.sourceStart, 2.5, accuracy: 0.001)
    XCTAssertEqual(trimmedLead.duration, 3.5, accuracy: 0.001)

    let trimmedTrail = clip.trimmedTrailing(by: -10.0)
    XCTAssertEqual(trimmedTrail.duration, AudioTimelineClip.minDuration, accuracy: 0.001)
  }

  func testAudioClip_splitProducesContiguousHalvesWithPreservedFades() throws {
    let clip = AudioTimelineClip(
      source: .primary,
      name: "Music",
      timelineStart: 1.0,
      sourceDuration: 10.0,
      sourceStart: 0.0,
      sourceEnd: 8.0,
      fadeIn: 0.5,
      fadeOut: 1.0
    )

    let (left, right) = try XCTUnwrap(clip.split(at: 4.0))
    XCTAssertEqual(left.timelineStart, 1.0, accuracy: 0.001)
    XCTAssertEqual(left.timelineEnd, 4.0, accuracy: 0.001)
    XCTAssertEqual(left.sourceStart, 0.0, accuracy: 0.001)
    XCTAssertEqual(left.sourceEnd, 3.0, accuracy: 0.001)
    XCTAssertEqual(left.fadeIn, 0.5, accuracy: 0.001)
    XCTAssertEqual(left.fadeOut, 0.0, accuracy: 0.001)

    XCTAssertEqual(right.timelineStart, 4.0, accuracy: 0.001)
    XCTAssertEqual(right.timelineEnd, 9.0, accuracy: 0.001)
    XCTAssertEqual(right.sourceStart, 3.0, accuracy: 0.001)
    XCTAssertEqual(right.sourceEnd, 8.0, accuracy: 0.001)
    XCTAssertEqual(right.fadeIn, 0.0, accuracy: 0.001)
    XCTAssertEqual(right.fadeOut, 1.0, accuracy: 0.001)

    // Splitting too close to an edge is rejected cleanly.
    XCTAssertNil(clip.split(at: 1.05))
  }
}
