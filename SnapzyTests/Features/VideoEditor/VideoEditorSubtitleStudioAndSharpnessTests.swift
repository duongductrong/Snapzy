//
//  VideoEditorSubtitleStudioAndSharpnessTests.swift
//  SnapzyTests
//
//  Tests for 2x Retina timeline filmstrip sharpness, macOS System Font (SF Pro)
//  and installed device fonts (1-run Vietnamese diacritics + local TTF synthetic oblique),
//  Text Overlay studio presets, deterministic motion + specular sheen GPU export, and atomic
//  two-way Text (`Aa`) ↔ Captions conversion & style sync.
//

import AppKit
import AVFoundation
import CoreImage
import CoreText
@testable import Snapzy
import XCTest

@MainActor
final class VideoEditorSubtitleStudioAndSharpnessTests: XCTestCase {
  private var tempDir: URL!

  override func setUpWithError() throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzySubtitleSharpnessTests_\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let tempDir {
      try? FileManager.default.removeItem(at: tempDir)
    }
  }

  // MARK: - 1. Retina Filmstrip Thumbnail Sharpness

  func testTimelineThumbnailsExtractAtRetina2xBackingScale() async throws {
    let url = try await make1080pTestMovie(name: "retina_strip.mov", durationSeconds: 3.0)
    let state = VideoEditorState(url: url)
    defer { state.cancelPendingPerformanceWork() }
    await state.loadMetadata()
    await state.extractFrames()

    XCTAssertGreaterThanOrEqual(state.frameThumbnails.count, 20)
    let first = try XCTUnwrap(state.frameThumbnails.first)
    let rep = try XCTUnwrap(first.representations.first as? NSBitmapImageRep)

    XCTAssertGreaterThanOrEqual(rep.pixelsWide, 400)
    XCTAssertGreaterThanOrEqual(rep.pixelsHigh, 220)
    XCTAssertEqual(Double(rep.pixelsWide) / first.size.width, 2.0, accuracy: 0.05)
    XCTAssertEqual(Double(rep.pixelsHigh) / first.size.height, 2.0, accuracy: 0.05)
  }

  // MARK: - 2. System Font Default, Installed Device Fonts & Per-Item Text Presets

  func testSystemAndInstalledFontsAndAllTextPresetsRenderVietnameseCleanly() throws {
    XCTAssertEqual(VideoEditorFontResolver.defaultFamilyId, "system")
    XCTAssertFalse(
      VideoEditorFontManager.shared.installedFamilies.isEmpty,
      "Font picker must enumerate fonts already installed on the user's Mac"
    )

    let vnStress = "PHỤ ĐỀ MỚI • RẤT NHIỀU THỜI GIAN • bạn cần biết kỹ năng 60fps"
    for family in VideoEditorCaptionSettings.FontFamily.allCases {
      for bold in [true, false] {
        for italic in [false, true] {
          let ctFont = VideoEditorCaptionLayout.makeFont(
            size: 48,
            bold: bold,
            italic: italic,
            family: family
          )
          let psName = CTFontCopyPostScriptName(ctFont) as String
          XCTAssertFalse(psName.isEmpty)
          let attr = NSAttributedString(
            string: vnStress,
            attributes: [.init(kCTFontAttributeName as String): ctFont]
          )
          let ctLine = CTLineCreateWithAttributedString(attr)
          let runCount = CFArrayGetCount(CTLineGetGlyphRuns(ctLine))
          XCTAssertEqual(
            runCount,
            1,
            "System typeface \(family.rawValue) (bold=\(bold), italic=\(italic), ps=\(psName)) fell back across \(runCount) glyph runs"
          )
        }
      }
    }

    // Verify installed device font resolution (`installed:<FamilyName>`)
    if let firstInstalled = VideoEditorFontManager.shared.installedFamilies
      .first(where: { $0.familyName.contains("Helvetica") || $0.familyName.contains("Arial") })
      ?? VideoEditorFontManager.shared.installedFamilies.first {
      XCTAssertTrue(VideoEditorFontManager.shared.isFontAvailable(firstInstalled.id))
      let resolvedInstalled = VideoEditorFontResolver.resolveFont(
        familyId: firstInstalled.id,
        size: 42,
        weight: 700,
        italic: false
      )
      XCTAssertFalse((CTFontCopyPostScriptName(resolvedInstalled.font) as String).isEmpty)
    }

    // Missing custom font IDs must report unavailable and fall back cleanly to System Font
    XCTAssertFalse(VideoEditorFontManager.shared.isFontAvailable("custom-missing-font-999"))
    let missingResolution = VideoEditorFontResolver.resolveFont(
      familyId: "custom-missing-font-999",
      size: 42,
      weight: 700,
      italic: false
    )
    XCTAssertFalse((CTFontCopyPostScriptName(missingResolution.font) as String).isEmpty)

    // Verify local `.ttf` font import + universal synthetic Italic matrix on upright-only system TTF copy
    let candidateUprightTTFs: [URL] = [
      URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Tahoma.ttf"),
      URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Impact.ttf"),
      URL(fileURLWithPath: "/System/Library/Fonts/SFNSMono.ttf"),
      URL(fileURLWithPath: "/System/Library/Fonts/Geneva.ttf"),
    ]
    let uprightTTF = try XCTUnwrap(
      candidateUprightTTFs.first { FileManager.default.fileExists(atPath: $0.path) },
      "Expected an upright macOS system TTF fixture for local font import test"
    )
    let copyTTF = tempDir.appendingPathComponent("StudioCustomUpright_\(UUID().uuidString.prefix(6)).ttf")
    try FileManager.default.copyItem(at: uprightTTF, to: copyTTF)
    let importedId = try XCTUnwrap(VideoEditorFontManager.shared.importFontFiles(from: [copyTTF]))
    let importedDir = VideoEditorFontResolver.storageRootURL().appendingPathComponent(importedId, isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: importedDir)
    }
    XCTAssertTrue(VideoEditorFontManager.shared.importedFonts.contains { $0.id == importedId })

    let synthItalic = VideoEditorFontResolver.resolveFont(
      familyId: importedId,
      size: 44,
      weight: 800,
      italic: true
    ).font
    let mat = CTFontGetMatrix(synthItalic)
    let traits = CTFontGetSymbolicTraits(synthItalic)
    XCTAssertTrue(
      mat.c > 0.12 || traits.contains(.traitItalic),
      "Imported TTF must resolve italic via native face or synthetic oblique matrix when Italic is ON"
    )

    let canvasSize = CGSize(width: 1920, height: 1080)
    let baseCanvas = CIImage(color: CIColor(red: 0.05, green: 0.07, blue: 0.11))
      .cropped(to: CGRect(origin: .zero, size: canvasSize))

    for preset in VideoEditorCaptionSettings.EditorialPreset.allCases {
      var overlay = VideoEditorTextOverlay(
        text: "và đang tốn rất nhiều thời gian",
        startTime: 0.5,
        duration: 3.0
      )
      overlay.applyPreset(preset)
      XCTAssertEqual(overlay.style.matchingPreset, preset, "Preset \(preset.rawValue) must match itself")

      let encoded = try JSONEncoder().encode(overlay)
      let decoded = try JSONDecoder().decode(VideoEditorTextOverlay.self, from: encoded)
      XCTAssertEqual(decoded, overlay)

      let pill = try XCTUnwrap(
        VideoEditorTextOverlayRenderer.renderPillImage(for: overlay, canvasSize: canvasSize, outputTime: 1.5),
        "Failed to render TextOverlay pill for preset \(preset.rawValue)"
      )
      XCTAssertGreaterThan(pill.extent.width, 100)
      XCTAssertGreaterThan(pill.extent.height, 30)

      let composited = VideoEditorTextOverlayRenderer.composite(
        pillImage: pill,
        onto: baseCanvas,
        overlay: overlay,
        canvasSize: canvasSize,
        motion: overlay.motionState(at: 1.5)
      )
      XCTAssertEqual(composited.extent, CGRect(origin: .zero, size: canvasSize))
    }
  }

  // MARK: - 3. Kinetic Active Word & Progressive Reveal Without Layout Shift

  func testWordTimingModesAdvanceMonotonicallyWithZeroBoxJitter() throws {
    var settings = VideoEditorCaptionSettings.default
    settings.apply(preset: .kineticPulse)
    let segment = CaptionSegment(
      sourceRange: 1.0 ... 5.0,
      text: "Design faster with Montserrat subtitles"
    )
    let videoSize = CGSize(width: 1280, height: 720)
    let baseLayout = try XCTUnwrap(
      VideoEditorCaptionLayout.make(text: segment.text, settings: settings, videoSize: videoSize)
    )
    XCTAssertEqual(baseLayout.flatWords.count, 5)

    let idxStart = try XCTUnwrap(
      VideoEditorCaptionMotion.activeWordIndex(atSource: 1.05, in: segment, wordsInLayout: baseLayout.flatWords)
    )
    let idxMid = try XCTUnwrap(
      VideoEditorCaptionMotion.activeWordIndex(atSource: 3.0, in: segment, wordsInLayout: baseLayout.flatWords)
    )
    let idxEnd = try XCTUnwrap(
      VideoEditorCaptionMotion.activeWordIndex(atSource: 4.95, in: segment, wordsInLayout: baseLayout.flatWords)
    )
    XCTAssertEqual(idxStart, 0)
    XCTAssertGreaterThan(idxMid, idxStart)
    XCTAssertEqual(idxEnd, 4)

    let cache = VideoEditorCaptionImageCache(capacity: 16)
    let e0 = try XCTUnwrap(cache.entry(
      text: segment.text,
      segment: segment,
      sourceTime: 1.05,
      settings: settings,
      videoSize: videoSize
    ))
    let e4 = try XCTUnwrap(cache.entry(
      text: segment.text,
      segment: segment,
      sourceTime: 4.95,
      settings: settings,
      videoSize: videoSize
    ))
    XCTAssertEqual(e0.layout.size, e4.layout.size)
    XCTAssertEqual(e0.image.width, e4.image.width)
    XCTAssertEqual(e0.image.height, e4.image.height)
  }

  // MARK: - 4. All 10 Motion Curves & Specular Light Sheen on Text Overlays

  func testAllMotionCurvesAndSpecularSheenCompositeCleanlyOnTextOverlays() throws {
    let canvasSize = CGSize(width: 640, height: 360)
    let baseFrame = CIImage(color: CIColor(red: 0.05, green: 0.08, blue: 0.14))
      .cropped(to: CGRect(origin: .zero, size: canvasSize))

    for style in VideoEditorCaptionSettings.AnimationStyle.allCases where style != .none {
      var overlay = VideoEditorTextOverlay(text: "Comment \"Preset\"", startTime: 1.0, duration: 3.0)
      overlay.applyPreset(.solarSheen)
      overlay.style.shimmerSweep = false
      overlay.style.animationIn = style
      overlay.style.animationOut = style
      overlay.style.animationDuration = 0.26

      let enterStart = overlay.motionState(at: 1.01)
      let settled = overlay.motionState(at: 2.50)
      let exitEnd = overlay.motionState(at: 3.99)

      XCTAssertEqual(settled, .identity, "Style \(style.rawValue) must settle to exact identity at midpoint")
      if style == .editorialWipe {
        XCTAssertLessThan(enterStart.wipeProgress, 0.25)
      } else if style == .maskSlideUp {
        XCTAssertLessThan(enterStart.verticalRevealProgress, 0.30)
      } else if style == .wordCascade || style == .wordBlurIn || style == .typewriterPro {
        let subP = try XCTUnwrap(enterStart.subwordProgress)
        XCTAssertLessThan(subP, 0.20, "Subword style \(style.rawValue) must start at early stagger progress")
      } else if style == .shutterFlip {
        XCTAssertLessThan(enterStart.scaleY, 0.35)
      } else {
        XCTAssertLessThan(enterStart.opacity, 0.45)
      }
      XCTAssertLessThan(exitEnd.opacity, 0.30)

      let pill = try XCTUnwrap(VideoEditorTextOverlayRenderer.renderPillImage(
        for: overlay,
        canvasSize: canvasSize,
        outputTime: 1.06
      ))
      for t in [1.06, 2.50, 3.94] {
        let out = VideoEditorTextOverlayRenderer.composite(
          pillImage: pill,
          onto: baseFrame,
          overlay: overlay,
          canvasSize: canvasSize,
          motion: overlay.motionState(at: t)
        )
        XCTAssertEqual(out.extent, CGRect(origin: .zero, size: canvasSize))
      }
    }

    var sheenOverlay = VideoEditorTextOverlay(text: "Comment \"Preset\"", startTime: 1.0, duration: 3.0)
    sheenOverlay.applyPreset(.solarSheen)
    XCTAssertNotNil(sheenOverlay.motionState(at: 1.50).shimmerProgress)
  }

  // MARK: - 5. Bidirectional Text (`Aa`) ↔ Captions Conversion & Undo

  func testBidirectionalTextAndCaptionsIntegrationWithAtomicUndo() async throws {
    let srtSample = """
    1
    00:00:00,400 --> 00:00:02,000
    và đang tốn rất nhiều thời gian

    2
    00:00:02,200 --> 00:00:04,400
    tất tần tật bạn cần biết
    """
    let srtURL = tempDir.appendingPathComponent("sample.srt")
    try srtSample.write(to: srtURL, atomically: true, encoding: .utf8)

    let url = try await make1080pTestMovie(name: "bridge.mov", durationSeconds: 5.0)
    let state = VideoEditorState(url: url)
    defer { state.cancelPendingPerformanceWork() }
    await state.loadMetadata()

    XCTAssertEqual(state.importSubtitles(from: srtURL), 2)
    XCTAssertEqual(state.captions.segments.count, 2)

    // 1. Promote single caption cue -> creates independent TextOverlay + removes cue in 1 atomic Undo step!
    let firstCueId = state.captions.segments[0].id
    let promoted = try XCTUnwrap(state.promoteCaptionToTextOverlay(captionId: firstCueId))
    XCTAssertEqual(state.textOverlays.count, 1)
    XCTAssertEqual(state.captions.segments.count, 1)
    XCTAssertEqual(promoted.text, "và đang tốn rất nhiều thời gian")
    XCTAssertEqual(state.leftSidebarPanel, .text)

    // Style that promoted TextOverlay independently with `velvetSerif` and sync to Captions
    state.applyTextPreset(.velvetSerif, to: promoted.id)
    XCTAssertEqual(state.selectedTextOverlay?.style.matchingPreset, .velvetSerif)
    state.syncSelectedTextStyleToCaptions()
    XCTAssertTrue(state.captions.settings.resolvedItalic)
    XCTAssertEqual(state.captions.settings.fontWeight, 700)

    // Undo sync + undo preset + single atomic undo of promote -> both tracks back to exact initial SRT state!
    state.undo() // undo syncSelectedTextStyleToCaptions
    state.undo() // undo applyTextPreset
    state.undo() // atomic undo of promoteCaptionToTextOverlay!
    XCTAssertTrue(state.textOverlays.isEmpty)
    XCTAssertEqual(state.captions.segments.count, 2)

    // 2. Convert ALL captions to Text Overlays -> mutes captions track & populates 2 Text items atomically!
    XCTAssertEqual(state.convertAllCaptionsToTextOverlays(), 2)
    XCTAssertEqual(state.textOverlays.count, 2)
    XCTAssertFalse(state.captions.settings.isEnabled)
    XCTAssertEqual(state.leftSidebarPanel, .text)

    // Single Undo restores enabled Captions and clears converted Text items!
    state.undo()
    XCTAssertTrue(state.textOverlays.isEmpty)
    XCTAssertTrue(state.captions.settings.isEnabled)
    XCTAssertEqual(state.captions.segments.count, 2)

    // 3. Convert a standalone Text Overlay into a Caption cue!
    let standalone = try XCTUnwrap(state.addTextOverlay(
      text: "Highlight text",
      at: 1.2,
      duration: 1.5,
      preset: .rangeHighlight
    ))
    let newSeg = try XCTUnwrap(state.convertTextOverlayToCaption(id: standalone.id))
    XCTAssertEqual(newSeg.text, "Highlight text")
    XCTAssertTrue(state.textOverlays.isEmpty)
    XCTAssertEqual(state.captions.segments.count, 3)
    XCTAssertEqual(state.leftSidebarPanel, .captions)
  }

  // MARK: - Fixture Helper

  private func make1080pTestMovie(name: String, durationSeconds: Double) async throws -> URL {
    let outputURL = tempDir.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: outputURL)
    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
    let width = 1920
    let height = 1080
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

    let totalFrames = Int(durationSeconds * Double(fps))
    let q = DispatchQueue(label: "snapzy.subtitle.test.writer")
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      var frame = 0
      input.requestMediaDataWhenReady(on: q) {
        while input.isReadyForMoreMediaData, frame < totalFrames {
          var pb: CVPixelBuffer?
          CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &pb)
          if let pb {
            CVPixelBufferLockBaseAddress(pb, [])
            if let base = CVPixelBufferGetBaseAddress(pb) {
              memset(base, Int32(30 + (frame * 3) % 180), CVPixelBufferGetDataSize(pb))
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
}
