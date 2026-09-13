//
//  VideoEditorTimelineSequenceTests.swift
//  SnapzyTests
//
//  Unit tests for the clip-sequence timeline: `TimelineClip` clamping,
//  `TimelineSequence` layout/projection, and `TimelineSequenceMap` sequence↔output
//  time math. Replaces the SpeedTimeMap suite, whose map was folded into
//  TimelineSequenceMap when the editor moved to a clip sequence.
//

import CoreMedia
@testable import Snapzy
import XCTest

final class VideoEditorTimelineSequenceTests: XCTestCase {
  private let eps = 0.0005

  // MARK: - Helpers

  private func primary(
    sourceDuration: TimeInterval,
    _ start: TimeInterval = 0,
    _ end: TimeInterval? = nil
  ) -> TimelineClip {
    TimelineClip(
      source: .primary,
      sourceDuration: sourceDuration,
      sourceStart: start,
      sourceEnd: end ?? sourceDuration
    )
  }

  private func inserted(
    _ name: String,
    sourceDuration: TimeInterval,
    _ start: TimeInterval = 0,
    _ end: TimeInterval? = nil
  ) -> TimelineClip {
    TimelineClip(
      source: .file(url: URL(fileURLWithPath: "/tmp/\(name).mov")),
      sourceDuration: sourceDuration,
      sourceStart: start,
      sourceEnd: end ?? sourceDuration
    )
  }

  private func map(
    _ clips: [TimelineClip],
    _ speeds: [SpeedSegment] = []
  ) -> TimelineSequenceMap {
    TimelineSequenceMap(clips: clips, speedSegments: speeds)
  }

  // MARK: - SpeedSegment (structural timeline authoring unit)

  func testSpeedSegment_clampsRateToSupportedRange() {
    XCTAssertEqual(SpeedSegment(startTime: 0, rate: 100).rate, SpeedSegment.maxRate, accuracy: eps)
    XCTAssertEqual(SpeedSegment(startTime: 0, rate: 0.01).rate, SpeedSegment.minRate, accuracy: eps)
    XCTAssertEqual(SpeedSegment(startTime: 0, rate: 2).rate, 2.0, accuracy: eps)
  }

  func testSpeedSegment_clampsStartAndMinDuration() {
    let seg = SpeedSegment(startTime: -5, duration: 0.01, rate: 2)
    XCTAssertEqual(seg.startTime, 0, accuracy: eps)
    XCTAssertEqual(seg.duration, SpeedSegment.minDuration, accuracy: eps)
  }

  func testSpeedSegment_overlapDetection() {
    let a = SpeedSegment(startTime: 0, duration: 4, rate: 2)
    let b = SpeedSegment(startTime: 3, duration: 4, rate: 2)
    let c = SpeedSegment(startTime: 4, duration: 2, rate: 2)
    XCTAssertTrue(a.overlaps(with: b))
    XCTAssertFalse(a.overlaps(with: c)) // touching edges do not overlap
  }

  func testSpeedSegment_formattedRate() {
    XCTAssertEqual(SpeedSegment(startTime: 0, rate: 2).formattedRate, "2x")
    XCTAssertEqual(SpeedSegment(startTime: 0, rate: 0.5).formattedRate, "0.5x")
  }

  // MARK: - TimelineClip

  func testClip_keepsWholeAssetByDefault() {
    let clip = primary(sourceDuration: 10)
    XCTAssertEqual(clip.sourceStart, 0, accuracy: eps)
    XCTAssertEqual(clip.sourceEnd, 10, accuracy: eps)
    XCTAssertEqual(clip.duration, 10, accuracy: eps)
    XCTAssertTrue(clip.isPrimary)
  }

  func testClip_clampsOutPointToSourceDuration() {
    let clip = TimelineClip(source: .primary, sourceDuration: 10, sourceStart: 2, sourceEnd: 99)
    XCTAssertEqual(clip.sourceEnd, 10, accuracy: eps)
  }

  func testClip_enforcesMinimumDurationByExtendingOutPoint() {
    let clip = TimelineClip(source: .primary, sourceDuration: 10, sourceStart: 4, sourceEnd: 4.01)
    XCTAssertEqual(clip.duration, TimelineClip.minDuration, accuracy: eps)
    XCTAssertEqual(clip.sourceStart, 4, accuracy: eps)
  }

  func testClip_pullsInPointBackWhenThereIsNoRoomAfterIt() {
    // In-point sits at the very end of the asset: the only way to reach minDuration
    // is to move the in-point earlier.
    let clip = TimelineClip(source: .primary, sourceDuration: 10, sourceStart: 10, sourceEnd: 10)
    XCTAssertEqual(clip.sourceEnd, 10, accuracy: eps)
    XCTAssertEqual(clip.sourceStart, 10 - TimelineClip.minDuration, accuracy: eps)
  }

  func testClip_retainsFullSourceDurationForNonDestructiveTrim() {
    // The whole point of keeping sourceDuration: a trimmed clip can be re-extended.
    let trimmed = TimelineClip(source: .primary, sourceDuration: 10, sourceStart: 4, sourceEnd: 6)
    XCTAssertEqual(trimmed.duration, 2, accuracy: eps)
    XCTAssertEqual(trimmed.sourceDuration, 10, accuracy: eps)

    let reExtended = TimelineClip(
      id: trimmed.id,
      source: trimmed.source,
      sourceDuration: trimmed.sourceDuration,
      sourceStart: 0,
      sourceEnd: 10
    )
    XCTAssertEqual(reExtended.duration, 10, accuracy: eps)
  }

  func testClip_keepsStructuralSlotWhenTrimmed() {
    let trimmed = TimelineClip(
      source: .primary,
      sourceDuration: 20,
      sourceStart: 5,
      sourceEnd: 15,
      slotStart: 0,
      slotEnd: 20
    )

    XCTAssertEqual(trimmed.duration, 10, accuracy: eps)
    XCTAssertEqual(trimmed.slotDuration, 20, accuracy: eps)
    XCTAssertEqual(trimmed.slotRange.lowerBound, 0, accuracy: eps)
    XCTAssertEqual(trimmed.slotRange.upperBound, 20, accuracy: eps)
  }

  // MARK: - TimelineSequence.layout

  func testLayout_placesClipsShoulderToShoulder() {
    let clips = [
      primary(sourceDuration: 10, 0, 4),
      inserted("intro", sourceDuration: 5, 0, 3),
      primary(sourceDuration: 10, 7, 10),
    ]
    let placements = TimelineSequence.layout(clips)

    XCTAssertEqual(placements.count, 3)
    XCTAssertEqual(placements[0].start, 0, accuracy: eps)
    XCTAssertEqual(placements[0].end, 4, accuracy: eps)
    XCTAssertEqual(placements[1].start, 4, accuracy: eps)
    XCTAssertEqual(placements[1].end, 7, accuracy: eps)
    XCTAssertEqual(placements[2].start, 7, accuracy: eps)
    XCTAssertEqual(placements[2].end, 10, accuracy: eps)
    XCTAssertEqual(TimelineSequence.duration(clips), 10, accuracy: eps)
  }

  func testLayout_indicesPointBackAtTheClipsArray() {
    let clips = [primary(sourceDuration: 10, 0, 4), primary(sourceDuration: 10, 6, 10)]
    let placements = TimelineSequence.layout(clips)
    XCTAssertEqual(placements[0].index, 0)
    XCTAssertEqual(placements[1].index, 1)
  }

  func testLayout_retainsTrimmedSlotAndMarksOnlyItsActiveMiddle() throws {
    let clip = primary(sourceDuration: 20, 5, 15)
    let placement = try XCTUnwrap(TimelineSequence.layout([
      TimelineClip(
        source: clip.source,
        sourceDuration: clip.sourceDuration,
        sourceStart: clip.sourceStart,
        sourceEnd: clip.sourceEnd,
        slotStart: 0,
        slotEnd: 20
      ),
    ]).first)

    XCTAssertEqual(placement.start, 0, accuracy: eps)
    XCTAssertEqual(placement.end, 20, accuracy: eps)
    XCTAssertEqual(placement.activeStart, 5, accuracy: eps)
    XCTAssertEqual(placement.activeEnd, 15, accuracy: eps)
    XCTAssertFalse(placement.containsActive(2))
    XCTAssertTrue(placement.containsActive(10))
    XCTAssertFalse(placement.containsActive(18))
  }

  func testPlayableLayout_collapsesInactiveTrimSlot() throws {
    let clip = TimelineClip(
      source: .primary,
      sourceDuration: 20,
      sourceStart: 5,
      sourceEnd: 15,
      slotStart: 0,
      slotEnd: 20
    )
    let placement = try XCTUnwrap(TimelineSequence.playableLayout([clip]).first)

    XCTAssertEqual(placement.start, 0, accuracy: eps)
    XCTAssertEqual(placement.end, 10, accuracy: eps)
    XCTAssertEqual(placement.sourceTime(at: 0), 5, accuracy: eps)
    XCTAssertEqual(placement.sourceTime(at: 10), 15, accuracy: eps)
  }

  func testPlacement_mapsSequenceTimeToSourceTimeAcrossACut() {
    // Delete [4,6] from a 10 s recording: sequence 5 s should show source 7 s.
    let clips = [primary(sourceDuration: 10, 0, 4), primary(sourceDuration: 10, 6, 10)]
    let placements = TimelineSequence.layout(clips)

    let hit = TimelineSequence.placement(at: 5, in: placements)
    XCTAssertNotNil(hit)
    XCTAssertEqual(hit?.sourceTime(at: 5) ?? -1, 7, accuracy: eps)
  }

  func testPlacement_sourceAndSequenceRoundTrip() {
    let clips = [primary(sourceDuration: 10, 0, 4), primary(sourceDuration: 10, 6, 10)]
    let placements = TimelineSequence.layout(clips)

    for t in stride(from: 0.0, to: 8.0, by: 0.31) {
      guard let hit = TimelineSequence.placement(at: t, in: placements) else {
        return XCTFail("no placement at \(t)")
      }
      XCTAssertEqual(hit.sequenceTime(atSource: hit.sourceTime(at: t)), t, accuracy: 0.01)
    }
  }

  func testPlacement_atExactSequenceEndResolvesToLastClip() {
    let clips = [primary(sourceDuration: 10, 0, 4), primary(sourceDuration: 10, 6, 10)]
    let placements = TimelineSequence.layout(clips)
    XCTAssertEqual(TimelineSequence.placement(at: 8, in: placements)?.index, 1)
  }

  // MARK: - Structural effect projection

  func testProjectTimelineRange_staysAtAuthoredPositionAfterReorder() {
    let first = primary(sourceDuration: 10, 0, 5)
    let second = primary(sourceDuration: 10, 5, 10)
    let timeline = TimelineSequence.layout([second, first])
    let playable = TimelineSequence.playableLayout([second, first])

    let pieces = TimelineSequence.project(
      timelineRange: 1 ... 3,
      from: timeline,
      to: playable
    )

    XCTAssertEqual(pieces, [1 ... 3])
  }

  func testProjectTimelineRange_canTargetInsertedClip() {
    let clips = [
      primary(sourceDuration: 10, 0, 5),
      inserted("intro", sourceDuration: 2),
      primary(sourceDuration: 10, 5, 10),
    ]
    let timeline = TimelineSequence.layout(clips)
    let playable = TimelineSequence.playableLayout(clips)

    let pieces = TimelineSequence.project(
      timelineRange: 5.25 ... 6.75,
      from: timeline,
      to: playable
    )

    XCTAssertEqual(pieces, [5.25 ... 6.75])
  }

  func testProjectTimelineRange_collapsesTrimmedSlotsOnlyAtPlayback() {
    let clip = TimelineClip(
      source: .primary,
      sourceDuration: 20,
      sourceStart: 5,
      sourceEnd: 15,
      slotStart: 0,
      slotEnd: 20
    )
    let timeline = TimelineSequence.layout([clip])
    let playable = TimelineSequence.playableLayout([clip])

    let pieces = TimelineSequence.project(
      timelineRange: 3 ... 8,
      from: timeline,
      to: playable
    )

    XCTAssertEqual(pieces, [0 ... 3])
  }

  // MARK: - TimelineSequenceMap identity

  func testIdentityMap_whenNoSpeedSegments() {
    let m = map([primary(sourceDuration: 10)])
    XCTAssertTrue(m.isIdentity)
    XCTAssertEqual(m.outputDuration, 10, accuracy: eps)
    XCTAssertEqual(m.sequenceDuration, 10, accuracy: eps)
    for t in stride(from: 0.0, through: 10.0, by: 1.0) {
      XCTAssertEqual(m.toOutput(t), t, accuracy: eps)
      XCTAssertEqual(m.toSequence(t), t, accuracy: eps)
    }
  }

  func testIdentityMap_whenOnly1xSegment() {
    let m = map([primary(sourceDuration: 10)], [SpeedSegment(startTime: 2, duration: 3, rate: 1.0)])
    XCTAssertTrue(m.isIdentity)
    XCTAssertEqual(m.outputDuration, 10, accuracy: eps)
  }

  func testIdentityMap_ignoresDisabledSegment() {
    let seg = SpeedSegment(startTime: 2, duration: 3, rate: 4, isEnabled: false)
    let m = map([primary(sourceDuration: 10)], [seg])
    XCTAssertTrue(m.isIdentity)
    XCTAssertEqual(m.outputDuration, 10, accuracy: eps)
  }

  // MARK: - Single segment

  func testSingle2xSegment_halvesSpanAndShortensTotal() {
    // 10 s clip; 2x over [2,6] (4s → 2s). Total = 8s.
    let m = map([primary(sourceDuration: 10)], [SpeedSegment(startTime: 2, duration: 4, rate: 2)])
    XCTAssertEqual(m.outputDuration, 8, accuracy: eps)

    XCTAssertEqual(m.toOutput(0), 0, accuracy: eps) // before region
    XCTAssertEqual(m.toOutput(2), 2, accuracy: eps) // region start unchanged
    XCTAssertEqual(m.toOutput(4), 3, accuracy: eps) // midpoint: 2 + 2/2
    XCTAssertEqual(m.toOutput(6), 4, accuracy: eps) // region end: 2 + 4/2
    XCTAssertEqual(m.toOutput(10), 8, accuracy: eps) // after region: 4 + 4
  }

  func testSingle05xSegment_doublesSpanAndLengthensTotal() {
    let m = map([primary(sourceDuration: 10)], [SpeedSegment(startTime: 2, duration: 4, rate: 0.5)])
    XCTAssertEqual(m.outputDuration, 14, accuracy: eps)
    XCTAssertEqual(m.toOutput(2), 2, accuracy: eps)
    XCTAssertEqual(m.toOutput(6), 10, accuracy: eps) // 2 + 4/0.5
    XCTAssertEqual(m.toOutput(10), 14, accuracy: eps)
  }

  // MARK: - Multi-segment non-uniform

  func testMultiSegment_nonUniformWithGap() {
    // 12 s clip; 4x over [0,4] (→1s), 1x gap [4,8] (→4s), 0.5x over [8,12] (→8s) = 13s.
    let segs = [
      SpeedSegment(startTime: 0, duration: 4, rate: 4),
      SpeedSegment(startTime: 8, duration: 4, rate: 0.5),
    ]
    let m = map([primary(sourceDuration: 12)], segs)
    XCTAssertEqual(m.outputDuration, 13, accuracy: eps)
    XCTAssertEqual(m.toOutput(4), 1, accuracy: eps)
    XCTAssertEqual(m.toOutput(8), 5, accuracy: eps)
    XCTAssertEqual(m.toOutput(12), 13, accuracy: eps)
  }

  func testSpansTileWholeSequenceContiguously() {
    let segs = [
      SpeedSegment(startTime: 1, duration: 2, rate: 2),
      SpeedSegment(startTime: 6, duration: 2, rate: 0.5),
    ]
    let m = map([primary(sourceDuration: 10)], segs)
    XCTAssertEqual(m.spans.first?.seqStart ?? -1, 0, accuracy: eps)
    var cursor = 0.0
    for span in m.spans {
      XCTAssertEqual(span.seqStart, cursor, accuracy: eps)
      cursor = span.seqEnd
    }
    XCTAssertEqual(cursor, 10, accuracy: eps)
  }

  // MARK: - Inverse round-trips

  func testInverseOfForward_isIdentity() {
    let segs = [
      SpeedSegment(startTime: 1, duration: 3, rate: 4),
      SpeedSegment(startTime: 7, duration: 2, rate: 0.25),
    ]
    let m = map([primary(sourceDuration: 10)], segs)
    for t in stride(from: 0.0, through: 10.0, by: 0.37) {
      XCTAssertEqual(m.toSequence(m.toOutput(t)), t, accuracy: 0.01)
    }
  }

  func testForwardOfInverse_isIdentity() {
    let m = map([primary(sourceDuration: 10)], [SpeedSegment(startTime: 2, duration: 4, rate: 8)])
    for s in stride(from: 0.0, through: m.outputDuration, by: 0.21) {
      XCTAssertEqual(m.toOutput(m.toSequence(s)), s, accuracy: 0.01)
    }
  }

  // MARK: - rate(atSequence:)

  func testRateAtSequence() {
    let segs = [
      SpeedSegment(startTime: 2, duration: 2, rate: 4),
      SpeedSegment(startTime: 6, duration: 2, rate: 0.5),
    ]
    let m = map([primary(sourceDuration: 10)], segs)
    XCTAssertEqual(m.rate(atSequence: 0), 1.0, accuracy: eps)
    XCTAssertEqual(m.rate(atSequence: 3), 4.0, accuracy: eps)
    XCTAssertEqual(m.rate(atSequence: 6.5), 0.5, accuracy: eps)
    XCTAssertEqual(m.rate(atSequence: 9), 1.0, accuracy: eps)
  }

  // MARK: - Trim window clipping & offset

  func testTrimmedClip_offsetsSpeedSegmentsOntoSequenceCoordinates() {
    // Structural slot [0,10] keeps its own coordinate; segment [7,11] projects to
    // the active/playable source portion [7,10] → playable [7,10].
    let clip = primary(sourceDuration: 20, 5, 15)
    let m = map([clip], [SpeedSegment(startTime: 7, duration: 4, rate: 2)])
    XCTAssertEqual(m.sequenceDuration, 10, accuracy: eps)
    XCTAssertEqual(m.outputDuration, 8.5, accuracy: eps)
    XCTAssertEqual(m.toOutput(6), 6, accuracy: eps)
    XCTAssertEqual(m.toOutput(10), 8.5, accuracy: eps)
  }

  func testTrimmedSlot_speedMapUsesOnlyActiveMaterial() {
    let clip = TimelineClip(
      source: .primary,
      sourceDuration: 20,
      sourceStart: 5,
      sourceEnd: 15,
      slotStart: 0,
      slotEnd: 20
    )
    let m = map([clip], [SpeedSegment(startTime: 9, duration: 2, rate: 2)])

    XCTAssertEqual(m.sequenceDuration, 10, accuracy: eps)
    XCTAssertEqual(m.outputDuration, 9, accuracy: eps)
    XCTAssertEqual(m.toOutput(4), 4, accuracy: eps)
    XCTAssertEqual(m.toOutput(6), 5, accuracy: eps)
  }

  func testSegmentExtendingPastClip_isClippedToTheSequence() {
    // Clip [0,8]; segment source [6,16] rate 2 clips to [6,8] → 1s. Total 7s.
    let clip = primary(sourceDuration: 20, 0, 8)
    let m = map([clip], [SpeedSegment(startTime: 6, duration: 10, rate: 2)])
    XCTAssertEqual(m.outputDuration, 7, accuracy: eps)
  }

  func testSpeedUsesStructuralPositionAfterACut() {
    // The effect remains at structural [6,10]. The cut sequence is [0,4] + [4,8],
    // so only its final two seconds are inside the structural timeline and rate-scaled.
    let clips = [primary(sourceDuration: 10, 0, 4), primary(sourceDuration: 10, 6, 10)]
    let m = map(clips, [SpeedSegment(startTime: 6, duration: 4, rate: 2)])
    XCTAssertEqual(m.sequenceDuration, 8, accuracy: eps)
    XCTAssertEqual(m.outputDuration, 7, accuracy: eps)
    XCTAssertEqual(m.rate(atSequence: 5), 1.0, accuracy: eps)
    XCTAssertEqual(m.rate(atSequence: 6), 2.0, accuracy: eps)
  }

  func testSpeedSegmentUsesIndependentTimelineAfterClipReorder() {
    let first = primary(sourceDuration: 10, 0, 5)
    let second = primary(sourceDuration: 10, 5, 10)
    let speed = SpeedSegment(startTime: 1, duration: 2, rate: 2)

    let m = map([second, first], [speed])

    XCTAssertEqual(m.rate(atSequence: 1), 2.0, accuracy: eps)
    XCTAssertEqual(m.rate(atSequence: 6), 1.0, accuracy: eps)
  }

  func testSpeedUsesTimelinePositionAfterDeletedSourceMaterial() {
    let clips = [primary(sourceDuration: 10, 0, 4), primary(sourceDuration: 10, 6, 10)]
    let m = map(clips, [SpeedSegment(startTime: 4.2, duration: 1.5, rate: 4)])
    XCTAssertFalse(m.isIdentity)
    XCTAssertEqual(m.rate(atSequence: 4.5), 4.0, accuracy: eps)
    XCTAssertEqual(m.outputDuration, 6.875, accuracy: eps)
  }

  func testInsertedClipCanBeSpeedControlledOnIndependentTimeline() {
    // The inserted clip occupies structural [0,5]. A segment at structural [0,4]
    // intentionally controls that inserted material instead of following primary
    // source time to the right.
    let clips = [inserted("intro", sourceDuration: 5), primary(sourceDuration: 10)]
    let m = map(clips, [SpeedSegment(startTime: 0, duration: 4, rate: 2)])
    XCTAssertEqual(m.sequenceDuration, 15, accuracy: eps)
    XCTAssertEqual(m.rate(atSequence: 2), 2.0, accuracy: eps) // inside the intro
    XCTAssertEqual(m.rate(atSequence: 6), 1.0, accuracy: eps) // after the span
    XCTAssertEqual(m.outputDuration, 13, accuracy: eps) // 15 - 4/2
  }

  func testOutputCMDuration_matchesOutputSeconds() {
    let m = map([primary(sourceDuration: 8)], [SpeedSegment(startTime: 0, duration: 4, rate: 2)])
    XCTAssertEqual(CMTimeGetSeconds(m.outputCMDuration()), m.outputDuration, accuracy: 0.01)
  }

  func testSpeedMap_afterReorder_keepsAuthoredTimelineSpan() {
    // [A2][A1] does not move a structural [3.5,6] effect. The span crosses the
    // clip seam continuously and remains exactly 2.5 seconds long.
    let a1 = primary(sourceDuration: 10, 0, 5)
    let a2 = primary(sourceDuration: 10, 5, 10)
    let m = map([a2, a1], [SpeedSegment(startTime: 3.5, duration: 2.5, rate: 2)])

    XCTAssertEqual(m.rate(atSequence: 1), 1.0, accuracy: eps) // inside A2
    XCTAssertEqual(m.rate(atSequence: 5), 2.0, accuracy: eps) // across the seam
    XCTAssertEqual(m.rate(atSequence: 6), 1.0, accuracy: eps) // after the span
    // Output: 3.5 s at 1x + 1.25 s at 2x + 4 s at 1x = 8.75 s.
    XCTAssertEqual(m.outputDuration, 8.75, accuracy: eps)
  }
}
