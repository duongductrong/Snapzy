//
//  RecordingConfigurationTests.swift
//  SnapzyTests
//
//  Tests for screen-recording toolbar and overlay configuration defaults.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class RecordingConfigurationTests: XCTestCase {

  private let preferenceKeys = [
    PreferencesKeys.recordingFormat,
    PreferencesKeys.recordingQuality,
    PreferencesKeys.recordingCaptureAudio,
    PreferencesKeys.recordingCaptureMicrophone,
    PreferencesKeys.recordingOutputMode,
    PreferencesKeys.recordingHighlightClicks,
    PreferencesKeys.recordingShowKeystrokes,
    PreferencesKeys.mouseHighlightSize,
    PreferencesKeys.mouseHighlightAnimationDuration,
    PreferencesKeys.mouseHighlightColor,
    PreferencesKeys.mouseHighlightOpacity,
    PreferencesKeys.mouseHighlightRippleCount,
    PreferencesKeys.keystrokeFontSize,
    PreferencesKeys.keystrokePosition,
    PreferencesKeys.keystrokeDisplayDuration,
  ]

  private var originalValues: [String: Any] = [:]
  private var originallyMissing = Set<String>()

  override func setUp() async throws {
    try await super.setUp()
    originalValues.removeAll()
    originallyMissing.removeAll()

    for key in preferenceKeys {
      if let value = UserDefaults.standard.object(forKey: key) {
        originalValues[key] = value
      } else {
        originallyMissing.insert(key)
      }
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  override func tearDown() async throws {
    for key in preferenceKeys {
      if originallyMissing.contains(key) {
        UserDefaults.standard.removeObject(forKey: key)
      } else if let value = originalValues[key] {
        UserDefaults.standard.set(value, forKey: key)
      }
    }
    try await super.tearDown()
  }

  func testRecordingToolbarPreferences_defaults() {
    XCTAssertEqual(RecordingToolbarPreferences.selectedFormat(), .mov)
    XCTAssertEqual(RecordingToolbarPreferences.selectedQuality(), .high)
    XCTAssertTrue(RecordingToolbarPreferences.captureAudio())
    XCTAssertFalse(RecordingToolbarPreferences.captureMicrophone())
    XCTAssertEqual(RecordingToolbarPreferences.outputMode(), .video)
    XCTAssertFalse(RecordingToolbarPreferences.highlightClicks())
    XCTAssertFalse(RecordingToolbarPreferences.showKeystrokes())
  }

  func testRecordingToolbarPreferences_usePersistedRecordingOptions() {
    UserDefaults.standard.set(VideoFormat.mp4.rawValue, forKey: PreferencesKeys.recordingFormat)
    UserDefaults.standard.set(VideoQuality.low.rawValue, forKey: PreferencesKeys.recordingQuality)
    UserDefaults.standard.set(false, forKey: PreferencesKeys.recordingCaptureAudio)
    UserDefaults.standard.set(true, forKey: PreferencesKeys.recordingCaptureMicrophone)
    UserDefaults.standard.set(RecordingOutputMode.gif.rawValue, forKey: PreferencesKeys.recordingOutputMode)
    UserDefaults.standard.set(true, forKey: PreferencesKeys.recordingHighlightClicks)
    UserDefaults.standard.set(true, forKey: PreferencesKeys.recordingShowKeystrokes)

    XCTAssertEqual(RecordingToolbarPreferences.selectedFormat(), .mp4)
    XCTAssertEqual(RecordingToolbarPreferences.selectedQuality(), .low)
    XCTAssertFalse(RecordingToolbarPreferences.captureAudio())
    XCTAssertTrue(RecordingToolbarPreferences.captureMicrophone())
    XCTAssertEqual(RecordingToolbarPreferences.outputMode(), .gif)
    XCTAssertTrue(RecordingToolbarPreferences.highlightClicks())
    XCTAssertTrue(RecordingToolbarPreferences.showKeystrokes())
  }

  func testRecordingToolbarPreferences_invalidRawValuesFallBackToSafeDefaults() {
    UserDefaults.standard.set("avi", forKey: PreferencesKeys.recordingFormat)
    UserDefaults.standard.set("ultra", forKey: PreferencesKeys.recordingQuality)
    UserDefaults.standard.set("cinematic", forKey: PreferencesKeys.recordingOutputMode)

    XCTAssertEqual(RecordingToolbarPreferences.selectedFormat(), .mov)
    XCTAssertEqual(RecordingToolbarPreferences.selectedQuality(), .high)
    XCTAssertEqual(RecordingToolbarPreferences.outputMode(), .video)
  }

  func testRecordingMouseTrackerSamplesPerSecond_clampsToSupportedRange() {
    XCTAssertEqual(RecordingMouseTracker.resolvedSamplesPerSecond(for: 15), 60)
    XCTAssertEqual(RecordingMouseTracker.resolvedSamplesPerSecond(for: 30), 60)
    XCTAssertEqual(RecordingMouseTracker.resolvedSamplesPerSecond(for: 60), 120)
    XCTAssertEqual(RecordingMouseTracker.resolvedSamplesPerSecond(for: 240), 120)
  }

  func testMouseHighlightConfiguration_defaults() {
    let config = MouseHighlightConfiguration()

    XCTAssertEqual(config.highlightSize, MouseHighlightConfiguration.defaultHighlightSize)
    XCTAssertEqual(config.holdCircleSize, MouseHighlightConfiguration.defaultHoldCircleSize)
    XCTAssertEqual(config.ringWidth, MouseHighlightConfiguration.defaultRingWidth)
    XCTAssertEqual(config.animationDuration, MouseHighlightConfiguration.defaultAnimationDuration)
    XCTAssertEqual(config.rippleCount, MouseHighlightConfiguration.defaultRippleCount)
    XCTAssertEqual(config.highlightOpacity, MouseHighlightConfiguration.defaultHighlightOpacity)
    XCTAssertTrue(config.highlightColor.isEqual(MouseHighlightConfiguration.defaultHighlightColor))
  }

  func testMouseHighlightConfiguration_usesPersistedValues() throws {
    let color = NSColor(calibratedRed: 0.9, green: 0.2, blue: 0.4, alpha: 1.0)
    let colorData = try NSKeyedArchiver.archivedData(
      withRootObject: color,
      requiringSecureCoding: true
    )
    UserDefaults.standard.set(CGFloat(100), forKey: PreferencesKeys.mouseHighlightSize)
    UserDefaults.standard.set(1.2, forKey: PreferencesKeys.mouseHighlightAnimationDuration)
    UserDefaults.standard.set(colorData, forKey: PreferencesKeys.mouseHighlightColor)
    UserDefaults.standard.set(0.8, forKey: PreferencesKeys.mouseHighlightOpacity)
    UserDefaults.standard.set(5, forKey: PreferencesKeys.mouseHighlightRippleCount)

    let config = MouseHighlightConfiguration()

    XCTAssertEqual(config.highlightSize, 100)
    XCTAssertEqual(config.holdCircleSize, 72)
    XCTAssertEqual(config.animationDuration, 1.2)
    XCTAssertEqual(config.rippleCount, 5)
    XCTAssertEqual(config.highlightOpacity, 0.8)
    XCTAssertTrue(config.highlightColor.isEqual(color))
  }

  func testMouseHighlightConfiguration_nonPositiveRippleCountFallsBackToDefault() {
    UserDefaults.standard.set(0, forKey: PreferencesKeys.mouseHighlightRippleCount)

    let config = MouseHighlightConfiguration()

    XCTAssertEqual(config.rippleCount, MouseHighlightConfiguration.defaultRippleCount)
  }

  func testKeystrokeOverlayConfiguration_defaults() {
    let config = KeystrokeOverlayConfiguration()

    XCTAssertEqual(config.fontSize, KeystrokeOverlayConfiguration.defaultFontSize)
    XCTAssertEqual(config.position, KeystrokeOverlayConfiguration.defaultPosition)
    XCTAssertEqual(config.displayDuration, KeystrokeOverlayConfiguration.defaultDisplayDuration)
    XCTAssertEqual(config.edgeOffset, KeystrokeOverlayConfiguration.defaultEdgeOffset)
  }

  func testKeystrokeOverlayConfiguration_usesPersistedValues() {
    UserDefaults.standard.set(CGFloat(22), forKey: PreferencesKeys.keystrokeFontSize)
    UserDefaults.standard.set(KeystrokeOverlayPosition.topRight.rawValue, forKey: PreferencesKeys.keystrokePosition)
    UserDefaults.standard.set(2.5, forKey: PreferencesKeys.keystrokeDisplayDuration)

    let config = KeystrokeOverlayConfiguration()

    XCTAssertEqual(config.fontSize, 22)
    XCTAssertEqual(config.position, .topRight)
    XCTAssertEqual(config.displayDuration, 2.5)
  }

  func testKeystrokeOverlayConfiguration_invalidPositionFallsBackToDefault() {
    UserDefaults.standard.set("middle", forKey: PreferencesKeys.keystrokePosition)

    let config = KeystrokeOverlayConfiguration()

    XCTAssertEqual(config.position, KeystrokeOverlayConfiguration.defaultPosition)
  }
}
