//
//  VideoEditorExportSettingsTests.swift
//  SnapzyTests
//
//  Unit tests for video export sizing and zoom segment value models.
//

import AppKit
import AVFoundation
import CoreGraphics
@testable import Snapzy
import XCTest

final class VideoEditorExportSettingsTests: XCTestCase {
  private class MockVideoEditorWindow: VideoEditorWindow {
    var stubbedIsKeyWindow = false
    var stubbedIsMainWindow = false

    override var isKeyWindow: Bool {
      stubbedIsKeyWindow
    }

    override var isMainWindow: Bool {
      stubbedIsMainWindow
    }
  }

  func testVideoEditorSaveTargetKeepsTemporaryCapturesInQuickAccess() {
    XCTAssertEqual(
      VideoEditorSaveTarget.resolve(isTempCapture: true),
      .quickAccessTemp
    )
    XCTAssertEqual(
      VideoEditorSaveTarget.resolve(isTempCapture: false),
      .destination
    )
  }

  @MainActor
  func testVideoEditorWindowFocusSyncKeepsInactiveWindowAtRestingLevel() {
    let window = MockVideoEditorWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600)
    )
    defer { window.close() }

    let activeLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)

    // 1. Neither key nor main -> should be normal
    window.stubbedIsKeyWindow = false
    window.stubbedIsMainWindow = false
    window.syncLevelWithFocusState()
    XCTAssertEqual(window.level, .normal)

    // 2. Key but not main -> should be activeLevel
    window.stubbedIsKeyWindow = true
    window.stubbedIsMainWindow = false
    window.syncLevelWithFocusState()
    XCTAssertEqual(window.level, activeLevel)

    // 3. Main but not key -> should be activeLevel (crucial for popovers/dropdowns)
    window.stubbedIsKeyWindow = false
    window.stubbedIsMainWindow = true
    window.syncLevelWithFocusState()
    XCTAssertEqual(window.level, activeLevel)

    // 4. Both key and main -> should be activeLevel
    window.stubbedIsKeyWindow = true
    window.stubbedIsMainWindow = true
    window.syncLevelWithFocusState()
    XCTAssertEqual(window.level, activeLevel)
  }

  func testVideoEditorExportLayoutEvenSize_roundsToEvenMinimumDimensions() {
    XCTAssertEqual(
      VideoEditorExportLayout.evenSize(CGSize(width: 101.7, height: 1.1)),
      CGSize(width: 102, height: 2)
    )
    XCTAssertEqual(
      VideoEditorExportLayout.evenSize(CGSize(width: -10, height: 0)),
      CGSize(width: 2, height: 2)
    )
  }

  func testVideoEditorExportLayoutAspectRatioCanvasSize_usesNaturalShortEdge() {
    XCTAssertEqual(
      VideoEditorExportLayout.aspectRatioCanvasSize(
        for: CGSize(width: 1920, height: 1080),
        aspectRatio: CGSize(width: 1, height: 1)
      ),
      CGSize(width: 1080, height: 1080)
    )
    XCTAssertEqual(
      VideoEditorExportLayout.aspectRatioCanvasSize(
        for: CGSize(width: 1080, height: 1920),
        aspectRatio: CGSize(width: 16, height: 9)
      ),
      CGSize(width: 1920, height: 1080)
    )
    XCTAssertEqual(
      VideoEditorExportLayout.aspectRatioCanvasSize(
        for: CGSize(width: 0, height: 1080),
        aspectRatio: CGSize(width: 16, height: 9)
      ),
      .zero
    )
  }

  func testVideoEditorExportLayoutAspectFitRect_centersContent() {
    let rect = VideoEditorExportLayout.aspectFitRect(
      sourceSize: CGSize(width: 1920, height: 1080),
      in: CGSize(width: 1080, height: 1080)
    )

    XCTAssertEqual(rect.origin.x, 0, accuracy: 0.0001)
    XCTAssertEqual(rect.origin.y, 236.25, accuracy: 0.0001)
    XCTAssertEqual(rect.width, 1080, accuracy: 0.0001)
    XCTAssertEqual(rect.height, 607.5, accuracy: 0.0001)
  }

  func testExportSettingsExportSize_handlesPercentAspectAndCustomPresets() {
    let naturalSize = CGSize(width: 1920, height: 1080)

    var settings = ExportSettings()
    XCTAssertEqual(settings.exportSize(from: naturalSize), naturalSize)

    settings.dimensionPreset = .percent50
    XCTAssertEqual(settings.exportSize(from: naturalSize), CGSize(width: 960, height: 540))

    settings.dimensionPreset = .ratio1x1
    XCTAssertEqual(settings.exportSize(from: naturalSize), CGSize(width: 1080, height: 1080))

    settings.dimensionPreset = .ratio3x4
    XCTAssertEqual(settings.exportSize(from: naturalSize), CGSize(width: 1080, height: 1440))

    settings.dimensionPreset = .ratio2x3
    XCTAssertEqual(settings.exportSize(from: naturalSize), CGSize(width: 1080, height: 1620))

    XCTAssertTrue(ExportDimensionPreset.aspectRatioPresets.contains(.ratio3x4))
    XCTAssertTrue(ExportDimensionPreset.aspectRatioPresets.contains(.ratio2x3))

    settings.dimensionPreset = .custom
    settings.customWidth = 1001
    settings.customHeight = 563
    XCTAssertEqual(settings.exportSize(from: naturalSize), CGSize(width: 1000, height: 562))
  }

  func testExportSettingsAspectRatioStringAndContentRect() {
    var settings = ExportSettings()
    settings.dimensionPreset = .ratio1x1

    XCTAssertEqual(settings.aspectRatioString(from: CGSize(width: 1920, height: 1080)), "1:1")

    let contentRect = settings.videoContentRect(from: CGSize(width: 1920, height: 1080))
    XCTAssertEqual(contentRect.origin.y, 236.25, accuracy: 0.0001)
    XCTAssertEqual(contentRect.width, 1080, accuracy: 0.0001)
    XCTAssertEqual(contentRect.height, 607.5, accuracy: 0.0001)
  }

  func testExportSettingsAudioModes() {
    var settings = ExportSettings()
    settings.audioMode = .keep
    settings.audioVolume = 0.25
    settings.systemAudioVolume = 0.5
    settings.microphoneAudioVolume = 1.5
    XCTAssertTrue(settings.shouldIncludeAudio)
    XCTAssertEqual(settings.effectiveVolume, 1)
    XCTAssertEqual(settings.effectiveVolume(for: .systemAudio), 1)
    XCTAssertEqual(settings.effectiveVolume(for: .microphone), 1)

    settings.audioMode = .mute
    XCTAssertFalse(settings.shouldIncludeAudio)
    XCTAssertEqual(settings.effectiveVolume, 0)
    XCTAssertEqual(settings.effectiveVolume(for: .systemAudio), 0)
    XCTAssertEqual(settings.effectiveVolume(for: .microphone), 0)

    settings.audioMode = .custom
    settings.audioVolume = 2.5
    XCTAssertTrue(settings.shouldIncludeAudio)
    XCTAssertEqual(settings.effectiveVolume, 2.0)
    XCTAssertEqual(settings.effectiveVolume(for: .systemAudio), 0.5)
    XCTAssertEqual(settings.effectiveVolume(for: .microphone), 1.5)
  }

  func testExportSettingsAudioTrackRolesUseSnapzyRecordingOrder() {
    XCTAssertEqual(VideoEditorAudioTrackRole.roles(forAudioTrackCount: 0), [])
    XCTAssertEqual(VideoEditorAudioTrackRole.roles(forAudioTrackCount: 1), [.mixed])
    XCTAssertEqual(
      VideoEditorAudioTrackRole.roles(forAudioTrackCount: 3),
      [.systemAudio, .microphone, .additional(3)]
    )
  }

  func testExportSettingsSetAudioVolumeClampsPerRole() {
    var settings = ExportSettings()
    settings.setAudioVolume(-0.25, for: .systemAudio)
    settings.setAudioVolume(2.5, for: .microphone)
    settings.setAudioVolume(0.75, for: .mixed)

    XCTAssertEqual(settings.audioVolume(for: .systemAudio), 0)
    XCTAssertEqual(settings.audioVolume(for: .microphone), 2)
    XCTAssertEqual(settings.audioVolume(for: .mixed), 0.75)
  }

  func testAudioMixFactoryBuildsPerRoleVolumeParameters() {
    let composition = AVMutableComposition()
    let systemTrack = composition.addMutableTrack(
      withMediaType: .audio,
      preferredTrackID: kCMPersistentTrackID_Invalid
    )
    let microphoneTrack = composition.addMutableTrack(
      withMediaType: .audio,
      preferredTrackID: kCMPersistentTrackID_Invalid
    )
    XCTAssertNotNil(systemTrack)
    XCTAssertNotNil(microphoneTrack)

    var settings = ExportSettings()
    settings.audioMode = .custom
    settings.systemAudioVolume = 0.25
    settings.microphoneAudioVolume = 1.5

    let mix = VideoEditorAudioMixFactory.makeAudioMix(
      for: [systemTrack, microphoneTrack].compactMap { $0 },
      settings: settings
    )

    XCTAssertEqual(mix?.inputParameters.count, 2)
    XCTAssertEqual(volume(at: mix?.inputParameters.first), 0.25, accuracy: 0.0001)
    XCTAssertEqual(volume(at: mix?.inputParameters.dropFirst().first), 1.5, accuracy: 0.0001)
  }

  func testAudioMixFactoryUsesExplicitTrackRolesWhenProvided() {
    let composition = AVMutableComposition()
    let track = composition.addMutableTrack(
      withMediaType: .audio,
      preferredTrackID: kCMPersistentTrackID_Invalid
    )
    XCTAssertNotNil(track)

    var settings = ExportSettings()
    settings.audioMode = .custom
    settings.audioVolume = 1
    settings.microphoneAudioVolume = 0.3

    let mix = VideoEditorAudioMixFactory.makeAudioMix(
      for: [track].compactMap { $0 },
      settings: settings,
      roles: [.microphone]
    )

    XCTAssertEqual(mix?.inputParameters.count, 1)
    XCTAssertEqual(volume(at: mix?.inputParameters.first), 0.3, accuracy: 0.0001)
  }

  func testAudioMixFactoryIgnoresNonCustomModes() {
    let composition = AVMutableComposition()
    let track = composition.addMutableTrack(
      withMediaType: .audio,
      preferredTrackID: kCMPersistentTrackID_Invalid
    )
    XCTAssertNotNil(track)

    var settings = ExportSettings()
    settings.audioMode = .keep
    XCTAssertNil(VideoEditorAudioMixFactory.makeAudioMix(for: [track].compactMap { $0 }, settings: settings))

    settings.audioMode = .mute
    XCTAssertNil(VideoEditorAudioMixFactory.makeAudioMix(for: [track].compactMap { $0 }, settings: settings))
  }

  func testZoomSegmentClampsAndFormatsValues() {
    let segment = ZoomSegment(
      startTime: -5,
      duration: 100,
      zoomLevel: 9,
      zoomCenter: CGPoint(x: -1, y: 2),
      zoomType: .auto,
      followSpeed: 99,
      focusMargin: -5
    )

    XCTAssertEqual(segment.startTime, 0)
    XCTAssertEqual(segment.duration, ZoomSegment.maxDuration)
    XCTAssertEqual(segment.zoomLevel, ZoomSegment.maxZoomLevel)
    XCTAssertEqual(segment.zoomCenter, .init(x: 0, y: 1))
    XCTAssertEqual(segment.followSpeed, AutoFocusSettings.followSpeedRange.upperBound)
    XCTAssertEqual(segment.focusMargin, AutoFocusSettings.focusMarginRange.lowerBound)
    XCTAssertEqual(segment.formattedZoomLevel, "4x")
    XCTAssertEqual(segment.formattedDuration, "30s")
    XCTAssertTrue(segment.isAutoMode)
  }

  func testZoomSegmentCenteredAndClampedToVideoDuration() {
    let centered = ZoomSegment.centered(at: 1, duration: 4, zoomLevel: 1.5)
    XCTAssertEqual(centered.startTime, 0)
    XCTAssertEqual(centered.formattedZoomLevel, "1.5x")
    XCTAssertEqual(centered.formattedDuration, "4s")

    let clamped = ZoomSegment(startTime: 9, duration: 5).clamped(to: 10)
    XCTAssertEqual(clamped.startTime, 9)
    XCTAssertEqual(clamped.duration, 1)
  }

  private func volume(at params: AVAudioMixInputParameters?) -> Float {
    guard let params else { return -1 }
    var startVolume: Float = -1
    var endVolume: Float = -1
    var timeRange = CMTimeRange.invalid
    XCTAssertTrue(
      params.getVolumeRamp(
        for: .zero,
        startVolume: &startVolume,
        endVolume: &endVolume,
        timeRange: &timeRange
      )
    )
    XCTAssertEqual(startVolume, endVolume, accuracy: 0.0001)
    return startVolume
  }
}
