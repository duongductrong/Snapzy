//
//  ScreenRecordingEncodingSettingsTests.swift
//  SnapzyTests
//
//  Tests for deterministic screen-recording encoding decisions.
//

import AVFoundation
import XCTest
@testable import Snapzy

@MainActor
final class ScreenRecordingEncodingSettingsTests: XCTestCase {

  func testVideoFormatProperties_mapToExpectedAVFileTypesAndExtensions() {
    XCTAssertEqual(VideoFormat.mov.fileType.rawValue, AVFileType.mov.rawValue)
    XCTAssertEqual(VideoFormat.mov.fileExtension, "mov")
    XCTAssertEqual(VideoFormat.mov.displayName, "MOV")

    XCTAssertEqual(VideoFormat.mp4.fileType.rawValue, AVFileType.mp4.rawValue)
    XCTAssertEqual(VideoFormat.mp4.fileExtension, "mp4")
    XCTAssertEqual(VideoFormat.mp4.displayName, "MP4")
  }

  func testPreferredCodec_mp4AlwaysUsesH264() {
    for quality in VideoQuality.allCases {
      let codec = RecordingVideoEncodingSettings.preferredCodec(format: .mp4, quality: quality)
      XCTAssertEqual(codec.rawValue, AVVideoCodecType.h264.rawValue)
    }
  }

  func testPreferredCodec_movHighUsesPlatformPreferredCodec() {
    let codec = RecordingVideoEncodingSettings.preferredCodec(format: .mov, quality: .high)

    #if arch(arm64)
      XCTAssertEqual(codec.rawValue, AVVideoCodecType.hevc.rawValue)
    #else
      XCTAssertEqual(codec.rawValue, AVVideoCodecType.h264.rawValue)
    #endif
  }

  func testPreferredCodec_movMediumAndLowUseH264() {
    XCTAssertEqual(
      RecordingVideoEncodingSettings.preferredCodec(format: .mov, quality: .medium).rawValue,
      AVVideoCodecType.h264.rawValue
    )
    XCTAssertEqual(
      RecordingVideoEncodingSettings.preferredCodec(format: .mov, quality: .low).rawValue,
      AVVideoCodecType.h264.rawValue
    )
  }

  func testCalculatedBitrate_smallCaptureClampsToQualityMinimum() {
    let bitrate = RecordingVideoEncodingSettings.calculatedBitrate(
      width: 100,
      height: 100,
      fps: 30,
      quality: .high,
      codec: .h264
    )

    XCTAssertEqual(bitrate, VideoQuality.high.minBitrate)
  }

  func testCalculatedBitrate_hugeCaptureClampsToQualityMaximum() {
    let bitrate = RecordingVideoEncodingSettings.calculatedBitrate(
      width: 7_680,
      height: 4_320,
      fps: 60,
      quality: .high,
      codec: .h264
    )

    XCTAssertEqual(bitrate, VideoQuality.high.maxBitrate)
  }

  func testCalculatedBitrate_appliesHEVCEfficiencyBeforeClamp() {
    let h264Bitrate = RecordingVideoEncodingSettings.calculatedBitrate(
      width: 1_920,
      height: 1_080,
      fps: 30,
      quality: .low,
      codec: .h264
    )
    let hevcBitrate = RecordingVideoEncodingSettings.calculatedBitrate(
      width: 1_920,
      height: 1_080,
      fps: 30,
      quality: .low,
      codec: .hevc
    )

    XCTAssertEqual(h264Bitrate, 4_976_640)
    XCTAssertEqual(hevcBitrate, 4_478_976)
  }

  func testMakeVideoSettings_h264IncludesProfileFPSAndColorProperties() throws {
    let settings = RecordingVideoEncodingSettings.makeVideoSettings(
      width: 1_280,
      height: 720,
      fps: 60,
      quality: .medium,
      codec: .h264,
      bitrate: 7_200_000
    )

    XCTAssertEqual(codecRawValue(settings[AVVideoCodecKey]), AVVideoCodecType.h264.rawValue)
    XCTAssertEqual(settings[AVVideoWidthKey] as? Int, 1_280)
    XCTAssertEqual(settings[AVVideoHeightKey] as? Int, 720)

    let compression = try XCTUnwrap(settings[AVVideoCompressionPropertiesKey] as? [String: Any])
    XCTAssertEqual(compression[AVVideoAverageBitRateKey] as? Int, 7_200_000)
    XCTAssertEqual(compression[AVVideoExpectedSourceFrameRateKey] as? Int, 60)
    XCTAssertEqual(compression[AVVideoMaxKeyFrameIntervalKey] as? Int, 60)
    XCTAssertEqual(compression[AVVideoProfileLevelKey] as? String, VideoQuality.medium.h264ProfileLevel)

    let color = try XCTUnwrap(settings[AVVideoColorPropertiesKey] as? [String: Any])
    XCTAssertEqual(color[AVVideoColorPrimariesKey] as? String, AVVideoColorPrimaries_ITU_R_709_2)
    XCTAssertEqual(color[AVVideoTransferFunctionKey] as? String, AVVideoTransferFunction_ITU_R_709_2)
    XCTAssertEqual(color[AVVideoYCbCrMatrixKey] as? String, AVVideoYCbCrMatrix_ITU_R_709_2)
  }

  func testMakeVideoSettings_hevcOmitsH264Profile() throws {
    let settings = RecordingVideoEncodingSettings.makeVideoSettings(
      width: 1_920,
      height: 1_080,
      fps: 30,
      quality: .high,
      codec: .hevc,
      bitrate: 10_000_000
    )

    XCTAssertEqual(codecRawValue(settings[AVVideoCodecKey]), AVVideoCodecType.hevc.rawValue)
    let compression = try XCTUnwrap(settings[AVVideoCompressionPropertiesKey] as? [String: Any])
    XCTAssertNil(compression[AVVideoProfileLevelKey])
  }

  private func codecRawValue(_ value: Any?) -> String? {
    if let codec = value as? AVVideoCodecType {
      return codec.rawValue
    }
    return value as? String
  }
}
