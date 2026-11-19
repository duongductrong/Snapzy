//
//  VideoEditorCameraLayerTests.swift
//  SnapzyTests
//
//  Studio camera layer (phase 4): placement math shared by preview and export, the
//  recorded default, and the export layer (video rect inside padding, gaps, clips
//  from other files).
//

import CoreImage
import XCTest
@testable import Snapzy

final class VideoEditorCameraLayerTests: XCTestCase {
  private let source = RecordingCameraSource(
    fileName: "cam.mov", naturalSize: CGSize(width: 1280, height: 720), isMirrored: true, shape: "circle",
    normalizedFrame: CGRect(x: 0.7, y: 0.6, width: 0.2, height: 0.3), pointSize: CGSize(width: 120, height: 120),
    gaps: [RecordingTimeRange(start: 5, end: 6)]
  )

  func testRecordedSettingsMatchTheOverlayWhileRecording() {
    let settings = VideoEditorCameraSettings.recorded(source)
    XCTAssertEqual(settings.shape, "circle")
    XCTAssertTrue(settings.isMirrored)
    XCTAssertEqual(settings.size, 0.2, accuracy: 1e-6)
    XCTAssertEqual(settings.center.x, 0.8, accuracy: 1e-6)
    XCTAssertEqual(settings.center.y, 0.75, accuracy: 1e-6)
  }

  func testRectUsesShapeAspectAndStaysInsideTheVideo() {
    var settings = VideoEditorCameraSettings.default
    settings.size = 0.25
    settings.center = CGPoint(x: 1, y: 1)
    let video = CGRect(x: 10, y: 20, width: 400, height: 200)
    let rect = settings.rect(in: video, aspect: 2)
    XCTAssertEqual(rect.width, 100, accuracy: 1e-6)
    XCTAssertEqual(rect.height, 50, accuracy: 1e-6)
    XCTAssertEqual(rect.maxX, video.maxX, accuracy: 1e-6)
    XCTAssertEqual(rect.maxY, video.maxY, accuracy: 1e-6)

    settings.shape = "circle"
    let circle = settings.rect(in: video, aspect: 2)
    XCTAssertEqual(circle.width, circle.height)
    XCTAssertEqual(settings.cornerRadius(for: circle, referencePointWidth: 120), 50, accuracy: 1e-6)
  }

  func testCornerRadiusScalesWithTheOverlayReference() {
    var settings = VideoEditorCameraSettings.default
    settings.shape = "rectangle"
    // 18 pt on a 180 pt overlay → 10 % of the width.
    XCTAssertEqual(settings.cornerRadius(for: CGRect(x: 0, y: 0, width: 300, height: 100), referencePointWidth: 180), 30, accuracy: 1e-6)
  }

  func testExportLayerDrawsInsideVideoRectAndSkipsGapsAndOtherFiles() {
    var settings = VideoEditorCameraSettings.recorded(source)
    settings.shape = "square"
    settings.isMirrored = false
    settings.size = 0.5
    settings.center = CGPoint(x: 0.5, y: 0.5)
    let primary = TimelineClip(source: .primary, sourceDuration: 10)
    let other = TimelineClip(source: .file(url: URL(fileURLWithPath: "/tmp/o.mov")), sourceDuration: 2)
    let clips = [primary, other]
    let layer = VideoEditorCameraLayer(
      settings: settings,
      source: source,
      mapping: VideoEditorSourceTimeMapping(
        sequenceMap: TimelineSequenceMap(clips: clips, speedSegments: []),
        playbackPlacements: TimelineSequence.playableLayout(clips)
      )
    )
    // Canvas 300×300 with the video at (50, 50, 200, 200): camera 100×100 centered.
    let canvas = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 300, height: 300))
    let videoRect = CGRect(x: 50, y: 50, width: 200, height: 200)
    let camera = Self.greenBuffer()

    func render(_ time: TimeInterval) -> CIImage {
      layer.composite(onto: canvas, context: VideoEditorStudioLayerContext(
        outputTime: time, extent: canvas.extent, auxiliaryFrames: [.camera: camera], videoRect: videoRect
      ))
    }
    XCTAssertEqual(green(render(1), at: CGPoint(x: 150, y: 150)), 255)
    XCTAssertEqual(green(render(1), at: CGPoint(x: 95, y: 150)), 0, "outside the camera rect")
    XCTAssertEqual(green(render(5.5), at: CGPoint(x: 150, y: 150)), 0, "camera gap")
    XCTAssertEqual(green(render(11), at: CGPoint(x: 150, y: 150)), 0, "inserted clip from another file")
  }

  // MARK: - Helpers

  static func greenBuffer() -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, 64, 36, kCVPixelFormatType_32BGRA, [
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
    ] as CFDictionary, &buffer)
    let pixel = buffer!
    CVPixelBufferLockBaseAddress(pixel, [])
    let base = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
    let row = CVPixelBufferGetBytesPerRow(pixel)
    for y in 0 ..< 36 {
      for x in 0 ..< 64 {
        let p = base + y * row + x * 4
        p[0] = 0; p[1] = 255; p[2] = 0; p[3] = 255
      }
    }
    CVPixelBufferUnlockBaseAddress(pixel, [])
    return pixel
  }

  private func green(_ image: CIImage, at point: CGPoint) -> Int {
    var pixel = [UInt8](repeating: 0, count: 4)
    CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
      .render(image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: point.x, y: point.y, width: 1, height: 1),
              format: .RGBA8, colorSpace: nil)
    return Int(pixel[1])
  }
}
