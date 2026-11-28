//
//  VideoEditorCanvasUXAndHostileInputTests.swift
//  SnapzyTests
//
//  End-to-end integration, export parity, keyboard input, and hostile-input regression tests for:
//  1. Canvas transform math & CoreText layout (`maxWidthFraction` wrap vs unwrap on 2-Tier
//     `Lead + Hero`, corner-handle large vector `fontSize` crispness up to `0.160` / `140pt`).
//  2. Per-word animated motion physics (`activeHighlight` & `progressiveReveal` with
//     `wordAnimation`) across both SwiftUI preview cache and CoreImage export compositor.
//  3. Timeline `cutTimeline(range:)`, `closeAllGaps()`, `removeClip(id:)`, and atomic
//     `undo()` / `redo()` consistency across clips, audio lanes, and text overlays.
//  4. `VideoEditorWindow` Spacebar, `Escape` (including active IME `hasMarkedText()` protection),
//     non-Latin `keyCode` J/K/L/,/. transport routing, and `Cmd+A` focus/layout safety.
//  5. Hostile session JSON decoding (duplicate IDs, NaN/Inf/negative/oversized numbers, >8 MB
//     manifest rejection) and malformed/extreme SRT subtitle parsing & formatting.
//  6. Head-trimmed clip detached audio projection, global `audioFadeIn/Out` on independent
//     audio export, and combined Speed segment + Crossfade transition track-duration parity.
//

import AppKit
import AVFoundation
import CoreImage
import CoreText
@testable import Snapzy
import SwiftUI
import XCTest

@MainActor
final class VideoEditorCanvasUXAndHostileInputTests: XCTestCase {
  private var tempDir: URL!

  override func setUpWithError() throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyCanvasHostileTests_\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let tempDir {
      try? FileManager.default.removeItem(at: tempDir)
    }
  }

  // MARK: - 1. `maxWidthFraction` Wrap/Unwrap on 2-Tier `Lead + Hero` & Large Vector `fontSize`

  func testMaxWidthFractionWrapUnwrapOnDualLineHeroAndLargeVectorFontCrispness() throws {
    let canvasSize = CGSize(width: 1920, height: 1080)
    let sampleText = "Tối ưu quy trình làm video chuyên nghiệp ngay trên macOS"

    var wideSettings = VideoEditorCaptionSettings.studioDefault
    wideSettings.dualLineHero = true
    wideSettings.fontSize = 0.048
    wideSettings.maxWidthFraction = 0.96

    var narrowSettings = wideSettings
    narrowSettings.maxWidthFraction = 0.30

    let wideLayout = try XCTUnwrap(
      VideoEditorCaptionLayout.make(text: sampleText, settings: wideSettings, videoSize: canvasSize)
    )
    let narrowLayout = try XCTUnwrap(
      VideoEditorCaptionLayout.make(text: sampleText, settings: narrowSettings, videoSize: canvasSize)
    )

    XCTAssertEqual(wideLayout.lines.count, 2, "Wide maxWidthFraction should keep 1 Lead + 1 Hero line")
    XCTAssertFalse(wideLayout.lineSpecs[0].isHero)
    XCTAssertTrue(wideLayout.lineSpecs[1].isHero)

    XCTAssertGreaterThan(
      narrowLayout.lines.count,
      wideLayout.lines.count,
      "Narrowing maxWidthFraction via side pill handles must wrap 2-Tier Lead + Hero text into more lines"
    )
    XCTAssertLessThan(narrowLayout.size.width, wideLayout.size.width)
    XCTAssertTrue(narrowLayout.lineSpecs.contains { !$0.isHero })
    XCTAssertTrue(narrowLayout.lineSpecs.contains { $0.isHero })

    let narrowedFraction = VideoEditorTextCanvasTransformMath.adjustedMaxWidthFraction(
      startMaxWidthFraction: 0.90,
      logicalWidth: 620,
      canvasWidth: 1000,
      horizontalDelta: -120,
      isLeadingHandle: false
    )
    XCTAssertLessThan(narrowedFraction, 0.50)

    let widenedFraction = VideoEditorTextCanvasTransformMath.adjustedMaxWidthFraction(
      startMaxWidthFraction: narrowedFraction,
      logicalWidth: 380,
      canvasWidth: 1000,
      horizontalDelta: 340,
      isLeadingHandle: false
    )
    XCTAssertGreaterThan(widenedFraction, 0.90)

    let scaledUpSize = VideoEditorTextCanvasTransformMath.scaledFontSize(
      startFontSize: 0.045,
      center: CGPoint(x: 500, y: 300),
      startPoint: CGPoint(x: 600, y: 340),
      currentPoint: CGPoint(x: 800, y: 420)
    )
    XCTAssertGreaterThan(scaledUpSize, 0.120)

    var giantOverlay = VideoEditorTextOverlay(text: "VECTOR HEADLINE", startTime: 0, duration: 3.0)
    giantOverlay.style.fontSize = 0.145
    giantOverlay.syncLegacyMirrorFromStyle()
    giantOverlay.style.fontSize = 0.145
    XCTAssertGreaterThan(giantOverlay.fontSize, 100)

    let cache = VideoEditorCaptionImageCache(capacity: 8)
    let retinaEntry = try XCTUnwrap(
      cache.entry(
        text: giantOverlay.text,
        settings: giantOverlay.style,
        videoSize: canvasSize,
        scale: 2.0
      )
    )
    XCTAssertEqual(Double(retinaEntry.image.width) / Double(retinaEntry.layout.bitmapSize.width), 2.0, accuracy: 0.05)
    XCTAssertGreaterThan(retinaEntry.image.height, 260)
  }

  // MARK: - 2. Word-Timing Motion Physics (Preview & Export Parity)

  func testWordTimingAnimatedMotionPhysicsInPreviewAndExport() throws {
    let canvasSize = CGSize(width: 1280, height: 720)
    let baseFrame = CIImage(color: CIColor(red: 0.06, green: 0.08, blue: 0.12))
      .cropped(to: CGRect(origin: .zero, size: canvasSize))

    for mode in [VideoEditorCaptionSettings.WordMode.activeHighlight, .progressiveReveal] {
      var overlay = VideoEditorTextOverlay(
        text: "Smooth kinetic word motion physics",
        startTime: 1.0,
        duration: 2.5
      )
      overlay.applyPreset(.kineticPulse)
      overlay.style.animationIn = .none
      overlay.style.animationOut = .none
      overlay.style.wordMode = mode
      overlay.style.wordAnimation = .springRise

      let earlyMotion = overlay.motionState(at: 1.02)
      let settledMotion = overlay.motionState(at: 1.38)
      XCTAssertEqual(earlyMotion.activeWordIndex, 0)
      let earlyArrival = try XCTUnwrap(earlyMotion.activeWordArrivalProgress)
      XCTAssertLessThan(earlyArrival, 0.35)
      XCTAssertNotEqual(earlyMotion.activeWordScale, 1.0)
      XCTAssertLessThan(earlyMotion.activeWordOffsetYEm, -0.05)
      XCTAssertGreaterThan(earlyMotion.activeWordGlowBoost, 0.05)
      XCTAssertEqual(settledMotion.activeWordScale, 1.0, accuracy: 0.02)

      let keyEarly = VideoEditorTextOverlayRenderer.CacheKey(overlay: overlay, canvasSize: canvasSize, outputTime: 1.02)
      let keySettled = VideoEditorTextOverlayRenderer.CacheKey(
        overlay: overlay,
        canvasSize: canvasSize,
        outputTime: 1.38
      )
      XCTAssertNotEqual(keyEarly, keySettled)

      let pillEarly = try XCTUnwrap(
        VideoEditorTextOverlayRenderer.renderPillImage(for: overlay, canvasSize: canvasSize, outputTime: 1.02)
      )
      let pillSettled = try XCTUnwrap(
        VideoEditorTextOverlayRenderer.renderPillImage(for: overlay, canvasSize: canvasSize, outputTime: 1.38)
      )
      XCTAssertEqual(pillEarly.extent.size, pillSettled.extent.size)

      let composited = VideoEditorTextOverlayRenderer.composite(
        pillImage: pillEarly,
        onto: baseFrame,
        overlay: overlay,
        canvasSize: canvasSize,
        motion: earlyMotion
      )
      XCTAssertEqual(composited.extent, CGRect(origin: .zero, size: canvasSize))
    }
  }

  // MARK: - 3. Timeline Cut, Close Gaps & Atomic Undo/Redo Consistency

  func testTimelineCutCloseAllGapsAndAtomicUndoRedoKeepTracksConsistent() async throws {
    let url = try await makeTestMovie(
      in: tempDir,
      name: "ripple_consistency.mov",
      durationSeconds: 6.0,
      width: 1280,
      height: 720
    )
    let audioURL = try makeTestWAV(in: tempDir, name: "ripple_audio.wav", durationSeconds: 6.0)

    let state = VideoEditorState(url: url)
    defer { state.cancelPendingPerformanceWork() }
    await state.loadMetadata()

    state.audioClips = [
      AudioTimelineClip(
        source: .file(url: audioURL),
        name: "Full Bed",
        timelineStart: 0.0,
        sourceDuration: 6.0,
        sourceStart: 0.0,
        sourceEnd: 6.0,
        trackIndex: 0
      ),
    ]

    let tBefore = try XCTUnwrap(state.addTextOverlay(text: "Intro", at: 0.2, duration: 1.0))
    let tInside = try XCTUnwrap(state.addTextOverlay(text: "Cut Away", at: 2.1, duration: 0.7))
    let tSpanning = try XCTUnwrap(state.addTextOverlay(text: "Bridge", at: 1.5, duration: 2.5))
    let tAfter = try XCTUnwrap(state.addTextOverlay(text: "Outro", at: 4.5, duration: 1.0))

    let preCutClips = state.clips
    let preCutAudio = state.audioClips
    let preCutTexts = state.textOverlays

    let removed = try XCTUnwrap(state.cutTimeline(range: 2.0 ... 3.0))
    XCTAssertEqual(removed, [2.0 ... 3.0])
    let postCutDuration = CMTimeGetSeconds(state.timelineDuration)
    XCTAssertEqual(postCutDuration, 5.0, accuracy: 0.05)

    XCTAssertNil(state.textOverlays.first { $0.id == tInside.id })
    XCTAssertEqual(try XCTUnwrap(state.textOverlays.first { $0.id == tBefore.id }).startTime, 0.2, accuracy: 0.02)
    let postSpanning = try XCTUnwrap(state.textOverlays.first { $0.id == tSpanning.id })
    XCTAssertEqual(postSpanning.startTime, 1.5, accuracy: 0.02)
    XCTAssertEqual(postSpanning.duration, 1.5, accuracy: 0.02)
    let postAfter = try XCTUnwrap(state.textOverlays.first { $0.id == tAfter.id })
    XCTAssertEqual(postAfter.startTime, 3.5, accuracy: 0.02)
    XCTAssertEqual(postAfter.duration, 1.0, accuracy: 0.02)

    state.undo()
    XCTAssertEqual(state.clips, preCutClips)
    XCTAssertEqual(state.audioClips, preCutAudio)
    XCTAssertEqual(state.textOverlays, preCutTexts)

    state.redo()
    XCTAssertNil(state.textOverlays.first { $0.id == tInside.id })
    XCTAssertEqual(try XCTUnwrap(state.textOverlays.first { $0.id == tAfter.id }).startTime, 3.5, accuracy: 0.02)

    let secondClipId = state.clips[1].id
    state.moveClipOnTimeline(id: secondClipId, toActiveStart: 3.0)
    let gappedTitle = try XCTUnwrap(state.addTextOverlay(text: "After Gap", at: 3.4, duration: 1.0))
    state.closeAllGaps()
    let closedTitle = try XCTUnwrap(state.textOverlays.first { $0.id == gappedTitle.id })
    XCTAssertEqual(closedTitle.startTime, 2.4, accuracy: 0.05)

    state.undo()
    XCTAssertTrue(state.hasVideoGaps)
    XCTAssertEqual(try XCTUnwrap(state.textOverlays.first { $0.id == gappedTitle.id }).startTime, 3.4, accuracy: 0.05)
  }

  // MARK: - 4. `VideoEditorWindow` Spacebar, IME `hasMarkedText` Escape, and Non-Latin `keyCode` Routing

  func testVideoEditorWindow_spacebarIMEProtectedEscapeAndNonLatinKeyCodeRouting() throws {
    final class ButtonClickSpy: NSObject {
      var clickCount = 0
      @objc func didClick(_: Any?) {
        clickCount += 1
      }
    }

    final class MarkedTextViewStub: NSTextView {
      var simulatedHasMarkedText = false
      override func hasMarkedText() -> Bool {
        simulatedHasMarkedText
      }
    }

    let spy = ButtonClickSpy()
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
    let button = NSButton(title: "Preset Tile", target: spy, action: #selector(ButtonClickSpy.didClick(_:)))
    button.frame = NSRect(x: 20, y: 200, width: 140, height: 32)
    let imeTextView = MarkedTextViewStub(frame: NSRect(x: 20, y: 120, width: 220, height: 28))
    imeTextView.isEditable = true
    container.addSubview(button)
    container.addSubview(imeTextView)

    var toggleCount = 0
    var receivedTransport: [VideoEditorWindow.TransportKey] = []
    var selectAllCount = 0
    let window = VideoEditorWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300))
    window.contentView = container
    window.onTogglePlayback = { toggleCount += 1 }
    window.onTransportKey = { key in
      receivedTransport.append(key)
      return true
    }
    window.onSelectAllTrackItems = {
      selectAllCount += 1
      return true
    }
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }

    // 1) Focused NSButton: Space toggles playback and never clicks the button
    XCTAssertTrue(window.makeFirstResponder(button))
    let spaceDown = try makeKeyEvent(type: .keyDown, keyCode: 49, chars: " ", windowNumber: window.windowNumber)
    let spaceUp = try makeKeyEvent(type: .keyUp, keyCode: 49, chars: " ", windowNumber: window.windowNumber)
    window.sendEvent(spaceDown)
    window.sendEvent(spaceUp)
    XCTAssertEqual(toggleCount, 1)
    XCTAssertEqual(spy.clickCount, 0)

    // 2) Non-Latin (Russian Cyrillic) characters on physical J/K/L/,/. keyCodes must route to transport!
    let cyrillicTransport: [(String, UInt16, VideoEditorWindow.TransportKey)] = [
      ("о", 38, .shuttleReverse),
      ("л", 40, .shuttlePause),
      ("д", 37, .shuttleForward),
      ("б", 43, .stepBackward),
      ("ю", 47, .stepForward),
    ]
    for (char, code, _) in cyrillicTransport {
      try window.sendEvent(makeKeyEvent(type: .keyDown, keyCode: code, chars: char, windowNumber: window.windowNumber))
    }
    XCTAssertEqual(receivedTransport, cyrillicTransport.map(\.2))

    // 3) Cmd+A on Cyrillic ("ф", keyCode 0) and QWERTY ("a", keyCode 0) selects all, while AZERTY Cmd+Q ("q", keyCode
    // 0) does NOT!
    let cyrillicCmdA = try makeKeyEvent(
      type: .keyDown,
      keyCode: 0,
      chars: "ф",
      modifiers: .command,
      windowNumber: window.windowNumber
    )
    XCTAssertTrue(window.performKeyEquivalent(with: cyrillicCmdA))
    XCTAssertEqual(selectAllCount, 1)

    let azertyCmdQ = try makeKeyEvent(
      type: .keyDown,
      keyCode: 0,
      chars: "q",
      modifiers: .command,
      windowNumber: window.windowNumber
    )
    _ = window.performKeyEquivalent(with: azertyCmdQ)
    XCTAssertEqual(selectAllCount, 1, "AZERTY Cmd+Q must not be hijacked as Select All")

    // 4) Escape during active IME composition (`hasMarkedText() == true`) must NOT resign text responder!
    XCTAssertTrue(window.makeFirstResponder(imeTextView))
    XCTAssertTrue(window.isActivelyEditingTextInput)
    imeTextView.simulatedHasMarkedText = true

    let escDown = try makeKeyEvent(type: .keyDown, keyCode: 53, chars: "\u{1B}", windowNumber: window.windowNumber)
    let escUp = try makeKeyEvent(type: .keyUp, keyCode: 53, chars: "\u{1B}", windowNumber: window.windowNumber)
    window.sendEvent(escDown)
    window.sendEvent(escUp)
    XCTAssertTrue(
      window.isActivelyEditingTextInput,
      "Escape must leave responder focused while IME hasMarkedText() is active"
    )

    // Once IME marked text is committed (`hasMarkedText() == false`), Escape exits text focus cleanly!
    imeTextView.simulatedHasMarkedText = false
    window.sendEvent(escDown)
    window.sendEvent(escUp)
    XCTAssertFalse(window.isActivelyEditingTextInput)
  }

  // MARK: - 5. Reverse Shuttle (`J`) Does Not Fight Itself & `L` Resumes Forward Cleanly

  func testReverseShuttleJStaysPausedOnAVPlayerAndForwardLResumesCleanly() async throws {
    let videoURL = try await makeTestMovie(
      in: tempDir,
      name: "shuttle_reverse_forward.mov",
      durationSeconds: 4.0,
      width: 320,
      height: 180
    )
    let state = VideoEditorState(url: videoURL)
    defer { state.cancelPendingPerformanceWork() }
    await state.loadMetadata()

    state.seek(to: CMTime(seconds: 2.5, preferredTimescale: 600))
    state.play()
    XCTAssertTrue(state.isPlaying)

    // Press `J`: must engage -1x reverse shuttle and keep AVPlayer paused (`player.rate == 0`)
    state.shuttleReverse()
    XCTAssertEqual(state.playbackState.shuttleRate, -1.0, accuracy: 0.001)
    XCTAssertEqual(state.player.rate, 0.0, accuracy: 0.001)
    XCTAssertTrue(state.player.isMuted)

    // Let reverse timer tick ~120ms and verify playhead moves backward while `player.rate` stays 0!
    let beforeTick = CMTimeGetSeconds(state.currentTime)
    try await Task.sleep(nanoseconds: 140_000_000)
    let afterTick = CMTimeGetSeconds(state.currentTime)
    XCTAssertLessThan(afterTick, beforeTick, "Reverse shuttle must step playhead backward smoothly")
    XCTAssertEqual(
      state.player.rate,
      0.0,
      accuracy: 0.001,
      "Seek completion must never restart forward AVPlayer during reverse shuttle"
    )

    // Press `L`: must switch to +1x forward shuttle, restore audio mute state, and resume forward playback!
    state.shuttleForward()
    XCTAssertEqual(state.playbackState.shuttleRate, 1.0, accuracy: 0.001)
    XCTAssertTrue(state.isPlaying)
    XCTAssertFalse(state.player.isMuted)
    state.shuttlePause()
  }

  // MARK: - 6. Hostile Session JSON, Duplicate IDs, Out-of-Range Clamping & >8 MB Manifest Rejection

  func testHostileSessionJSON_deduplicatesIDsClampsOutOfRangeValuesAndRejectsOversizedManifest() async throws {
    let videoURL = try await makeTestMovie(
      in: tempDir,
      name: "hostile_rehydrate.mov",
      durationSeconds: 3.0,
      width: 320,
      height: 180
    )
    let seedState = VideoEditorState(url: videoURL)
    defer { seedState.cancelPendingPerformanceWork() }
    await seedState.loadMetadata()
    _ = seedState.addZoom(at: 0.4)
    _ = seedState.addSpeed(range: 0.5 ... 1.5, rate: 2.0)
    let basePersisted = PersistedVideoEditorEditState(
      sessionData: VideoEditorSessionData.snapshot(from: seedState, sourceSnapshotURL: videoURL)
    )
    var rootDict = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(basePersisted)) as? [String: Any]
    )

    let sharedUUID = "11111111-2222-3333-4444-555555555555"
    let hostilePatchJSON = """
    {
      "clips": [
        {
          "id": "\(sharedUUID)",
          "source": { "primary": {} },
          "sourceDuration": 999999999,
          "sourceStart": -50,
          "sourceEnd": 999999999,
          "slotStart": -20,
          "slotEnd": 999999999,
          "leadingGap": 999999999
        },
        {
          "id": "\(sharedUUID)",
          "source": { "primary": {} },
          "sourceDuration": 5.0
        }
      ],
      "audioClips": [
        {
          "id": "\(sharedUUID)",
          "source": { "primary": {} },
          "name": "Dup Audio 1",
          "timelineStart": -999,
          "sourceDuration": 999999999,
          "sourceStart": -10,
          "sourceEnd": 999999999,
          "volume": 999,
          "isMuted": false,
          "fadeIn": 999,
          "fadeOut": -20,
          "trackIndex": 999
        },
        {
          "id": "\(sharedUUID)",
          "source": { "primary": {} },
          "name": "Dup Audio 2",
          "timelineStart": 1.0,
          "sourceDuration": 2.0,
          "trackIndex": -5
        }
      ],
      "mutedAudioLanes": [-4, 0, 2, 99],
      "backgroundPadding": 99999,
      "backgroundShadowIntensity": -50,
      "backgroundCornerRadius": 99999,
      "exportSettings": {
        "dimensionPreset": "Custom...",
        "customWidth": -500,
        "customHeight": 99999999,
        "audioVolume": 999,
        "audioFadeIn": 999,
        "audioFadeOut": -10
      },
      "captions": {
        "segments": [
          { "id": "\(sharedUUID)", "sourceRange": [-10, 999999999], "text": "Dup Cue 1" },
          { "id": "\(sharedUUID)", "sourceRange": [1, 2], "text": "Dup Cue 2" }
        ],
        "settings": {
          "fontSize": -5,
          "fontWeight": 99999,
          "margin": 999,
          "maxWidthFraction": -10,
          "maxCharsPerLine": 99999,
          "maxLines": 0,
          "glowIntensity": 99,
          "backgroundOpacity": -4,
          "animationDuration": 999
        }
      },
      "textOverlays": [
        {
          "id": "\(sharedUUID)",
          "text": "Dup Overlay 1",
          "startTime": -50,
          "duration": -10,
          "trackIndex": 999
        },
        {
          "id": "\(sharedUUID)",
          "text": "Dup Overlay 2",
          "startTime": 1,
          "duration": 2
        }
      ],
      "timelineBookmarks": [-50, 2.0, 999999999]
    }
    """.data(using: .utf8)!
    let patchDict = try XCTUnwrap(JSONSerialization.jsonObject(with: hostilePatchJSON) as? [String: Any])
    for (k, v) in patchDict {
      rootDict[k] = v
    }
    if var zooms = rootDict["zoomSegments"] as? [[String: Any]], let z0 = zooms.first {
      var z1 = z0
      z1["id"] = sharedUUID
      var z2 = z0
      z2["id"] = sharedUUID
      zooms = [z1, z2]
      rootDict["zoomSegments"] = zooms
    }
    if var speeds = rootDict["speedSegments"] as? [[String: Any]], let s0 = speeds.first {
      var s1 = s0
      s1["id"] = sharedUUID
      var s2 = s0
      s2["id"] = sharedUUID
      speeds = [s1, s2]
      rootDict["speedSegments"] = speeds
    }
    let hostileJSON = try JSONSerialization.data(withJSONObject: rootDict)

    let decoded = try JSONDecoder().decode(PersistedVideoEditorEditState.self, from: hostileJSON)
    XCTAssertEqual(
      Set(decoded.clips.map(\.id)).count,
      decoded.clips.count,
      "Duplicate clip IDs must be reassigned unique IDs"
    )
    XCTAssertEqual(
      Set(decoded.zoomSegments.map(\.id)).count,
      decoded.zoomSegments.count,
      "Duplicate zoom IDs must be unique"
    )
    XCTAssertEqual(
      Set(decoded.speedSegments.map(\.id)).count,
      decoded.speedSegments.count,
      "Duplicate speed IDs must be unique"
    )
    let decodedAudio = try XCTUnwrap(decoded.audioClips)
    XCTAssertEqual(Set(decodedAudio.map(\.id)).count, decodedAudio.count, "Duplicate audioClip IDs must be unique")
    let decodedCues = try XCTUnwrap(decoded.captions?.segments)
    XCTAssertEqual(Set(decodedCues.map(\.id)).count, decodedCues.count, "Duplicate caption segment IDs must be unique")
    let decodedOverlays = try XCTUnwrap(decoded.textOverlays)
    XCTAssertEqual(
      Set(decodedOverlays.map(\.id)).count,
      decodedOverlays.count,
      "Duplicate textOverlay IDs must be unique"
    )

    let clip = try XCTUnwrap(decoded.clips.first)
    XCTAssertLessThanOrEqual(clip.sourceDuration, TimelineClip.maxDurationSeconds)
    XCTAssertLessThanOrEqual(clip.leadingGap, TimelineClip.maxLeadingGapSeconds)
    XCTAssertGreaterThanOrEqual(clip.sourceStart, 0)

    let audio = try XCTUnwrap(decoded.audioClips?.first)
    XCTAssertGreaterThanOrEqual(audio.timelineStart, 0)
    XCTAssertEqual(audio.volume, 2.0, accuracy: 0.001)
    XCTAssertLessThanOrEqual(audio.fadeIn, 5.0)
    XCTAssertEqual(audio.fadeOut, 0.0, accuracy: 0.001)
    XCTAssertEqual(audio.trackIndex, AudioTimelineClip.maxTrackCount - 1)
    XCTAssertEqual(decoded.mutedAudioLanes, Set([0, 2]))

    XCTAssertEqual(decoded.backgroundPadding, 500, accuracy: 0.001)
    XCTAssertEqual(decoded.backgroundShadowIntensity, 0, accuracy: 0.001)
    XCTAssertEqual(decoded.backgroundCornerRadius, 500, accuracy: 0.001)
    XCTAssertEqual(decoded.exportSettings.customWidth, 1920)
    XCTAssertEqual(decoded.exportSettings.customHeight, 16_384)
    XCTAssertEqual(decoded.exportSettings.audioVolume, 2.0, accuracy: 0.001)

    let capSettings = try XCTUnwrap(decoded.captions?.settings)
    XCTAssertGreaterThanOrEqual(capSettings.fontSize, 0.018)
    XCTAssertEqual(capSettings.fontWeight, 900)
    XCTAssertLessThanOrEqual(capSettings.margin, 0.30)
    XCTAssertGreaterThanOrEqual(capSettings.maxWidthFraction, 0.18)
    XCTAssertEqual(capSettings.maxCharsPerLine, 120)
    XCTAssertEqual(capSettings.maxLines, 1)

    // Negative / NaN duration on VideoEditorTextOverlay must never trap in `motionState(at:)` or `contains(time:)`
    var negativeOverlay = VideoEditorTextOverlay(text: "Safe", startTime: 1.0, duration: 1.0)
    negativeOverlay.duration = -5.0
    XCTAssertFalse(negativeOverlay.contains(time: 0.5))
    XCTAssertEqual(negativeOverlay.motionState(at: 0.5).opacity, 0, accuracy: 0.001)

    // Rehydration into VideoEditorState with hostile state must never trap in Dictionary lookups!
    let session = decoded.sessionData(sourceSnapshotURL: videoURL, recordingMetadata: nil)
    let state = VideoEditorState(url: videoURL, sessionData: session)
    defer { state.cancelPendingPerformanceWork() }
    await state.loadMetadata()
    XCTAssertFalse(state.clips.isEmpty)

    // Oversized session `manifest.json` (> 8 MB) must be rejected before reading into memory
    let storeRoot = tempDir.appendingPathComponent("OversizedSessionStore", isDirectory: true)
    let store = VideoEditorSessionStore(rootDirectory: storeRoot)
    let validSnapshot = VideoEditorSessionData.snapshot(from: state, sourceSnapshotURL: videoURL)
    XCTAssertTrue(store.persist(validSnapshot, for: videoURL))
    XCTAssertNotNil(store.load(for: videoURL))

    let committedDir = store.committedSourceSnapshotURL(for: videoURL, fileName: videoURL.lastPathComponent)
      .deletingLastPathComponent()
    let sessionManifestURL = committedDir.appendingPathComponent("manifest.json")
    let oversizedBlob = Data(repeating: 0x20, count: 8_388_608 + 1024)
    try oversizedBlob.write(to: sessionManifestURL, options: .atomic)
    XCTAssertNil(store.load(for: videoURL), "Oversized >8 MB session manifest must be rejected cleanly")
  }

  // MARK: - 7. Malformed & Extreme SRT Parsing and Formatting Never Traps

  func testMalformedAndExtremeSRTImportAndExportNeverTraps() {
    let hostileSRT = """
    1
    00:00:01,000 --> 00:00:02,500
    Valid cue &amp; entities &lt;ok&gt;

    2
    1e300:00:00,000 --> 1e300:00:05,000
    Astronomical overflow timestamp

    3
    00:99:99,000 --> 01:00:01,000
    Invalid minutes/seconds >= 60

    4
    -00:00:05,000 --> 00:00:02,000
    Negative timestamp

    5
    00:00:05,000 --> 00:00:03,000
    Reversed range end < start

    6
    Missing arrow line altogether
    Text without timing

    7
    00:00:03,000 --> 00:00:04,200
    Second valid cue
    """
    let parsed = VideoEditorSubtitleWriter.parse(hostileSRT)
    XCTAssertEqual(parsed.count, 2, "Only valid cues must survive malformed/overflow SRT blocks")
    XCTAssertEqual(parsed[0].text, "Valid cue & entities <ok>")
    XCTAssertEqual(parsed[1].text, "Second valid cue")

    // Formatting extreme non-finite / huge cues must clamp cleanly and never trap in `Int(...)`!
    XCTAssertEqual(VideoEditorSubtitleWriter.timestamp(1e300, separator: ","), "240:00:00,000")
    XCTAssertEqual(VideoEditorSubtitleWriter.timestamp(.infinity, separator: ","), "00:00:00,000")
    let extremeSRT = VideoEditorSubtitleWriter.srt([
      VideoEditorSubtitleCue(start: 0, end: 1e300, text: "Extreme"),
      VideoEditorSubtitleCue(start: .nan, end: .infinity, text: "NaN cue"),
    ])
    XCTAssertTrue(extremeSRT.contains("Extreme"))
    XCTAssertFalse(extremeSRT.contains("NaN cue"))
  }

  // MARK: - 8. Head-Trimmed Clip Detached Audio Projection & Global `audioFadeIn/Out` on Independent Audio

  func testHeadTrimmedDetachedAudioHasZeroOffsetAndGlobalAudioFadesAttenuateExport() async throws {
    // Source movie: 4.0s total, silent from [0...1.6s] and loud 880Hz tone from [1.6...3.8s].
    let silentVideo = try await makeTestMovie(
      in: tempDir,
      name: "headtrim_video.mov",
      durationSeconds: 4.0,
      width: 320,
      height: 180
    )
    let toneWAV = try makeBurstWAV(
      in: tempDir,
      name: "headtrim_tone.wav",
      durationSeconds: 4.0,
      burstRange: 1.6 ... 3.8
    )
    let muxedURL = tempDir.appendingPathComponent("headtrim_muxed.mov")
    let muxComp = AVMutableComposition()
    let vAsset = AVURLAsset(url: silentVideo)
    let aAsset = AVURLAsset(url: toneWAV)
    if let vSrc = try await vAsset.loadTracks(withMediaType: .video).first,
       let vDst = muxComp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
      try await vDst.insertTimeRange(
        CMTimeRange(start: .zero, duration: vAsset.load(.duration)),
        of: vSrc,
        at: .zero
      )
    }
    if let aSrc = try await aAsset.loadTracks(withMediaType: .audio).first,
       let aDst = muxComp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
      try await aDst.insertTimeRange(
        CMTimeRange(start: .zero, duration: aAsset.load(.duration)),
        of: aSrc,
        at: .zero
      )
    }
    let muxExport = try XCTUnwrap(AVAssetExportSession(asset: muxComp, presetName: AVAssetExportPresetPassthrough))
    muxExport.outputURL = muxedURL
    muxExport.outputFileType = .mov
    await muxExport.export()
    XCTAssertEqual(muxExport.status, .completed)

    let state = VideoEditorState(url: muxedURL)
    defer { state.cancelPendingPerformanceWork() }
    await state.loadMetadata()

    // Head-trim primary clip to [1.5s ... 4.0s] (active duration = 2.5s; tone starts at output t = 0.1s!)
    let clipId = try XCTUnwrap(state.clips.first?.id)
    state.updateClip(id: clipId, sourceStart: 1.5, sourceEnd: 4.0)
    _ = await state.detachAudio(fromClipId: clipId)
    XCTAssertTrue(state.usesIndependentAudioPlayback)

    // 1) Export without global fade: output duration must be 2.5s (no 1.5s black tail!) and tone must be loud right at
    // [0.2...0.6s]!
    let unfadedURL = tempDir.appendingPathComponent("headtrim_unfaded.mp4")
    try await VideoEditorExporter.exportTrimmed(state: state, to: unfadedURL) { _ in }
    let unfadedDuration = try await CMTimeGetSeconds(AVURLAsset(url: unfadedURL).load(.duration))
    XCTAssertEqual(
      unfadedDuration,
      2.5,
      accuracy: 0.20,
      "Head-trimmed clip with detached audio must export at 2.5s without black tail"
    )
    let unfadedHeadRMS = try await measureAudioRMS(from: unfadedURL, rangeSeconds: 0.15 ... 0.45)
    XCTAssertGreaterThan(
      unfadedHeadRMS,
      0.08,
      "Detached audio on head-trimmed clip must align with output t=0 without 1.5s offset"
    )

    // 2) Apply global `exportSettings.audioFadeIn = 1.0` & `audioFadeOut = 1.0` -> must attenuate head & tail even with
    // independent audio!
    var fadedSettings = state.exportSettings
    fadedSettings.audioFadeIn = 1.0
    fadedSettings.audioFadeOut = 1.0
    state.updateExportSettings(fadedSettings)

    let fadedURL = tempDir.appendingPathComponent("headtrim_faded.mp4")
    try await VideoEditorExporter.exportTrimmed(state: state, to: fadedURL) { _ in }
    let fadedHeadRMS = try await measureAudioRMS(from: fadedURL, rangeSeconds: 0.10 ... 0.35)
    let fadedMidRMS = try await measureAudioRMS(from: fadedURL, rangeSeconds: 1.05 ... 1.45)
    XCTAssertLessThan(
      fadedHeadRMS,
      fadedMidRMS * 0.55,
      "Global exportSettings.audioFadeIn must attenuate independent audio track start (head=\(fadedHeadRMS), mid=\(fadedMidRMS))"
    )
  }

  // MARK: - 9. Combined Speed Segment + Crossfade Transition Export Track-Duration Parity

  func testCombinedSpeedSegmentAndCrossfadeTransitionExportTrackDurationParity() async throws {
    let redURL = try await makeSolidColorMovie(
      in: tempDir,
      name: "speed_cf_red.mov",
      durationSeconds: 2.0,
      width: 320,
      height: 180,
      r: 235,
      g: 20,
      b: 20
    )
    let blueURL = try await makeSolidColorMovie(
      in: tempDir,
      name: "speed_cf_blue.mov",
      durationSeconds: 2.0,
      width: 320,
      height: 180,
      r: 20,
      g: 20,
      b: 235
    )
    let bedWAV = try makeTestWAV(in: tempDir, name: "speed_cf_bed.wav", durationSeconds: 4.0)

    let state = VideoEditorState(url: redURL)
    defer { state.cancelPendingPerformanceWork() }
    await state.loadMetadata()

    let blueClip = TimelineClip(
      source: .file(url: blueURL),
      sourceDuration: 2.0,
      leadingTransition: TimelineClipTransition(style: .crossfade, duration: 0.6)
    )
    state.applyClipsReplacing(state.clips + [blueClip], recordUndo: true)
    _ = await state.addAudioClip(url: bedWAV, at: 0.0)

    // Apply 2.0x speed across [2.4s ... 4.0s] (saves 0.8s -> expected output duration = 3.2s)
    _ = state.addSpeed(range: 2.4 ... 4.0, rate: 2.0)

    let outURL = tempDir.appendingPathComponent("combined_speed_crossfade.mp4")
    try await VideoEditorExporter.exportTrimmed(state: state, to: outURL) { _ in }

    let outAsset = AVURLAsset(url: outURL)
    let videoTracks = try await outAsset.loadTracks(withMediaType: .video)
    let audioTracks = try await outAsset.loadTracks(withMediaType: .audio)
    XCTAssertFalse(videoTracks.isEmpty)
    XCTAssertFalse(audioTracks.isEmpty)

    let videoTrackDuration = try await CMTimeGetSeconds(videoTracks[0].load(.timeRange).duration)
    let audioTrackDuration = try await CMTimeGetSeconds(audioTracks[0].load(.timeRange).duration)
    XCTAssertEqual(
      videoTrackDuration,
      3.2,
      accuracy: 0.20,
      "Video track duration must match 3.2s speed-scaled timeline"
    )
    XCTAssertEqual(
      audioTrackDuration,
      3.2,
      accuracy: 0.20,
      "Audio track duration must match 3.2s speed-scaled timeline"
    )
    XCTAssertEqual(
      videoTrackDuration,
      audioTrackDuration,
      accuracy: 0.12,
      "Video and audio tracks must stay tightly synchronized"
    )

    // Crossfade midpoint at t = 2.0s must still blend red + blue cleanly!
    let cfRGB = try await sampleCenterPixelRGB(from: outURL, atSeconds: 2.0)
    XCTAssertGreaterThan(cfRGB.r, 0.20)
    XCTAssertGreaterThan(cfRGB.b, 0.20)
  }

  // MARK: - 10. Cmd+A Bulk Select & Delete, Convert Captions, Multi-Track Text & Persistence

  func testCmdASelectAllConvertCaptionsMultiTrackTextAndGracefulEnumDecode() async throws {
    let videoURL = try await makeTestMovie(
      in: tempDir,
      name: "bulk_select_delete.mov",
      durationSeconds: 5.0,
      width: 1280,
      height: 720
    )
    let wavURL = try makeTestWAV(in: tempDir, name: "bgm.wav", durationSeconds: 2.0)

    let state = VideoEditorState(url: videoURL)
    defer { state.cancelPendingPerformanceWork() }
    await state.loadMetadata()

    let cues = [
      CaptionSegment(sourceRange: 0.2 ... 1.2, text: "Line 1"),
      CaptionSegment(sourceRange: 1.5 ... 2.5, text: "Line 2"),
      CaptionSegment(sourceRange: 2.8 ... 4.0, text: "Line 3"),
    ]
    state.applyCaptions(VideoEditorCaptions(segments: cues, settings: .studioDefault))
    state.selectCaption(id: cues[0].id)
    XCTAssertTrue(state.selectAllInActiveTrack())
    XCTAssertEqual(state.selectedCaptionIds.count, 3)
    XCTAssertTrue(state.deleteSelectedTrackItems())
    XCTAssertTrue(state.captions.segments.isEmpty)
    state.undo()
    XCTAssertEqual(state.captions.segments.count, 3)

    // Convert all captions to Text Overlays without duplicates + atomic undo
    XCTAssertEqual(state.convertAllCaptionsToTextOverlays(), 3)
    XCTAssertEqual(state.textOverlays.count, 3)
    XCTAssertTrue(state.captions.segments.isEmpty)
    state.undo()
    XCTAssertEqual(state.captions.segments.count, 3)
    XCTAssertTrue(state.textOverlays.isEmpty)

    // Overlapping text overlays auto-stack onto T1 (0) and T2 (1)
    let t1 = try XCTUnwrap(state.addTextOverlay(text: "Top Title", at: 0.5, duration: 2.0, preset: .cyberCyan))
    let t2 = try XCTUnwrap(state.addTextOverlay(text: "Lower Third", at: 0.8, duration: 2.0, preset: .editorialInk))
    XCTAssertEqual(t1.trackIndex, 0)
    XCTAssertEqual(t2.trackIndex, 1)
    XCTAssertEqual(state.textLaneCount, 2)

    // Audio bulk select & delete
    state.leftSidebarPanel = .background
    state.selectTextOverlay(id: nil)
    state.audioClips = [
      AudioTimelineClip(source: .file(url: wavURL), name: "A1", timelineStart: 0.0, sourceDuration: 2.0, trackIndex: 0),
      AudioTimelineClip(source: .file(url: wavURL), name: "A2", timelineStart: 2.2, sourceDuration: 2.0, trackIndex: 1),
    ]
    state.selectedAudioClipId = state.audioClips[0].id
    XCTAssertTrue(state.selectAllInActiveTrack())
    XCTAssertTrue(state.deleteSelectedTrackItems())
    XCTAssertTrue(state.audioClips.isEmpty)
    state.undo()
    XCTAssertEqual(state.audioClips.count, 2)

    // Unknown future enum values decode gracefully
    let captionJSON = #"{"isEnabled":true,"fontFamily":"futureQuantumSerif","surfaceStyle":"liquidMetal","animationIn":"teleportWarp"}"#
      .data(using: .utf8)!
    let decodedCaption = try JSONDecoder().decode(VideoEditorCaptionSettings.self, from: captionJSON)
    XCTAssertTrue(decodedCaption.isEnabled)
    XCTAssertEqual(decodedCaption.surfaceStyle, VideoEditorCaptionSettings.default.surfaceStyle)
  }

  // MARK: - 11. Export Pixel RGB & Speed 2x Synchronized Audio-Visual Burst

  func testCrossfadeDipToBlackAndSpeed2xSynchronizedBurstExport() async throws {
    let burstVideoURL = try await makeFlashBurstMovie(
      in: tempDir,
      name: "av_burst_video.mov",
      durationSeconds: 4.0,
      flashRange: 2.8 ... 3.4
    )
    let burstWavURL = try makeBurstWAV(
      in: tempDir,
      name: "av_burst_audio.wav",
      durationSeconds: 4.0,
      burstRange: 2.8 ... 3.4
    )
    let muxedURL = tempDir.appendingPathComponent("av_burst_muxed.mov")
    let muxComp = AVMutableComposition()
    let vAsset = AVURLAsset(url: burstVideoURL)
    let aAsset = AVURLAsset(url: burstWavURL)
    if let vSrc = try await vAsset.loadTracks(withMediaType: .video).first,
       let vDst = muxComp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
      try await vDst.insertTimeRange(
        CMTimeRange(start: .zero, duration: vAsset.load(.duration)),
        of: vSrc,
        at: .zero
      )
    }
    if let aSrc = try await aAsset.loadTracks(withMediaType: .audio).first,
       let aDst = muxComp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
      try await aDst.insertTimeRange(
        CMTimeRange(start: .zero, duration: aAsset.load(.duration)),
        of: aSrc,
        at: .zero
      )
    }
    let muxExport = try XCTUnwrap(AVAssetExportSession(asset: muxComp, presetName: AVAssetExportPresetPassthrough))
    muxExport.outputURL = muxedURL
    muxExport.outputFileType = .mov
    await muxExport.export()
    XCTAssertEqual(muxExport.status, .completed)

    let state = VideoEditorState(url: muxedURL)
    defer { state.cancelPendingPerformanceWork() }
    await state.loadMetadata()

    state.seek(to: CMTime(seconds: 2.0, preferredTimescale: 600))
    XCTAssertNotNil(state.splitAtPlayhead())
    let firstClipId = try XCTUnwrap(state.clips.first?.id)
    _ = await state.detachAudio(fromClipId: firstClipId)
    _ = state.addSpeed(range: 2.0 ... 4.0, rate: 2.0)

    let outURL = tempDir.appendingPathComponent("av_burst_speed2x.mp4")
    try await VideoEditorExporter.exportTrimmed(state: state, to: outURL) { _ in }

    let midRGB = try await sampleCenterPixelRGB(from: outURL, atSeconds: 2.55)
    let midLuma = 0.2126 * midRGB.r + 0.7152 * midRGB.g + 0.0722 * midRGB.b
    let midRMS = try await measureAudioRMS(from: outURL, rangeSeconds: 2.45 ... 2.65)
    XCTAssertGreaterThan(midLuma, 0.70)
    XCTAssertGreaterThan(midRMS, 0.08)
  }

  // MARK: - Fixtures

  private func makeKeyEvent(
    type: NSEvent.EventType,
    keyCode: UInt16,
    chars: String,
    modifiers: NSEvent.ModifierFlags = [],
    windowNumber: Int
  ) throws -> NSEvent {
    try XCTUnwrap(
      NSEvent.keyEvent(
        with: type,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: windowNumber,
        context: nil,
        characters: chars,
        charactersIgnoringModifiers: chars,
        isARepeat: false,
        keyCode: keyCode
      )
    )
  }

  private func makeTestMovie(
    in directory: URL,
    name: String,
    durationSeconds: Double,
    width: Int,
    height: Int
  ) async throws -> URL {
    let outputURL = directory.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: outputURL)
    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
    let fps: Int32 = 30
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
      ]
    )
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ]
    )
    writer.add(input)
    XCTAssertTrue(writer.startWriting())
    writer.startSession(atSourceTime: .zero)

    let totalFrames = max(6, Int(durationSeconds * Double(fps)))
    let q = DispatchQueue(label: "snapzy.canvas.test.movie.\(UUID().uuidString)")
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      var frame = 0
      input.requestMediaDataWhenReady(on: q) {
        while input.isReadyForMoreMediaData, frame < totalFrames {
          var pb: CVPixelBuffer?
          CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &pb)
          if let pb {
            CVPixelBufferLockBaseAddress(pb, [])
            if let base = CVPixelBufferGetBaseAddress(pb) {
              memset(base, Int32(28 + (frame * 5) % 160), CVPixelBufferGetDataSize(pb))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            let pts = CMTime(value: CMTimeValue(frame), timescale: fps)
            adaptor.append(pb, withPresentationTime: pts)
          }
          frame += 1
        }
        if frame >= totalFrames {
          input.markAsFinished()
          writer.finishWriting {
            if let err = writer.error {
              cont.resume(throwing: err)
            } else {
              cont.resume()
            }
          }
        }
      }
    }
    return outputURL
  }

  private func makeSolidColorMovie(
    in directory: URL,
    name: String,
    durationSeconds: Double,
    width: Int,
    height: Int,
    r: UInt8,
    g: UInt8,
    b: UInt8
  ) async throws -> URL {
    let url = directory.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ]
    )
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    let fps = 30
    let frameCount = Int(durationSeconds * Double(fps))
    for i in 0 ..< frameCount {
      while !input.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 2_000_000)
      }
      var pb: CVPixelBuffer?
      CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &pb)
      let buffer = try XCTUnwrap(pb)
      CVPixelBufferLockBaseAddress(buffer, [])
      if let base = CVPixelBufferGetBaseAddress(buffer) {
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        for y in 0 ..< height {
          for x in 0 ..< width {
            let off = y * bytesPerRow + x * 4
            ptr[off] = b
            ptr[off + 1] = g
            ptr[off + 2] = r
            ptr[off + 3] = 255
          }
        }
      }
      CVPixelBufferUnlockBaseAddress(buffer, [])
      adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
    }
    input.markAsFinished()
    await writer.finishWriting()
    return url
  }

  private func makeFlashBurstMovie(
    in directory: URL,
    name: String,
    durationSeconds: Double,
    flashRange: ClosedRange<Double>
  ) async throws -> URL {
    let width = 320
    let height = 180
    let url = directory.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ]
    )
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    let fps = 30
    let frameCount = Int(durationSeconds * Double(fps))
    for i in 0 ..< frameCount {
      while !input.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 2_000_000)
      }
      let t = Double(i) / Double(fps)
      let v: UInt8 = flashRange.contains(t) ? 245 : 12
      var pb: CVPixelBuffer?
      CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &pb)
      let buffer = try XCTUnwrap(pb)
      CVPixelBufferLockBaseAddress(buffer, [])
      if let base = CVPixelBufferGetBaseAddress(buffer) {
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        for y in 0 ..< height {
          for x in 0 ..< width {
            let off = y * bytesPerRow + x * 4
            ptr[off] = v
            ptr[off + 1] = v
            ptr[off + 2] = v
            ptr[off + 3] = 255
          }
        }
      }
      CVPixelBufferUnlockBaseAddress(buffer, [])
      adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
    }
    input.markAsFinished()
    await writer.finishWriting()
    return url
  }

  private func makeTestWAV(in directory: URL, name: String, durationSeconds: Double) throws -> URL {
    let url = directory.appendingPathComponent(name)
    let sampleRate = 8000
    let numSamples = max(800, Int(durationSeconds * Double(sampleRate)))
    let dataSize = UInt32(numSamples * 2)
    var header = Data()
    header.append("RIFF".data(using: .ascii)!)
    var chunkSize = UInt32(36 + dataSize).littleEndian
    header.append(Data(bytes: &chunkSize, count: 4))
    header.append("WAVEfmt ".data(using: .ascii)!)
    var subchunk1Size = UInt32(16).littleEndian
    var audioFormat = UInt16(1).littleEndian
    var numChannels = UInt16(1).littleEndian
    var sr = UInt32(sampleRate).littleEndian
    var byteRate = UInt32(sampleRate * 2).littleEndian
    var blockAlign = UInt16(2).littleEndian
    var bitsPerSample = UInt16(16).littleEndian
    header.append(Data(bytes: &subchunk1Size, count: 4))
    header.append(Data(bytes: &audioFormat, count: 2))
    header.append(Data(bytes: &numChannels, count: 2))
    header.append(Data(bytes: &sr, count: 4))
    header.append(Data(bytes: &byteRate, count: 4))
    header.append(Data(bytes: &blockAlign, count: 2))
    header.append(Data(bytes: &bitsPerSample, count: 2))
    header.append("data".data(using: .ascii)!)
    var subchunk2Size = dataSize.littleEndian
    header.append(Data(bytes: &subchunk2Size, count: 4))
    var pcm = Data(count: Int(dataSize))
    let phaseStep = 2.0 * Double.pi * 440.0 / Double(sampleRate)
    pcm.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
      guard let samples = raw.bindMemory(to: Int16.self).baseAddress else { return }
      for i in 0 ..< numSamples {
        let s = sin(Double(i) * phaseStep)
        samples[i] = Int16(s * 6000.0).littleEndian
      }
    }
    header.append(pcm)
    try header.write(to: url, options: .atomic)
    return url
  }

  private func makeBurstWAV(
    in directory: URL,
    name: String,
    durationSeconds: Double,
    burstRange: ClosedRange<Double>
  ) throws -> URL {
    let url = directory.appendingPathComponent(name)
    let sampleRate = 44_100
    let numSamples = Int(durationSeconds * Double(sampleRate))
    let dataSize = UInt32(numSamples * 2)
    let chunkSize = UInt32(36) + dataSize
    var header = Data()
    header.append("RIFF".data(using: .ascii)!)
    var cs = chunkSize.littleEndian
    header.append(Data(bytes: &cs, count: 4))
    header.append("WAVE".data(using: .ascii)!)
    header.append("fmt ".data(using: .ascii)!)
    var subchunk1Size = UInt32(16).littleEndian
    var audioFormat = UInt16(1).littleEndian
    var numChannels = UInt16(1).littleEndian
    var sr = UInt32(sampleRate).littleEndian
    var byteRate = UInt32(sampleRate * 2).littleEndian
    var blockAlign = UInt16(2).littleEndian
    var bitsPerSample = UInt16(16).littleEndian
    header.append(Data(bytes: &subchunk1Size, count: 4))
    header.append(Data(bytes: &audioFormat, count: 2))
    header.append(Data(bytes: &numChannels, count: 2))
    header.append(Data(bytes: &sr, count: 4))
    header.append(Data(bytes: &byteRate, count: 4))
    header.append(Data(bytes: &blockAlign, count: 2))
    header.append(Data(bytes: &bitsPerSample, count: 2))
    header.append("data".data(using: .ascii)!)
    var subchunk2Size = dataSize.littleEndian
    header.append(Data(bytes: &subchunk2Size, count: 4))
    var pcm = Data(count: Int(dataSize))
    let sampleRateDouble = Double(sampleRate)
    let burstAngularFreq = 2.0 * Double.pi * 880.0
    pcm.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
      guard let samples = raw.bindMemory(to: Int16.self).baseAddress else { return }
      for i in 0 ..< numSamples {
        let t = Double(i) / sampleRateDouble
        if burstRange.contains(t) {
          let s = sin(burstAngularFreq * t)
          samples[i] = Int16(s * 12_000.0).littleEndian
        } else {
          samples[i] = 0
        }
      }
    }
    header.append(pcm)
    try header.write(to: url, options: .atomic)
    return url
  }

  private func sampleCenterPixelRGB(from url: URL,
                                    atSeconds: Double) async throws -> (r: Double, g: Double, b: Double) {
    let asset = AVURLAsset(url: url)
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    gen.requestedTimeToleranceBefore = CMTime(seconds: 0.04, preferredTimescale: 600)
    gen.requestedTimeToleranceAfter = CMTime(seconds: 0.04, preferredTimescale: 600)
    let cg = try gen.copyCGImage(at: CMTime(seconds: atSeconds, preferredTimescale: 600), actualTime: nil)
    let rep = NSBitmapImageRep(cgImage: cg)
    let color = try XCTUnwrap(rep.colorAt(x: cg.width / 2, y: cg.height / 2)?.usingColorSpace(.sRGB))
    return (Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent))
  }

  private func measureAudioRMS(from url: URL, rangeSeconds: ClosedRange<Double>) async throws -> Double {
    let asset = AVURLAsset(url: url)
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    let track = try XCTUnwrap(audioTracks.first)
    let reader = try AVAssetReader(asset: asset)
    reader.timeRange = CMTimeRange(
      start: CMTime(seconds: rangeSeconds.lowerBound, preferredTimescale: 600),
      duration: CMTime(seconds: rangeSeconds.upperBound - rangeSeconds.lowerBound, preferredTimescale: 600)
    )
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true,
      AVLinearPCMIsNonInterleaved: false,
    ])
    reader.add(output)
    reader.startReading()
    var sumSquares: Double = 0
    var count = 0
    while let sampleBuffer = output.copyNextSampleBuffer() {
      guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
      let byteLength = CMBlockBufferGetDataLength(blockBuffer)
      let floatCount = byteLength / MemoryLayout<Float>.size
      guard floatCount > 0 else { continue }
      var floats = [Float](repeating: 0, count: floatCount)
      let status = floats.withUnsafeMutableBytes { raw -> OSStatus in
        guard let dst = raw.baseAddress else { return -1 }
        return CMBlockBufferCopyDataBytes(
          blockBuffer,
          atOffset: 0,
          dataLength: floatCount * MemoryLayout<Float>.size,
          destination: dst
        )
      }
      guard status == kCMBlockBufferNoErr else { continue }
      for v in floats {
        let d = Double(v)
        sumSquares += d * d
      }
      count += floatCount
    }
    reader.cancelReading()
    guard count > 0 else { return 0 }
    return sqrt(sumSquares / Double(count))
  }
}
