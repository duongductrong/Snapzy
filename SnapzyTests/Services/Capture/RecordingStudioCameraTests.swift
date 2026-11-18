//
//  RecordingStudioCameraTests.swift
//  SnapzyTests
//
//  Studio recording phase 3: camera sidecar writer (timeline, gaps, held last frame),
//  camera metadata, the flatten camera layer and a flatten with a camera sidecar.
//

import AVFoundation
import CoreImage
import XCTest
@testable import Snapzy

final class RecordingStudioCameraTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_StudioCamera_\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private func pixelBuffer(width: Int = 64, height: Int = 36) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
    ] as CFDictionary, &buffer)
    return buffer!
  }

  func testWriterRecordsGapsAndLastsAsLongAsTheRecording() async throws {
    let url = directory.appendingPathComponent("camera.mov")
    let writer = RecordingCameraWriter(outputURL: url) { _ in nil }
    let buffer = pixelBuffer()
    for frame in 0 ..< 10 { // 0 ... 0.9 s
      writer.append(buffer, at: CMTime(value: CMTimeValue(frame), timescale: 10))
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    for frame in 20 ..< 25 { // 2.0 ... 2.4 s after a camera dropout
      writer.append(buffer, at: CMTime(value: CMTimeValue(frame), timescale: 10))
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    let finished = await writer.finish(duration: 3)
    let result = try XCTUnwrap(finished)

    XCTAssertEqual(result.naturalSize, CGSize(width: 64, height: 36))
    XCTAssertEqual(result.gaps.count, 2)
    // The real-time encoder may skip a frame that arrives while it is busy.
    XCTAssertGreaterThanOrEqual(result.gaps[0].start, 0.5)
    XCTAssertLessThanOrEqual(result.gaps[0].start, 0.9)
    XCTAssertEqual(result.gaps[0].end, 2.0, accuracy: 1e-6)
    XCTAssertGreaterThanOrEqual(result.gaps[1].start, 2.0)
    XCTAssertLessThanOrEqual(result.gaps[1].start, 2.4)
    XCTAssertEqual(result.gaps[1].end, 3, accuracy: 1e-6)
    let duration = try await AVURLAsset(url: result.url).load(.duration).seconds
    XCTAssertEqual(duration, 3, accuracy: 0.05)
  }

  func testWriterWithoutFramesProducesNothing() async {
    let url = directory.appendingPathComponent("empty.mov")
    let writer = RecordingCameraWriter(outputURL: url) { _ in nil }
    let result = await writer.finish(duration: 2)
    XCTAssertNil(result)
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }

  func testCameraSourceRoundTripsAndPhase0PayloadDecodes() throws {
    let source = RecordingCameraSource(
      fileName: "cam.mov", naturalSize: CGSize(width: 1280, height: 720), isMirrored: true, shape: "circle",
      normalizedFrame: CGRect(x: 0.7, y: 0.7, width: 0.2, height: 0.2), pointSize: CGSize(width: 120, height: 120),
      gaps: [RecordingTimeRange(start: 1, end: 2)]
    )
    let decoded = try JSONDecoder().decode(RecordingCameraSource.self, from: JSONEncoder().encode(source))
    XCTAssertEqual(decoded, source)
    let old = try JSONDecoder().decode(RecordingCameraSource.self, from: Data(#"{"fileName":"x.mov"}"#.utf8))
    XCTAssertEqual(old.fileName, "x.mov")
    XCTAssertEqual(old.normalizedFrame, .zero)
  }

  func testCameraLayerDrawsCircleAtOverlayRectAndSkipsGaps() {
    let source = RecordingCameraSource(
      fileName: "cam.mov", shape: "circle",
      normalizedFrame: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
      pointSize: CGSize(width: 50, height: 50),
      gaps: [RecordingTimeRange(start: 5, end: 6)]
    )
    let layer = RecordingStudioCameraLayer(source: source, captureSize: CGSize(width: 100, height: 100))
    let base = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
    let camera = pixelBuffer(width: 64, height: 64)
    fill(camera, bgra: [0, 255, 0, 255])

    // Bottom-right quadrant in top-left coordinates → x 100...200, CI y 0...100.
    let image = layer.composite(onto: base, context: VideoEditorStudioLayerContext(
      outputTime: 1, extent: base.extent, auxiliaryFrames: [.camera: camera]
    ))
    XCTAssertEqual(rgb(of: image, at: CGPoint(x: 150, y: 50)).g, 255)
    XCTAssertEqual(rgb(of: image, at: CGPoint(x: 103, y: 3)).r, 255, "circle corner stays background")
    XCTAssertEqual(rgb(of: image, at: CGPoint(x: 50, y: 150)).r, 255)

    let gap = layer.composite(onto: base, context: VideoEditorStudioLayerContext(
      outputTime: 5.5, extent: base.extent, auxiliaryFrames: [.camera: camera]
    ))
    XCTAssertEqual(rgb(of: gap, at: CGPoint(x: 150, y: 50)).r, 255)
  }

  @MainActor
  func testFlattenCompositesCameraSidecar() async throws {
    let screen = try await StudioCompositorFixture.solidMovie(color: .red, size: CGSize(width: 320, height: 180), in: directory)
    let camera = try await StudioCompositorFixture.solidMovie(color: .green, size: CGSize(width: 160, height: 90), in: directory)
    let output = directory.appendingPathComponent("flat.mov")
    let source = RecordingCameraSource(
      fileName: camera.lastPathComponent, naturalSize: CGSize(width: 160, height: 90), shape: "rectangle",
      normalizedFrame: CGRect(x: 0.5, y: 0.5, width: 0.4, height: 0.4), pointSize: CGSize(width: 64, height: 36)
    )
    let recipe = VideoEditorStudioRecipe(layers: [
      RecordingStudioCameraLayer(source: source, captureSize: CGSize(width: 160, height: 90)),
    ])
    try await RecordingStudioFlattenExporter.flatten(
      sourceURL: screen, outputURL: output, recipe: recipe, frameRate: 30, cameraURL: camera
    )
    let asset = AVURLAsset(url: output)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    XCTAssertEqual(tracks.count, 1)
    let composition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)
    // Camera rect: x 160...288, y 90...162 (top-left).
    let inside = try await StudioCompositorFixture.firstPixel(of: asset, videoComposition: composition, at: CGPoint(x: 224, y: 126))
    let outside = try await StudioCompositorFixture.firstPixel(of: asset, videoComposition: composition, at: CGPoint(x: 60, y: 40))
    XCTAssertTrue(inside.g > 200 && inside.b < 80, "camera pixel \(inside)")
    XCTAssertTrue(outside.isDominantly(.red), "screen pixel \(outside)")
  }

  // MARK: - Helpers

  private func fill(_ buffer: CVPixelBuffer, bgra: [UInt8]) {
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let row = CVPixelBufferGetBytesPerRow(buffer)
    for y in 0 ..< CVPixelBufferGetHeight(buffer) {
      for x in 0 ..< CVPixelBufferGetWidth(buffer) {
        let p = base + y * row + x * 4
        p[0] = bgra[0]; p[1] = bgra[1]; p[2] = bgra[2]; p[3] = bgra[3]
      }
    }
  }

  private func rgb(of image: CIImage, at point: CGPoint) -> (r: Int, g: Int, b: Int) {
    var pixel = [UInt8](repeating: 0, count: 4)
    CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
      .render(image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: point.x, y: point.y, width: 1, height: 1),
              format: .RGBA8, colorSpace: nil)
    return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
  }
}
