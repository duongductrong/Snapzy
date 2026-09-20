//
//  RecordingConfigurationTests.swift
//  SnapzyTests
//
//  Tests for screen-recording toolbar and overlay configuration defaults.
//

import AppKit
@testable import Snapzy
import XCTest

@MainActor
final class RecordingConfigurationTests: XCTestCase {
  private var defaults: UserDefaults!

  override func setUp() async throws {
    try await super.setUp()
    defaults = UserDefaultsFactory.make()
  }

  func testRecordingToolbarPreferences_defaults() {
    XCTAssertEqual(RecordingToolbarPreferences.selectedFormat(defaults: defaults), .mov)
    XCTAssertEqual(RecordingToolbarPreferences.selectedQuality(defaults: defaults), .high)
    XCTAssertEqual(RecordingToolbarPreferences.selectedMaxResolution(defaults: defaults), .auto)
    XCTAssertTrue(RecordingToolbarPreferences.captureAudio(defaults: defaults))
    XCTAssertFalse(RecordingToolbarPreferences.captureMicrophone(defaults: defaults))
    XCTAssertEqual(
      RecordingToolbarPreferences.microphoneDeviceID(defaults: defaults),
      RecordingMicrophoneDevice.systemDefaultID
    )
    XCTAssertFalse(RecordingToolbarPreferences.captureCamera(defaults: defaults))
    XCTAssertEqual(
      RecordingToolbarPreferences.cameraDeviceID(defaults: defaults),
      RecordingCameraDevice.systemDefaultID
    )
    XCTAssertEqual(RecordingToolbarPreferences.outputMode(defaults: defaults), .video)
    XCTAssertTrue(RecordingToolbarPreferences.showCursor(defaults: defaults))
    XCTAssertFalse(RecordingToolbarPreferences.highlightClicks(defaults: defaults))
    XCTAssertFalse(RecordingToolbarPreferences.showKeystrokes(defaults: defaults))
  }

  func testRecordingToolbarPreferences_usePersistedRecordingOptions() {
    defaults.set(VideoFormat.mp4.rawValue, forKey: PreferencesKeys.recordingFormat)
    defaults.set(VideoQuality.low.rawValue, forKey: PreferencesKeys.recordingQuality)
    defaults.set(RecordingMaxResolution.fhd1080.rawValue, forKey: PreferencesKeys.recordingMaxResolution)
    defaults.set(false, forKey: PreferencesKeys.recordingCaptureAudio)
    defaults.set(true, forKey: PreferencesKeys.recordingCaptureMicrophone)
    defaults.set("external-mic-id", forKey: PreferencesKeys.recordingMicrophoneDeviceID)
    defaults.set(true, forKey: PreferencesKeys.recordingCaptureCamera)
    defaults.set("iphone-camera-id", forKey: PreferencesKeys.recordingCameraDeviceID)
    defaults.set(RecordingOutputMode.gif.rawValue, forKey: PreferencesKeys.recordingOutputMode)
    defaults.set(false, forKey: PreferencesKeys.recordingShowCursor)
    defaults.set(true, forKey: PreferencesKeys.recordingHighlightClicks)
    defaults.set(true, forKey: PreferencesKeys.recordingShowKeystrokes)

    XCTAssertEqual(RecordingToolbarPreferences.selectedFormat(defaults: defaults), .mp4)
    XCTAssertEqual(RecordingToolbarPreferences.selectedQuality(defaults: defaults), .low)
    XCTAssertEqual(RecordingToolbarPreferences.selectedMaxResolution(defaults: defaults), .fhd1080)
    XCTAssertFalse(RecordingToolbarPreferences.captureAudio(defaults: defaults))
    XCTAssertTrue(RecordingToolbarPreferences.captureMicrophone(defaults: defaults))
    XCTAssertEqual(RecordingToolbarPreferences.microphoneDeviceID(defaults: defaults), "external-mic-id")
    XCTAssertTrue(RecordingToolbarPreferences.captureCamera(defaults: defaults))
    XCTAssertEqual(RecordingToolbarPreferences.cameraDeviceID(defaults: defaults), "iphone-camera-id")
    XCTAssertEqual(RecordingToolbarPreferences.outputMode(defaults: defaults), .gif)
    XCTAssertFalse(RecordingToolbarPreferences.showCursor(defaults: defaults))
    XCTAssertTrue(RecordingToolbarPreferences.highlightClicks(defaults: defaults))
    XCTAssertTrue(RecordingToolbarPreferences.showKeystrokes(defaults: defaults))
  }

  func testRecordingToolbarPreferences_invalidRawValuesFallBackToSafeDefaults() {
    defaults.set("avi", forKey: PreferencesKeys.recordingFormat)
    defaults.set("ultra", forKey: PreferencesKeys.recordingQuality)
    defaults.set("8k", forKey: PreferencesKeys.recordingMaxResolution)
    defaults.set("cinematic", forKey: PreferencesKeys.recordingOutputMode)

    XCTAssertEqual(RecordingToolbarPreferences.selectedFormat(defaults: defaults), .mov)
    XCTAssertEqual(RecordingToolbarPreferences.selectedQuality(defaults: defaults), .high)
    XCTAssertEqual(RecordingToolbarPreferences.selectedMaxResolution(defaults: defaults), .auto)
    XCTAssertEqual(RecordingToolbarPreferences.outputMode(defaults: defaults), .video)
  }

  func testRecordingToolbarPlacement_usesOutsideGapWhenBelowSelectionFits() {
    let toolbarSize = CGSize(width: 240, height: 44)
    let screenFrame = CGRect(x: 0, y: 0, width: 1200, height: 900)
    let selectionRect = CGRect(x: 300, y: 220, width: 400, height: 300)

    let origin = RecordingToolbarPlacement.frameOrigin(
      toolbarSize: toolbarSize,
      anchorRect: selectionRect,
      screenFrame: screenFrame
    )

    XCTAssertEqual(origin.x, selectionRect.midX - toolbarSize.width / 2)
    XCTAssertEqual(
      origin.y,
      selectionRect.minY - toolbarSize.height - RecordingToolbarPlacement.outsideSelectionGap
    )
  }

  func testRecordingToolbarPlacement_usesInsideBottomInsetNearScreenBottom() {
    let toolbarSize = CGSize(width: 240, height: 44)
    let screenFrame = CGRect(x: 0, y: 0, width: 1200, height: 900)
    let selectionRect = CGRect(x: 300, y: 24, width: 400, height: 300)

    let origin = RecordingToolbarPlacement.frameOrigin(
      toolbarSize: toolbarSize,
      anchorRect: selectionRect,
      screenFrame: screenFrame
    )

    XCTAssertEqual(
      origin.y,
      selectionRect.minY + RecordingToolbarPlacement.insideSelectionBottomInset
    )
  }

  func testRecordingToolbarPlacement_clampsInsideInsetToVisibleScreen() {
    let toolbarSize = CGSize(width: 240, height: 44)
    let screenFrame = CGRect(x: 0, y: 0, width: 1200, height: 100)
    let selectionRect = CGRect(x: 300, y: 24, width: 400, height: 60)

    let origin = RecordingToolbarPlacement.frameOrigin(
      toolbarSize: toolbarSize,
      anchorRect: selectionRect,
      screenFrame: screenFrame
    )

    XCTAssertEqual(
      origin.y,
      screenFrame.maxY - toolbarSize.height - RecordingToolbarPlacement.screenEdgeInset
    )
  }

  func testRecordingMouseTrackerSamplesPerSecond_clampsToSupportedRange() {
    XCTAssertEqual(RecordingMouseTracker.resolvedSamplesPerSecond(for: 15), 60)
    XCTAssertEqual(RecordingMouseTracker.resolvedSamplesPerSecond(for: 30), 60)
    XCTAssertEqual(RecordingMouseTracker.resolvedSamplesPerSecond(for: 60), 120)
    XCTAssertEqual(RecordingMouseTracker.resolvedSamplesPerSecond(for: 240), 120)
  }

  func testRecordingCameraOverlayPlacement_staysInsideSelectionAtSixteenByNine() {
    let selectionRect = CGRect(x: 100, y: 200, width: 800, height: 600)

    let frame = RecordingCameraOverlayWindow.overlayFrame(in: selectionRect)
    let expectedBottomRight = RecordingCameraOverlayPlacement.targetOrigin(
      for: .bottomRight,
      recordingRect: selectionRect,
      overlaySize: frame.size,
      edgeInset: RecordingCameraOverlayWindow.edgeInset
    )

    XCTAssertTrue(selectionRect.contains(frame))
    XCTAssertEqual(frame.width / frame.height, RecordingCameraOverlayWindow.aspectRatio, accuracy: 0.001)
    XCTAssertEqual(frame.origin, expectedBottomRight)
  }

  func testRecordingCameraOverlayPlacement_resolvesAllEightSnapPoints() {
    let recordingRect = CGRect(x: 100, y: 200, width: 800, height: 600)
    let overlaySize = CGSize(width: 224, height: 126)

    for snapPoint in RecordingCameraOverlaySnapPoint.allCases {
      let target = RecordingCameraOverlayPlacement.targetOrigin(
        for: snapPoint,
        recordingRect: recordingRect,
        overlaySize: overlaySize,
        edgeInset: RecordingCameraOverlayWindow.edgeInset
      )
      let proposedOrigin = CGPoint(x: target.x + 12, y: target.y - 10)

      let resolved = RecordingCameraOverlayPlacement.resolvedOrigin(
        for: proposedOrigin,
        recordingRect: recordingRect,
        overlaySize: overlaySize,
        edgeInset: RecordingCameraOverlayWindow.edgeInset
      )

      XCTAssertEqual(resolved.x, target.x, accuracy: 0.001, "Failed to snap to \(snapPoint)")
      XCTAssertEqual(resolved.y, target.y, accuracy: 0.001, "Failed to snap to \(snapPoint)")
    }
  }

  func testRecordingCameraOverlayPlacement_snapsAtThresholdButNotBeyondIt() {
    let recordingRect = CGRect(x: 100, y: 200, width: 800, height: 600)
    let overlaySize = CGSize(width: 224, height: 126)
    let target = RecordingCameraOverlayPlacement.targetOrigin(
      for: .topLeft,
      recordingRect: recordingRect,
      overlaySize: overlaySize,
      edgeInset: RecordingCameraOverlayWindow.edgeInset
    )

    let atThreshold = CGPoint(
      x: target.x + RecordingCameraOverlayPlacement.snapThreshold,
      y: target.y
    )
    let beyondThreshold = CGPoint(
      x: target.x + RecordingCameraOverlayPlacement.snapThreshold + 0.1,
      y: target.y
    )

    XCTAssertEqual(
      RecordingCameraOverlayPlacement.snapPoint(
        for: atThreshold,
        recordingRect: recordingRect,
        overlaySize: overlaySize,
        edgeInset: RecordingCameraOverlayWindow.edgeInset
      ),
      .topLeft
    )
    XCTAssertNil(
      RecordingCameraOverlayPlacement.snapPoint(
        for: beyondThreshold,
        recordingRect: recordingRect,
        overlaySize: overlaySize,
        edgeInset: RecordingCameraOverlayWindow.edgeInset
      )
    )
  }

  func testRecordingCameraOverlayPlacement_preservesFreeDragAndClampsToRecordingRect() {
    let recordingRect = CGRect(x: 100, y: 200, width: 800, height: 600)
    let overlaySize = CGSize(width: 224, height: 126)
    let freeDragOrigin = CGPoint(x: 380, y: 470)

    XCTAssertEqual(
      RecordingCameraOverlayPlacement.resolvedOrigin(
        for: freeDragOrigin,
        recordingRect: recordingRect,
        overlaySize: overlaySize,
        edgeInset: RecordingCameraOverlayWindow.edgeInset
      ),
      freeDragOrigin
    )

    let bounds = RecordingCameraOverlayPlacement.originBounds(
      in: recordingRect,
      overlaySize: overlaySize,
      edgeInset: RecordingCameraOverlayWindow.edgeInset
    )
    let clamped = RecordingCameraOverlayPlacement.resolvedOrigin(
      for: CGPoint(x: -1_000, y: 1_000),
      recordingRect: recordingRect,
      overlaySize: overlaySize,
      edgeInset: RecordingCameraOverlayWindow.edgeInset
    )

    XCTAssertEqual(clamped.x, bounds.minX, accuracy: 0.001)
    XCTAssertEqual(clamped.y, bounds.maxY, accuracy: 0.001)
  }

  func testRecordingCameraDeviceProvider_doesNotReplaceMissingCamera() {
    XCTAssertNil(RecordingCameraDeviceProvider.captureDevice(matching: "missing-camera-id"))
  }

  func testMouseHighlightConfiguration_defaults() {
    let config = MouseHighlightConfiguration(defaults: defaults)

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
    defaults.set(CGFloat(100), forKey: PreferencesKeys.mouseHighlightSize)
    defaults.set(1.2, forKey: PreferencesKeys.mouseHighlightAnimationDuration)
    defaults.set(colorData, forKey: PreferencesKeys.mouseHighlightColor)
    defaults.set(0.8, forKey: PreferencesKeys.mouseHighlightOpacity)
    defaults.set(5, forKey: PreferencesKeys.mouseHighlightRippleCount)

    let config = MouseHighlightConfiguration(defaults: defaults)

    XCTAssertEqual(config.highlightSize, 100)
    XCTAssertEqual(config.holdCircleSize, 72)
    XCTAssertEqual(config.animationDuration, 1.2)
    XCTAssertEqual(config.rippleCount, 5)
    XCTAssertEqual(config.highlightOpacity, 0.8)
    XCTAssertTrue(config.highlightColor.isEqual(color))
  }

  func testMouseHighlightConfiguration_nonPositiveRippleCountFallsBackToDefault() {
    defaults.set(0, forKey: PreferencesKeys.mouseHighlightRippleCount)

    let config = MouseHighlightConfiguration(defaults: defaults)

    XCTAssertEqual(config.rippleCount, MouseHighlightConfiguration.defaultRippleCount)
  }

  func testKeystrokeOverlayConfiguration_defaults() {
    let config = KeystrokeOverlayConfiguration(defaults: defaults)

    XCTAssertEqual(config.fontSize, KeystrokeOverlayConfiguration.defaultFontSize)
    XCTAssertEqual(config.position, KeystrokeOverlayConfiguration.defaultPosition)
    XCTAssertEqual(config.displayDuration, KeystrokeOverlayConfiguration.defaultDisplayDuration)
    XCTAssertEqual(config.edgeOffset, KeystrokeOverlayConfiguration.defaultEdgeOffset)
  }

  func testKeystrokeOverlayConfiguration_usesPersistedValues() {
    defaults.set(CGFloat(22), forKey: PreferencesKeys.keystrokeFontSize)
    defaults.set(KeystrokeOverlayPosition.topRight.rawValue, forKey: PreferencesKeys.keystrokePosition)
    defaults.set(2.5, forKey: PreferencesKeys.keystrokeDisplayDuration)

    let config = KeystrokeOverlayConfiguration(defaults: defaults)

    XCTAssertEqual(config.fontSize, 22)
    XCTAssertEqual(config.position, .topRight)
    XCTAssertEqual(config.displayDuration, 2.5)
  }

  func testKeystrokeOverlayConfiguration_invalidPositionFallsBackToDefault() {
    defaults.set("middle", forKey: PreferencesKeys.keystrokePosition)

    let config = KeystrokeOverlayConfiguration(defaults: defaults)

    XCTAssertEqual(config.position, KeystrokeOverlayConfiguration.defaultPosition)
  }
}
