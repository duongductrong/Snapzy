//
//  VideoEditorCaptionLayerTests.swift
//  SnapzyTests
//
//  Caption resolver, output-time cues for SRT/VTT, shared CoreText layout and the
//  burn-in layer.
//

import CoreImage
import XCTest
@testable import Snapzy

final class VideoEditorCaptionLayerTests: XCTestCase {
  private func segment(_ start: TimeInterval, _ end: TimeInterval, _ text: String) -> CaptionSegment {
    CaptionSegment(sourceRange: start ... end, text: text)
  }

  // MARK: - Resolver

  func testResolverFindsCaptionAndHidesWhenDisabledOrFast() {
    var captions = VideoEditorCaptions(segments: [segment(1, 3, "Hello"), segment(4, 6, "World")])
    var resolver = VideoEditorCaptionResolver(captions: captions)
    XCTAssertEqual(resolver.segment(atSource: 2)?.text, "Hello")
    XCTAssertNil(resolver.segment(atSource: 3.5))
    XCTAssertEqual(resolver.segment(atSource: 5, rate: 2)?.text, "World")
    XCTAssertNil(resolver.segment(atSource: 5, rate: 4))

    captions.settings.hideDuringFastSpeed = false
    resolver = VideoEditorCaptionResolver(captions: captions)
    XCTAssertEqual(resolver.segment(atSource: 5, rate: 4)?.text, "World")

    captions.settings.isEnabled = false
    resolver = VideoEditorCaptionResolver(captions: captions)
    XCTAssertNil(resolver.segment(atSource: 2))
  }

  // MARK: - Output cues

  func testCuesFollowCutsWithoutRegenerating() {
    // Keep 0–4 and 6–10 of a 10 s recording: a caption in the cut is dropped, later ones shift by 2 s.
    let clips = [
      TimelineClip(source: .primary, sourceDuration: 10, sourceStart: 0, sourceEnd: 4),
      TimelineClip(source: .primary, sourceDuration: 10, sourceStart: 6, sourceEnd: 10),
    ]
    let cues = VideoEditorCaptionResolver.outputCues(
      segments: [segment(1, 2, "a"), segment(4.5, 5.5, "cut"), segment(7, 8, "b"), segment(3, 7, "split")],
      playbackPlacements: TimelineSequence.playableLayout(clips),
      sequenceMap: TimelineSequenceMap(clips: clips, speedSegments: [])
    )
    XCTAssertEqual(cues.map(\.text), ["a", "split", "b"])
    XCTAssertEqual(cues[1].start, 3, accuracy: 0.001)
    // "split" spans the cut: 3–4 then 6–7, which become 3–4 and 4–5 back to back → one cue.
    XCTAssertEqual(cues[1].end, 5, accuracy: 0.001)
    XCTAssertEqual(cues[2].start, 5, accuracy: 0.001)
    XCTAssertEqual(cues[2].end, 6, accuracy: 0.001)
  }

  func testCuesShrinkUnderSpeed() {
    let clips = [TimelineClip(source: .primary, sourceDuration: 10)]
    let speed = SpeedSegment(startTime: 2, duration: 4, rate: 2)
    let cues = VideoEditorCaptionResolver.outputCues(
      segments: [segment(2, 6, "fast"), segment(7, 8, "after")],
      playbackPlacements: TimelineSequence.playableLayout(clips),
      sequenceMap: TimelineSequenceMap(clips: clips, speedSegments: [speed])
    )
    XCTAssertEqual(cues[0].start, 2, accuracy: 0.001)
    XCTAssertEqual(cues[0].end, 4, accuracy: 0.001)
    XCTAssertEqual(cues[1].start, 5, accuracy: 0.001)
    XCTAssertEqual(cues[1].end, 6, accuracy: 0.001)

    let srt = VideoEditorSubtitleWriter.srt(cues)
    XCTAssertTrue(srt.contains("00:00:05,000 --> 00:00:06,000\nafter"))
  }

  // MARK: - Layout

  func testLayoutBreaksLinesTheSameAtPreviewAndExportSize() {
    let text = "This caption is long enough that it has to wrap onto a second line"
    let settings = VideoEditorCaptionSettings.default
    let export = VideoEditorCaptionLayout.make(text: text, settings: settings, videoSize: CGSize(width: 1920, height: 1080))
    let preview = VideoEditorCaptionLayout.make(text: text, settings: settings, videoSize: CGSize(width: 640, height: 360))
    XCTAssertEqual(export?.lines.count, 2)
    XCTAssertEqual(export?.lines, preview?.lines)
    let ratio = (export?.size.width ?? 0) / (preview?.size.width ?? 1)
    XCTAssertEqual(ratio, 3, accuracy: 0.01)
    XCTAssertNil(VideoEditorCaptionLayout.make(text: "  ", settings: settings, videoSize: CGSize(width: 100, height: 100)))
  }

  func testLayoutShrinksToFitNarrowVideo() throws {
    var settings = VideoEditorCaptionSettings.default
    settings.fontSize = 0.1
    let layout = try XCTUnwrap(VideoEditorCaptionLayout.make(
      text: "Supercalifragilisticexpialidocious", settings: settings, videoSize: CGSize(width: 300, height: 600)
    ))
    XCTAssertLessThanOrEqual(layout.size.width, 300 * VideoEditorCaptionLayout.maxWidthFraction + 1)
    let frame = layout.frame(in: CGRect(x: 0, y: 0, width: 300, height: 600), settings: settings)
    XCTAssertEqual(frame.maxY, 600 - settings.margin * 600, accuracy: 0.5)
  }

  // MARK: - Export layer

  func testLayerBurnsCaptionNearTheBottomOfTheVideoRect() throws {
    let clips = [TimelineClip(source: .primary, sourceDuration: 10)]
    let map = TimelineSequenceMap(clips: clips, speedSegments: [])
    let layer = VideoEditorCaptionLayer(
      captions: VideoEditorCaptions(segments: [segment(1, 3, "Hello")]),
      mapping: VideoEditorSourceTimeMapping(sequenceMap: map, playbackPlacements: TimelineSequence.playableLayout(clips)),
      sequenceMap: map
    )
    XCTAssertTrue(layer.isActive)
    let extent = CGRect(x: 0, y: 0, width: 400, height: 300)
    let base = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: extent)
    let context = { (time: TimeInterval) in
      VideoEditorStudioLayerContext(outputTime: time, extent: extent, auxiliaryFrames: [:])
    }
    let ci = CIContext()
    func pixel(_ image: CIImage, _ x: CGFloat, _ y: CGFloat) -> [UInt8] {
      var out = [UInt8](repeating: 0, count: 4)
      ci.render(image, toBitmap: &out, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1),
                format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
      return out
    }

    let hidden = layer.composite(onto: base, context: context(5))
    XCTAssertEqual(pixel(hidden, 200, 40)[2], 255)

    let shown = layer.composite(onto: base, context: context(2))
    // Bottom center (Core Image y grows up) is darkened by the pill; the top is untouched.
    XCTAssertLessThan(pixel(shown, 200, 300 * 0.06 + 3)[2], 200)
    XCTAssertEqual(pixel(shown, 200, 280)[2], 255)
  }

  // MARK: - Persistence shape

  func testCaptionsDecodeWithMissingKeys() throws {
    let decoded = try JSONDecoder().decode(VideoEditorCaptions.self, from: Data(#"{"settings":{"fontSize":0.07}}"#.utf8))
    XCTAssertTrue(decoded.segments.isEmpty)
    XCTAssertEqual(decoded.settings.fontSize, 0.07)
    XCTAssertEqual(decoded.settings.maxCharsPerLine, 42)

    let captions = VideoEditorCaptions(segments: [segment(1, 2, "x")])
    let roundTrip = try JSONDecoder().decode(VideoEditorCaptions.self, from: JSONEncoder().encode(captions))
    XCTAssertEqual(roundTrip, captions)
  }
}
