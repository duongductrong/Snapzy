//
//  VideoEditorCursorLayerTests.swift
//  SnapzyTests
//
//  Studio cursor layer (phase 2): resolver smoothing/idle/clicks, output → source time
//  mapping through cuts, reorder and speed, hotspot under scale, and click sound times.
//

import CoreImage
import XCTest
@testable import Snapzy

final class VideoEditorCursorLayerTests: XCTestCase {
  private func sample(_ t: TimeInterval, _ x: CGFloat, _ y: CGFloat) -> RecordedMouseSample {
    RecordedMouseSample(time: t, normalizedX: x, normalizedY: y, isInsideCapture: true)
  }

  // MARK: - Resolver

  func testZeroSmoothingReturnsRawSamples() {
    var settings = VideoEditorCursorSettings.default
    settings.smoothing = 0
    let samples = [sample(0, 0.1, 0.1), sample(0.1, 0.9, 0.2), sample(0.2, 0.3, 0.8)]
    let resolver = VideoEditorCursorResolver(samples: samples, capture: RecordingCursorCapture(), settings: settings)
    XCTAssertEqual(resolver.resolve(sourceTime: 0.1)?.position, CGPoint(x: 0.9, y: 0.2))
  }

  func testSmoothingReducesAJumpWithoutLag() {
    var settings = VideoEditorCursorSettings.default
    settings.smoothing = 1
    let samples = (0 ... 100).map { sample(Double($0) / 100, $0 == 50 ? 0.9 : 0.5, 0.5) }
    let resolver = VideoEditorCursorResolver(samples: samples, capture: RecordingCursorCapture(), settings: settings)
    let spike = resolver.resolve(sourceTime: 0.5)?.position.x ?? 0
    XCTAssertLessThan(spike, 0.6)
    XCTAssertEqual(resolver.resolve(sourceTime: 0.2)?.position.x ?? 0, 0.5, accuracy: 0.01)
  }

  func testHideWhenIdleFadesOutAfterDelayAndReturnsOnMovement() {
    var settings = VideoEditorCursorSettings.default
    settings.smoothing = 0
    settings.hideWhenIdle = true
    settings.idleDelay = 1
    let samples = [sample(0, 0.1, 0.1), sample(0.5, 0.2, 0.2), sample(4, 0.2, 0.2), sample(4.1, 0.6, 0.6)]
    let resolver = VideoEditorCursorResolver(samples: samples, capture: RecordingCursorCapture(), settings: settings)
    XCTAssertEqual(resolver.idleOpacity(at: 1.4), 1)
    XCTAssertEqual(resolver.idleOpacity(at: 1.6), 0.5, accuracy: 1e-6)
    XCTAssertNil(resolver.resolve(sourceTime: 3))
    XCTAssertEqual(resolver.resolve(sourceTime: 4.1)?.opacity, 1)
  }

  func testRippleRunsAfterMouseDownAndRingWhileHeld() {
    var settings = VideoEditorCursorSettings.default
    settings.smoothing = 0
    let capture = RecordingCursorCapture(clicks: [
      RecordedClick(time: 1, button: .left, phase: .down, normalizedX: 0.5, normalizedY: 0.5),
      RecordedClick(time: 2, button: .left, phase: .up, normalizedX: 0.5, normalizedY: 0.5),
    ])
    let samples = [sample(0, 0.5, 0.5), sample(3, 0.5, 0.5)]
    let ripple = VideoEditorCursorResolver(samples: samples, capture: capture, settings: settings)
    XCTAssertEqual(ripple.resolve(sourceTime: 1.1)?.pulses.count, 1)
    XCTAssertEqual(ripple.resolve(sourceTime: 1.6)?.pulses.count, 0)

    settings.clickEffect = .ring
    let ring = VideoEditorCursorResolver(samples: samples, capture: capture, settings: settings)
    XCTAssertEqual(ring.resolve(sourceTime: 1.5)?.held.count, 1)
    XCTAssertEqual(ring.resolve(sourceTime: 2.5)?.held.count, 0)
  }

  /// Changing settings on an existing resolver must resolve exactly like a fresh one.
  func testUpdatingSettingsMatchesFreshResolver() {
    let capture = RecordingCursorCapture(clicks: [
      RecordedClick(time: 1, button: .left, phase: .down, normalizedX: 0.4, normalizedY: 0.4),
      RecordedClick(time: 1.3, button: .left, phase: .up, normalizedX: 0.4, normalizedY: 0.4),
    ])
    let samples = (0 ..< 200).map { index in
      let t = Double(index) * 0.05
      return sample(t, 0.5 + 0.3 * CGFloat(sin(t)), index > 120 ? 0.7 : 0.3 + CGFloat(index) * 0.002)
    }
    var settings = VideoEditorCursorSettings.default
    let base = VideoEditorCursorResolver(samples: samples, capture: capture, settings: settings)
    let variants: [(inout VideoEditorCursorSettings) -> Void] = [
      { $0.scale = 2 },
      { $0.smoothing = 0.9 },
      { $0.smoothing = 0 },
      { $0.hideWhenIdle = true; $0.idleDelay = 0.6 },
      { $0.clickEffect = .ring },
      { $0.isVisible = false },
    ]
    for change in variants {
      change(&settings)
      let updated = base.updating(settings: settings)
      let fresh = VideoEditorCursorResolver(samples: samples, capture: capture, settings: settings)
      for step in 0 ..< 220 {
        let time = Double(step) * 0.047
        XCTAssertEqual(updated.resolve(sourceTime: time), fresh.resolve(sourceTime: time))
      }
    }
  }

  // MARK: - Time mapping

  func testMappingFollowsReorderedClipsAndSkipsInsertedFiles() {
    let late = TimelineClip(source: .primary, sourceDuration: 12, sourceStart: 8, sourceEnd: 12)
    let other = TimelineClip(source: .file(url: URL(fileURLWithPath: "/tmp/x.mov")), sourceDuration: 2)
    let early = TimelineClip(source: .primary, sourceDuration: 12, sourceStart: 0, sourceEnd: 6)
    let clips = [late, other, early]
    let mapping = VideoEditorSourceTimeMapping(
      sequenceMap: TimelineSequenceMap(clips: clips, speedSegments: []),
      playbackPlacements: TimelineSequence.playableLayout(clips)
    )
    XCTAssertEqual(mapping.sourceTime(output: 1) ?? -1, 9, accuracy: 1e-6)
    XCTAssertNil(mapping.sourceTime(output: 5))
    XCTAssertEqual(mapping.sourceTime(output: 8) ?? -1, 2, accuracy: 1e-6)
  }

  func testMappingAndClickTimesFollowSpeed() {
    let clip = TimelineClip(source: .primary, sourceDuration: 12)
    let speed = SpeedSegment(startTime: 0, duration: 4, rate: 2)
    let map = TimelineSequenceMap(clips: [clip], speedSegments: [speed])
    let placements = TimelineSequence.playableLayout([clip])
    let mapping = VideoEditorSourceTimeMapping(sequenceMap: map, playbackPlacements: placements)
    XCTAssertEqual(mapping.sourceTime(output: 4) ?? -1, 6, accuracy: 1e-6)
    XCTAssertEqual(mapping.sourceTime(output: 1) ?? -1, 2, accuracy: 1e-6)

    let times = VideoEditorClickSound.outputTimes(
      clickSourceTimes: [2, 2.05, 6], playbackPlacements: placements, sequenceMap: map
    )
    // 2 and 2.05 land 25 ms apart at 2× and merge.
    XCTAssertEqual(times.count, 2)
    XCTAssertEqual(times[0], 1, accuracy: 1e-6)
    XCTAssertEqual(times[1], 4, accuracy: 1e-6)
  }

  func testPreviewClickTimesDropTrimmedOutClicks() {
    let clip = TimelineClip(source: .primary, sourceDuration: 10, sourceStart: 2, sourceEnd: 8)
    let times = VideoEditorClickSoundPlayer.sequenceTimes(
      clickSourceTimes: [1, 3, 9], placements: TimelineSequence.layout([clip])
    )
    XCTAssertEqual(times.count, 1)
  }

  // MARK: - Render

  func testHotspotStaysPutWhenScaled() {
    var settings = VideoEditorCursorSettings.recorded(clickEffect: .none, clickColor: .defaultClick)
    settings.scale = 2
    let layer = RecordingStudioCursorCaptureTests.whiteCursorLayer(
      samples: [sample(0, 0.5, 0.5)],
      captureSize: CGSize(width: 100, height: 100),
      settings: settings,
      hotspot: CGPoint(x: 5, y: 5)
    )
    let base = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
    let image = layer.composite(onto: base, context: VideoEditorStudioLayerContext(
      outputTime: 0, extent: base.extent, auxiliaryFrames: [:]
    ))
    // 2 px/pt × scale 2 → 40×40 px sprite, hotspot (5,5) pt → 20 px from its top-left,
    // so the sprite is centered on (100, 100) and spans 80...120.
    XCTAssertGreaterThan(brightness(of: image, at: CGPoint(x: 82, y: 82)), 0.9)
    XCTAssertGreaterThan(brightness(of: image, at: CGPoint(x: 118, y: 118)), 0.9)
    XCTAssertLessThan(brightness(of: image, at: CGPoint(x: 76, y: 100)), 0.1)
    XCTAssertLessThan(brightness(of: image, at: CGPoint(x: 124, y: 100)), 0.1)
  }

  func testHiddenCursorLeavesFrameUntouched() {
    var settings = VideoEditorCursorSettings.default
    settings.isVisible = false
    let layer = RecordingStudioCursorCaptureTests.whiteCursorLayer(
      samples: [sample(0, 0.5, 0.5)], captureSize: CGSize(width: 100, height: 100), settings: settings
    )
    XCTAssertFalse(layer.isActive)
  }

  private func brightness(of image: CIImage, at point: CGPoint) -> CGFloat {
    var pixel = [UInt8](repeating: 0, count: 4)
    CIContext().render(image, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: point.x, y: point.y, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
    return CGFloat(pixel[0]) / 255
  }
}
