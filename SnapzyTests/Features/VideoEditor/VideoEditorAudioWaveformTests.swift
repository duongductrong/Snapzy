//
//  VideoEditorAudioWaveformTests.swift
//  SnapzyTests
//

import AVFoundation
@testable import Snapzy
import XCTest

final class VideoEditorAudioWaveformTests: XCTestCase {
  func testEmptyWaveform_reportsEmptyAndSilent() {
    let empty = VideoEditorAudioWaveform.empty
    XCTAssertTrue(empty.isEmpty)
    XCTAssertTrue(empty.isSilent)
    XCTAssertEqual(empty.slice(from: 0, to: 1, barCount: 10), [])
  }

  func testExtractPeaks_normalizesRelativeToGlobalPeakWithPerceptualCurve() {
    let raw: [Float] = [0.25, -0.25, 0.5, -0.5, 1.0, -1.0, 0.0, 0.0]
    let peaks = VideoEditorAudioWaveform.extractPeaks(from: raw, bucketCount: 4)
    XCTAssertEqual(peaks.count, 4)
    XCTAssertEqual(peaks[2], 1.0, accuracy: 0.001)
    XCTAssertEqual(peaks[3], 0.0, accuracy: 0.001)
    XCTAssertGreaterThan(peaks[0], 0.25)
    XCTAssertGreaterThan(peaks[1], peaks[0])
    XCTAssertLessThan(peaks[1], peaks[2])
  }

  func testExtractPeaks_handlesDigitalSilenceAndNonFiniteSamplesSafely() {
    let silent: [Float] = [0.0001, -0.0002, 0.0, 0.0001]
    XCTAssertEqual(VideoEditorAudioWaveform.extractPeaks(from: silent, bucketCount: 2), [0, 0])

    let noisy: [Float] = [.nan, .infinity, -.infinity, 0.5, -1.0, 0.25]
    let peaks = VideoEditorAudioWaveform.extractPeaks(from: noisy, bucketCount: 2)
    XCTAssertEqual(peaks.count, 2)
    XCTAssertTrue(peaks.allSatisfy(\.isFinite))
    XCTAssertEqual(peaks[1], 1.0, accuracy: 0.001)
  }

  func testSlice_alignsAccuratelyForTrimmedAndSplitClips() {
    let waveform = VideoEditorAudioWaveform(
      samples: [0.1, 0.2, 0.9, 1.0, 0.3, 0.4, 0.8, 0.7],
      duration: 8.0
    )

    let firstHalf = waveform.slice(from: 0.0, to: 4.0, barCount: 2)
    XCTAssertEqual(firstHalf.count, 2)
    XCTAssertEqual(firstHalf[0], 0.2, accuracy: 0.001)
    XCTAssertEqual(firstHalf[1], 1.0, accuracy: 0.001)

    let secondHalf = waveform.slice(from: 4.0, to: 8.0, barCount: 2)
    XCTAssertEqual(secondHalf.count, 2)
    XCTAssertEqual(secondHalf[0], 0.4, accuracy: 0.001)
    XCTAssertEqual(secondHalf[1], 0.8, accuracy: 0.001)

    // Out-of-bounds range clamps cleanly without crashing.
    let clamped = waveform.slice(from: -5.0, to: 20.0, barCount: 4)
    XCTAssertEqual(clamped.count, 4)
    XCTAssertEqual(clamped[1], 1.0, accuracy: 0.001)
  }

  func testLayoutHelpers_clampBucketCountAndBarDensity() {
    XCTAssertEqual(VideoEditorAudioWaveform.recommendedBucketCount(for: 0.5), 64)
    XCTAssertEqual(VideoEditorAudioWaveform.recommendedBucketCount(for: 300), 960)
    XCTAssertEqual(VideoEditorAudioWaveform.barCount(forWidth: 8), 0)
    XCTAssertEqual(VideoEditorAudioWaveform.barCount(forWidth: 12), 4)
    XCTAssertEqual(VideoEditorAudioWaveform.barCount(forWidth: 15), 5)
    XCTAssertEqual(VideoEditorAudioWaveform.barCount(forWidth: 300), 100)
    XCTAssertEqual(VideoEditorAudioWaveform.barCount(forWidth: 5000), 480)
  }

  func testExtractWaveform_readsRealAudioFileAndDetectsActiveRegion() async throws {
    let wavURL = try makeTestToneWAV(duration: 1.0, silentSecondHalf: true)
    defer { try? FileManager.default.removeItem(at: wavURL) }

    let waveform = await VideoEditorAudioWaveformCache.extractWaveform(for: wavURL)
    XCTAssertFalse(waveform.isEmpty)
    XCTAssertFalse(waveform.isSilent)
    XCTAssertEqual(waveform.duration, 1.0, accuracy: 0.05)

    let bars = waveform.slice(from: 0, to: 1.0, barCount: 4)
    XCTAssertEqual(bars.count, 4)
    XCTAssertGreaterThan(bars[0], 0.7, "First half contains 440Hz tone")
    XCTAssertLessThan(bars[3], 0.05, "Second half is digital silence")
  }

  private func makeTestToneWAV(duration: Double, silentSecondHalf: Bool) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("snapzy-waveform-test-\(UUID().uuidString).wav")
    let sampleRate: Double = 16_000
    let frameCount = AVAudioFrameCount(sampleRate * duration)
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
    buffer.frameLength = frameCount

    let channel = try XCTUnwrap(buffer.floatChannelData?[0])
    for i in 0 ..< Int(frameCount) {
      if silentSecondHalf, i >= Int(frameCount) / 2 {
        channel[i] = 0
      } else {
        channel[i] = sinf(2 * .pi * 440 * Float(i) / Float(sampleRate)) * 0.8
      }
    }

    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    return url
  }

  @MainActor
  func testWaveformCache_loadsCachesAndForgetsURLCleanly() async throws {
    let wavURL = try makeTestToneWAV(duration: 0.6, silentSecondHalf: false)
    defer { try? FileManager.default.removeItem(at: wavURL) }

    let cache = VideoEditorAudioWaveformCache()
    XCTAssertNil(cache.waveform(for: wavURL))
    cache.ensureLoaded(for: wavURL)

    let deadline = Date().addingTimeInterval(5)
    while cache.waveform(for: wavURL) == nil, Date() < deadline {
      try await Task.sleep(nanoseconds: 25_000_000)
    }

    let loaded = try XCTUnwrap(cache.waveform(for: wavURL))
    XCTAssertFalse(loaded.isEmpty)

    cache.forget(url: wavURL)
    XCTAssertNil(cache.waveform(for: wavURL))
  }
}
