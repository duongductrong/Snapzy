//
//  VideoEditorCaptionSegmenterTests.swift
//  SnapzyTests
//
//  Captions engine (5a): words → segments, SRT / VTT text.
//

import XCTest
@testable import Snapzy

final class VideoEditorCaptionSegmenterTests: XCTestCase {
  private nonisolated func word(_ text: String, _ start: Double, _ duration: Double = 0.3) -> VideoEditorTranscriptWord {
    .init(start: start, duration: duration, text: text)
  }

  func testSentenceEndBreaksOnceTheCaptionIsLongEnough() {
    let words = [word("One", 0), word("two", 0.4), word("three.", 0.8, 0.5), word("Four", 1.5), word("five.", 1.9)]
    let segments = VideoEditorCaptionSegmenter.segment(words)
    XCTAssertEqual(segments.map(\.text), ["One two three.", "Four five."])
  }

  func testPauseStartsANewCaption() {
    let segments = VideoEditorCaptionSegmenter.segment([word("alpha", 0), word("beta", 0.4), word("gamma", 2.0)])
    XCTAssertEqual(segments.map(\.text), ["alpha beta", "gamma"])
  }

  func testCharacterBudgetAndMaxDurationSplit() {
    let words = (0 ..< 30).map { word("word\($0)", Double($0) * 0.3) }
    let options = VideoEditorCaptionSegmenterOptions(maxCharsPerLine: 20, maxLines: 2, minDuration: 1, maxDuration: 6, pauseBreak: 0.6)
    let segments = VideoEditorCaptionSegmenter.segment(words, options: options)
    XCTAssertGreaterThan(segments.count, 1)
    XCTAssertTrue(segments.allSatisfy { $0.text.count <= options.maxCharacters })
    XCTAssertEqual(segments.flatMap { $0.words ?? [] }.count, 30)
  }

  func testShortCaptionIsExtendedButNotIntoTheNextOne() {
    let segments = VideoEditorCaptionSegmenter.segment([word("hi", 0, 0.2), word("later", 1.0, 0.2)])
    XCTAssertEqual(segments.count, 2)
    XCTAssertEqual(segments[0].end, 1.0, accuracy: 1e-9)
    XCTAssertEqual(segments[1].end, 2.0, accuracy: 1e-9)
  }

  func testCJKIsCountedAndJoinedByCharacters() {
    let text = String(repeating: "你好世界", count: 50)  // 200 characters, one token
    let segments = VideoEditorCaptionSegmenter.segment([word(text, 0, 8)])
    XCTAssertEqual(segments.count, 3)
    XCTAssertTrue(segments.allSatisfy { $0.text.count <= 84 && !$0.text.contains(" ") })
    XCTAssertEqual(segments.map(\.text).joined(), text)
    XCTAssertEqual(VideoEditorCaptionSegmenter.join(["你好", "世界", "ok", "go"]), "你好世界ok go")
  }

  func testLineBreakerWrapsWordsAndCJK() {
    XCTAssertEqual(VideoEditorCaptionLineBreaker.lines("the quick brown fox", maxCharsPerLine: 10), ["the quick", "brown fox"])
    XCTAssertEqual(VideoEditorCaptionLineBreaker.lines("你好世界你好", maxCharsPerLine: 4), ["你好世界", "你好"])
  }

  // MARK: - Subtitles

  func testSRTFormat() {
    let cues = [
      VideoEditorSubtitleCue(start: 1.5, end: 3.25, text: "Hello"),
      VideoEditorSubtitleCue(start: 3661.0004, end: 3662, text: "Second\n\nline"),
      VideoEditorSubtitleCue(start: 5, end: 5, text: "dropped"),
    ]
    XCTAssertEqual(
      VideoEditorSubtitleWriter.srt(cues),
      "1\n00:00:01,500 --> 00:00:03,250\nHello\n\n2\n01:01:01,000 --> 01:01:02,000\nSecond\nline\n"
    )
  }

  func testVTTFormatEscapesMarkup() {
    let output = VideoEditorSubtitleWriter.vtt([VideoEditorSubtitleCue(start: 0, end: 1.2, text: "a < b & c")])
    XCTAssertEqual(output, "WEBVTT\n\n00:00:00.000 --> 00:00:01.200\na &lt; b &amp; c\n")
  }

  func testEmptyInputWritesNoCues() {
    XCTAssertEqual(VideoEditorSubtitleWriter.srt([]), "")
    XCTAssertEqual(VideoEditorSubtitleWriter.vtt([]), "WEBVTT\n\n")
  }
}
