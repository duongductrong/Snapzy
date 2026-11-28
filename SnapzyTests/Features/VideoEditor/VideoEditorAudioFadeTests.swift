//
//  VideoEditorAudioFadeTests.swift
//  SnapzyTests
//

import AVFoundation
@testable import Snapzy
import XCTest

final class VideoEditorAudioFadeTests: XCTestCase {
  func testExportSettings_decodesLegacyJSONWithoutFadeFields() throws {
    let legacyJSON = """
    {
      "quality": "High",
      "dimensionPreset": "Original",
      "customWidth": 1920,
      "customHeight": 1080,
      "aspectRatioLocked": true,
      "audioMode": "Keep Original",
      "audioVolume": 1.0,
      "systemAudioVolume": 1.0,
      "microphoneAudioVolume": 0.8
    }
    """
    let decoded = try JSONDecoder().decode(ExportSettings.self, from: Data(legacyJSON.utf8))
    XCTAssertEqual(decoded.audioFadeIn, 0)
    XCTAssertEqual(decoded.audioFadeOut, 0)
    XCTAssertFalse(decoded.hasAudioFades)
    XCTAssertFalse(decoded.requiresAudioMix)
    XCTAssertEqual(decoded.microphoneAudioVolume, 0.8, accuracy: 0.001)
  }

  func testExportSettings_requiresAudioMixForKeepWithFadesAndNotForMute() {
    var settings = ExportSettings()
    XCTAssertFalse(settings.requiresAudioMix)

    settings.setAudioFadeIn(0.6)
    XCTAssertTrue(settings.hasAudioFades)
    XCTAssertTrue(settings.requiresAudioMix)

    settings.audioMode = .mute
    XCTAssertFalse(settings.hasAudioFades)
    XCTAssertFalse(settings.requiresAudioMix)
  }

  func testResolvedFadeDurations_scalesProportionallyWhenFadesExceedDuration() {
    let normal = VideoEditorAudioMixFactory.resolvedFadeDurations(
      fadeIn: 0.5,
      fadeOut: 1.0,
      totalDuration: 5.0
    )
    XCTAssertEqual(normal.fadeIn, 0.5, accuracy: 0.0001)
    XCTAssertEqual(normal.fadeOut, 1.0, accuracy: 0.0001)

    let scaled = VideoEditorAudioMixFactory.resolvedFadeDurations(
      fadeIn: 1.0,
      fadeOut: 3.0,
      totalDuration: 2.0
    )
    XCTAssertEqual(scaled.fadeIn, 0.5, accuracy: 0.0001)
    XCTAssertEqual(scaled.fadeOut, 1.5, accuracy: 0.0001)
    XCTAssertLessThanOrEqual(scaled.fadeIn + scaled.fadeOut, 2.0001)

    let invalid = VideoEditorAudioMixFactory.resolvedFadeDurations(
      fadeIn: .nan,
      fadeOut: -2.0,
      totalDuration: 4.0
    )
    XCTAssertEqual(invalid.fadeIn, 0)
    XCTAssertEqual(invalid.fadeOut, 0)
  }

  func testMakeAudioMix_appliesFadeInAndFadeOutVolumeRampsAcrossTimeRange() async throws {
    let wavURL = try makeSilentWAV(duration: 4.0)
    defer { try? FileManager.default.removeItem(at: wavURL) }

    let asset = AVURLAsset(url: wavURL)
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    XCTAssertFalse(tracks.isEmpty)

    var settings = ExportSettings()
    settings.audioMode = .custom
    settings.setAudioVolume(0.8, for: .mixed)
    settings.setAudioFadeIn(0.5)
    settings.setAudioFadeOut(1.0)

    let trimmedRange = CMTimeRange(
      start: CMTime(seconds: 1.0, preferredTimescale: 600),
      duration: CMTime(seconds: 3.0, preferredTimescale: 600)
    )
    let mix = try XCTUnwrap(
      VideoEditorAudioMixFactory.makeAudioMix(
        for: tracks,
        settings: settings,
        audioTimeRange: trimmedRange
      )
    )
    let params = try XCTUnwrap(mix.inputParameters.first)

    var startVol: Float = -1
    var endVol: Float = -1
    var rampRange = CMTimeRange.zero

    XCTAssertTrue(
      params.getVolumeRamp(
        for: CMTime(seconds: 1.1, preferredTimescale: 600),
        startVolume: &startVol,
        endVolume: &endVol,
        timeRange: &rampRange
      )
    )
    XCTAssertEqual(startVol, 0.0, accuracy: 0.001)
    XCTAssertEqual(endVol, 0.8, accuracy: 0.001)
    XCTAssertEqual(CMTimeGetSeconds(rampRange.start), 1.0, accuracy: 0.01)
    XCTAssertEqual(CMTimeGetSeconds(rampRange.duration), 0.5, accuracy: 0.01)

    XCTAssertTrue(
      params.getVolumeRamp(
        for: CMTime(seconds: 3.5, preferredTimescale: 600),
        startVolume: &startVol,
        endVolume: &endVol,
        timeRange: &rampRange
      )
    )
    XCTAssertEqual(startVol, 0.8, accuracy: 0.001)
    XCTAssertEqual(endVol, 0.0, accuracy: 0.001)
    XCTAssertEqual(CMTimeGetSeconds(rampRange.start), 3.0, accuracy: 0.01)
    XCTAssertEqual(CMTimeGetSeconds(rampRange.duration), 1.0, accuracy: 0.01)
  }

  private func makeSilentWAV(duration: Double) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("snapzy-fade-test-\(UUID().uuidString).wav")
    let sampleRate: Double = 16_000
    let frameCount = AVAudioFrameCount(sampleRate * duration)
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
    buffer.frameLength = frameCount
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    return url
  }
}
