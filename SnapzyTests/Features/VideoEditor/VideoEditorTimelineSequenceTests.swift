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
import XCTest
@testable import Snapzy

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

  // MARK: - SpeedSegment (unchanged model, still the authoring unit)

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

  func testLayout_retainsTrimmedSlotAndMarksOnlyItsActiveMiddle() {
    let clip = primary(sourceDuration: 20, 5, 15)
    let placement = try! XCTUnwrap(TimelineSequence.layout([
      TimelineClip(
        source: clip.source,
        sourceDuration: clip.sourceDuration,
        sourceStart: clip.sourceStart,
        sourceEnd: clip.sourceEnd,
        slotStart: 0,
        slotEnd: 20
      )
    ]).first)

    XCTAssertEqual(placement.start, 0, accuracy: eps)
    XCTAssertEqual(placement.end, 20, accuracy: eps)
    XCTAssertEqual(placement.activeStart, 5, accuracy: eps)
    XCTAssertEqual(placement.activeEnd, 15, accuracy: eps)
    XCTAssertFalse(placement.containsActive(2))
    XCTAssertTrue(placement.containsActive(10))
    XCTAssertFalse(placement.containsActive(18))
  }

  func testPlayableLayout_collapsesInactiveTrimSlot() {
    let clip = TimelineClip(
      source: .primary,
      sourceDuration: 20,
      sourceStart: 5,
      sourceEnd: 15,
      slotStart: 0,
      slotEnd: 20
    )
    let placement = try! XCTUnwrap(TimelineSequence.playableLayout([clip]).first)

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

  // MARK: - TimelineSequence.project

  func testProject_mapsSourceRangeOntoSequence() {
    let clips = [primary(sourceDuration: 10, 0, 4), primary(sourceDuration: 10, 6, 10)]
    let placements = TimelineSequence.layout(clips)

    // Source [7,9] lives in the second clip, which starts at sequence 4 (source 6).
    let pieces = TimelineSequence.project(sourceRange: 7...9, in: placements)
    XCTAssertEqual(pieces.count, 1)
    XCTAssertEqual(pieces[0].lowerBound, 5, accuracy: eps)
    XCTAssertEqual(pieces[0].upperBound, 7, accuracy: eps)
  }

  func testProject_keepsEffectAtItsStructuralSourcePositionAcrossTrim() {
    let clip = TimelineClip(
      source: .primary,
      sourceDuration: 20,
      sourceStart: 5,
      sourceEnd: 15,
      slotStart: 0,
      slotEnd: 20
    )
    let pieces = TimelineSequence.project(
      sourceRange: 9...11,
      in: TimelineSequence.layout([clip])
    )

    XCTAssertEqual(pieces.count, 1)
    XCTAssertEqual(pieces[0].lowerBound, 9, accuracy: eps)
    XCTAssertEqual(pieces[0].upperBound, 11, accuracy: eps)
  }

  func testProject_dropsMaterialThatWasDeleted() {
    let clips = [primary(sourceDuration: 10, 0, 4), primary(sourceDuration: 10, 6, 10)]
    let placements = TimelineSequence.layout(clips)
    // Source [4.5, 5.5] sits entirely inside the deleted region.
    XCTAssertTrue(TimelineSequence.project(sourceRange: 4.5...5.5, in: placements).isEmpty)
  }

  func testProject_splitsARangeThatSpansADeletedRegion() {
    let clips = [primary(sourceDuration: 10, 0, 4), primary(sourceDuration: 10, 6, 10)]
    let placements = TimelineSequence.layout(clips)

    // Source [3,7] survives as [3,4] and [6,7] → sequence [3,4] and [4,5], which meet
    // and therefore merge into one piece.
    let pieces = TimelineSequence.project(sourceRange: 3...7, in: placements)
    XCTAssertEqual(pieces.count, 1)
    XCTAssertEqual(pieces[0].lowerBound, 3, accuracy: eps)
    XCTAssertEqual(pieces[0].upperBound, 5, accuracy: eps)
  }

  func testProject_followsMaterialAfterReorder() {
    // Same two halves, order swapped: source [0,4] now plays second.
    let clips = [primary(sourceDuration: 10, 6, 10), primary(sourceDuration: 10, 0, 4)]
    let placements = TimelineSequence.layout(clips)

    let pieces = TimelineSequence.project(sourceRange: 0...4, in: placements)
    XCTAssertEqual(pieces.count, 1)
    XCTAssertEqual(pieces[0].lowerBound, 4, accuracy: eps)
    XCTAssertEqual(pieces[0].upperBound, 8, accuracy: eps)
  }

  func testProject_ignoresInsertedClips() {
    // Zoom/speed are authored against the recording, so an inserted clip contributes
    // no projection even though it occupies sequence time.
    let clips = [inserted("intro", sourceDuration: 5), primary(sourceDuration: 10)]
    let placements = TimelineSequence.layout(clips)

    let pieces = TimelineSequence.project(sourceRange: 0...2, in: placements)
    XCTAssertEqual(pieces.count, 1)
    XCTAssertEqual(pieces[0].lowerBound, 5, accuracy: eps) // pushed right by the intro
    XCTAssertEqual(pieces[0].upperBound, 7, accuracy: eps)
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

    XCTAssertEqual(m.toOutput(0), 0, accuracy: eps)    // before region
    XCTAssertEqual(m.toOutput(2), 2, accuracy: eps)    // region start unchanged
    XCTAssertEqual(m.toOutput(4), 3, accuracy: eps)    // midpoint: 2 + 2/2
    XCTAssertEqual(m.toOutput(6), 4, accuracy: eps)    // region end: 2 + 4/2
    XCTAssertEqual(m.toOutput(10), 8, accuracy: eps)   // after region: 4 + 4
  }

  func testSingle05xSegment_doublesSpanAndLengthensTotal() {
    let m = map([primary(sourceDuration: 10)], [SpeedSegment(startTime: 2, duration: 4, rate: 0.5)])
    XCTAssertEqual(m.outputDuration, 14, accuracy: eps)
    XCTAssertEqual(m.toOutput(2), 2, accuracy: eps)
    XCTAssertEqual(m.toOutput(6), 10, accuracy: eps)   // 2 + 4/0.5
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
    // Clip keeps source [5,15] → sequence [0,10]; segment at source [7,11] → seq [2,6].
    let clip = primary(sourceDuration: 20, 5, 15)
    let m = map([clip], [SpeedSegment(startTime: 7, duration: 4, rate: 2)])
    XCTAssertEqual(m.sequenceDuration, 10, accuracy: eps)
    XCTAssertEqual(m.outputDuration, 8, accuracy: eps)
    XCTAssertEqual(m.toOutput(2), 2, accuracy: eps)
    XCTAssertEqual(m.toOutput(6), 4, accuracy: eps)
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

  func testSpeedFollowsItsMaterialAcrossACut() {
    // Delete source [4,6]. A 2x segment over source [6,10] lands on sequence [4,8]
    // and still halves to 2 s, so total = 4 + 2 = 6 s.
    let clips = [primary(sourceDuration: 10, 0, 4), primary(sourceDuration: 10, 6, 10)]
    let m = map(clips, [SpeedSegment(startTime: 6, duration: 4, rate: 2)])
    XCTAssertEqual(m.sequenceDuration, 8, accuracy: eps)
    XCTAssertEqual(m.outputDuration, 6, accuracy: eps)
    XCTAssertEqual(m.rate(atSequence: 5), 2.0, accuracy: eps)
    XCTAssertEqual(m.rate(atSequence: 2), 1.0, accuracy: eps)
  }

  func testSpeedOverDeletedMaterial_hasNoEffect() {
    let clips = [primary(sourceDuration: 10, 0, 4), primary(sourceDuration: 10, 6, 10)]
    let m = map(clips, [SpeedSegment(startTime: 4.2, duration: 1.5, rate: 4)])
    XCTAssertTrue(m.isIdentity)
    XCTAssertEqual(m.outputDuration, 8, accuracy: eps)
  }

  func testInsertedClipPlaysAt1xEvenUnderASpeedSegment() {
    // The inserted clip occupies sequence [0,5]; the recording's speed segment at
    // source [0,4] projects to sequence [5,9] and must not touch the intro.
    let clips = [inserted("intro", sourceDuration: 5), primary(sourceDuration: 10)]
    let m = map(clips, [SpeedSegment(startTime: 0, duration: 4, rate: 2)])
    XCTAssertEqual(m.sequenceDuration, 15, accuracy: eps)
    XCTAssertEqual(m.rate(atSequence: 2), 1.0, accuracy: eps)   // inside the intro
    XCTAssertEqual(m.rate(atSequence: 6), 2.0, accuracy: eps)   // inside the 2x span
    XCTAssertEqual(m.outputDuration, 13, accuracy: eps)         // 15 - 4/2
  }

  func testOutputCMDuration_matchesOutputSeconds() {
    let m = map([primary(sourceDuration: 8)], [SpeedSegment(startTime: 0, duration: 4, rate: 2)])
    XCTAssertEqual(CMTimeGetSeconds(m.outputCMDuration()), m.outputDuration, accuracy: 0.01)
  }
}
