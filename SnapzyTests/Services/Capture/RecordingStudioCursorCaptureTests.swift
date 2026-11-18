//
//  RecordingStudioCursorCaptureTests.swift
//  SnapzyTests
//
//  Studio recording phase 1: cursor/click capture on the mouse tracker clock (incl.
//  pause/resume), cursor data round-trip, the cursor layer and the flatten pass.
//

import AppKit
import AVFoundation
import CoreImage
import XCTest
@testable import Snapzy

@MainActor
final class RecordingStudioCursorCaptureTests: XCTestCase {
  private var uptime: TimeInterval = 100

  private func makeMouseTracker(rect: CGRect = CGRect(x: 0, y: 0, width: 200, height: 100)) -> RecordingMouseTracker {
    RecordingMouseTracker(
      recordingRect: rect,
      fps: 30,
      uptimeProvider: { [unowned self] in self.uptime },
      mouseLocationProvider: { CGPoint(x: 50, y: 50) },
      mouseMonitorInstaller: { _ in nil },
      mouseMonitorRemover: { _ in }
    )
  }

  // MARK: - Capture clock

  func testClicksAndAppearanceUseTrackerClockAndSkipPauses() {
    let mouse = makeMouseTracker()
    var cursor: NSCursor? = .arrow
    let tracker = RecordingCursorAppearanceTracker(mouseTracker: mouse, cursorProvider: { cursor })
    mouse.start()
    tracker.start()

    uptime += 1
    tracker.record(.leftMouseDown, location: CGPoint(x: 50, y: 25))
    uptime += 0.1
    tracker.record(.leftMouseUp, location: CGPoint(x: 50, y: 25))

    mouse.pause()
    uptime += 5
    cursor = .iBeam
    tracker.poll()
    tracker.record(.leftMouseDown, location: CGPoint(x: 50, y: 25))
    mouse.resume()

    uptime += 1
    tracker.poll()
    cursor = nil
    uptime += 0.5
    tracker.poll()

    let capture = tracker.stop()
    _ = mouse.stop()

    XCTAssertEqual(capture.clicks.map(\.phase), [.down, .up])
    XCTAssertEqual(capture.clicks[0].time, 1, accuracy: 1e-6)
    XCTAssertEqual(capture.clicks[1].time, 1.1, accuracy: 1e-6)
    XCTAssertEqual(capture.clicks[0].normalizedX, 0.25, accuracy: 1e-6)
    XCTAssertEqual(capture.clicks[0].normalizedY, 0.75, accuracy: 1e-6)

    // Arrow at 0, I-beam picked up after resume (pause excluded: 2.1 s), then hidden.
    XCTAssertEqual(capture.appearance.count, 3)
    XCTAssertEqual(capture.appearance[0].time, 0, accuracy: 1e-6)
    XCTAssertEqual(capture.appearance[1].time, 2.1, accuracy: 1e-6)
    XCTAssertTrue(capture.appearance[2].isHidden)
    XCTAssertEqual(capture.images.count, 2)
    XCTAssertNotEqual(capture.appearance[0].imageID, capture.appearance[1].imageID)
  }

  func testUnmatchedMouseUpAndClicksOutsideCaptureAreIgnored() {
    let mouse = makeMouseTracker()
    let tracker = RecordingCursorAppearanceTracker(mouseTracker: mouse, cursorProvider: { .arrow })
    mouse.start()
    tracker.start()
    tracker.record(.leftMouseUp, location: CGPoint(x: 10, y: 10))
    tracker.record(.rightMouseDown, location: CGPoint(x: 500, y: 10))
    tracker.record(.rightMouseUp, location: CGPoint(x: 500, y: 10))
    XCTAssertTrue(tracker.stop().clicks.isEmpty)
  }

  // MARK: - Data

  func testCursorCaptureRoundTripsAndOldPayloadDecodes() throws {
    let capture = RecordingCursorCapture(
      imagesFolderName: "folder",
      images: [RecordedCursorImage(id: 0, fileName: "cursor-0.png", hotspot: CGPoint(x: 4, y: 4),
                                   pointSize: CGSize(width: 17, height: 23), scale: 2)],
      appearance: [RecordedCursorChange(time: 0, imageID: 0, isHidden: false)],
      clicks: [RecordedClick(time: 1, button: .left, phase: .down, normalizedX: 0.5, normalizedY: 0.5)]
    )
    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 200, height: 100),
      samplesPerSecond: 60,
      mouseSamples: [],
      cursorCapture: capture,
      isCursorBaked: false,
      studioSourceFileName: "source.mov"
    )
    let decoded = try JSONDecoder().decode(RecordingMetadata.self, from: JSONEncoder().encode(metadata))
    XCTAssertEqual(decoded, metadata)
    XCTAssertTrue(decoded.sidecarReferences.contains(.named(.studioSource, "source.mov")))

    let phase0 = try JSONDecoder().decode(RecordingCursorCapture.self, from: Data(#"{"imagesFolderName":"f"}"#.utf8))
    XCTAssertEqual(phase0, RecordingCursorCapture(imagesFolderName: "f"))
  }

  func testAppearanceLookupAndSampleInterpolation() {
    let capture = RecordingCursorCapture(appearance: [
      RecordedCursorChange(time: 0, imageID: 0, isHidden: false),
      RecordedCursorChange(time: 2, imageID: 1, isHidden: false),
      RecordedCursorChange(time: 3, imageID: nil, isHidden: true),
    ])
    XCTAssertEqual(capture.appearance(at: 1.9)?.imageID, 0)
    XCTAssertEqual(capture.appearance(at: 2)?.imageID, 1)
    XCTAssertEqual(capture.appearance(at: 10)?.isHidden, true)

    let samples = [
      RecordedMouseSample(time: 0, normalizedX: 0, normalizedY: 0, isInsideCapture: true),
      RecordedMouseSample(time: 1, normalizedX: 1, normalizedY: 0.5, isInsideCapture: true),
    ]
    let mid = RecordedMouseSampleInterpolator.sample(at: 0.5, in: samples)
    XCTAssertEqual(mid?.normalizedX ?? -1, 0.5, accuracy: 1e-6)
    XCTAssertEqual(mid?.normalizedY ?? -1, 0.25, accuracy: 1e-6)
  }

  func testFlattenNeededOnlyForUnbakedStudioRecordings() {
    var metadata = RecordingMetadata(captureSize: .zero, samplesPerSecond: 60, mouseSamples: [])
    XCTAssertFalse(RecordingStudioFlattenJob.needsFlatten(metadata))
    metadata.cursorCapture = RecordingCursorCapture()
    metadata.isCursorBaked = false
    XCTAssertTrue(RecordingStudioFlattenJob.needsFlatten(metadata))
  }

  // MARK: - Layer + flatten

  /// A 10×10 opaque white sprite with its hotspot at the top-left corner.
  private func whiteCursorLayer(at point: CGPoint, captureSize: CGSize) -> RecordingStudioCursorLayer {
    let sprite = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 20, height: 20))
    return RecordingStudioCursorLayer(
      samples: [RecordedMouseSample(time: 0, normalizedX: point.x, normalizedY: point.y, isInsideCapture: true)],
      capture: RecordingCursorCapture(
        images: [RecordedCursorImage(id: 0, fileName: "c.png", hotspot: .zero,
                                     pointSize: CGSize(width: 10, height: 10), scale: 2)],
        appearance: [RecordedCursorChange(time: 0, imageID: 0, isHidden: false)]
      ),
      captureSize: captureSize,
      images: [0: sprite],
      fallbackImage: nil,
      clickStyle: nil
    )
  }

  func testFlattenBurnsCursorAtHotspotAndKeepsTheRestOfTheFrame() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_StudioFlatten_\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    // Source 320×180 px, captured from a 160×90 pt rect (2 px per point).
    let source = try await StudioCompositorFixture.solidMovie(color: .red, size: CGSize(width: 320, height: 180), in: directory)
    let output = directory.appendingPathComponent("flat.mov")
    let layer = whiteCursorLayer(at: CGPoint(x: 0.5, y: 0.5), captureSize: CGSize(width: 160, height: 90))

    try await RecordingStudioFlattenExporter.flatten(
      sourceURL: source,
      outputURL: output,
      recipe: VideoEditorStudioRecipe(layers: [layer]),
      frameRate: 30
    )

    let asset = AVURLAsset(url: output)
    let duration = try await asset.load(.duration)
    XCTAssertEqual(duration.seconds, 0.5, accuracy: 0.05)
    let composition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)
    // Sprite spans 20×20 px starting at the center (160, 90), top-left origin.
    let cursor = try await StudioCompositorFixture.firstPixel(of: asset, videoComposition: composition, at: CGPoint(x: 168, y: 98))
    let away = try await StudioCompositorFixture.firstPixel(of: asset, videoComposition: composition, at: CGPoint(x: 40, y: 40))
    XCTAssertGreaterThan(cursor.g, 200, "cursor pixel \(cursor)")
    XCTAssertTrue(away.isDominantly(.red), "background pixel \(away)")
  }

  /// Gated timing run: `TEST_RUNNER_SNAPZY_FLATTEN_BENCH=<movie>` (60 fps assumed).
  /// Prints wall time / duration; the D1 default-ON target is <= 0.25 at 1080p.
  func testFlattenTimingBenchmark() async throws {
    guard let path = ProcessInfo.processInfo.environment["SNAPZY_FLATTEN_BENCH"] else {
      throw XCTSkip("Set TEST_RUNNER_SNAPZY_FLATTEN_BENCH to a movie path")
    }
    let source = URL(fileURLWithPath: path)
    let size = try await AVURLAsset(url: source).loadTracks(withMediaType: .video).first?.load(.naturalSize) ?? .zero
    let output = FileManager.default.temporaryDirectory.appendingPathComponent("flatten-bench-\(UUID().uuidString).mov")
    defer { try? FileManager.default.removeItem(at: output) }
    let samples = (0 ... 600).map { index in
      let t = Double(index) / 10
      return RecordedMouseSample(time: t, normalizedX: 0.5 + 0.4 * sin(t), normalizedY: 0.5 + 0.4 * cos(t), isInsideCapture: true)
    }
    var layer = whiteCursorLayer(at: .zero, captureSize: CGSize(width: size.width / 2, height: size.height / 2))
    layer = RecordingStudioCursorLayer(samples: samples, capture: layer.capture, captureSize: layer.captureSize,
                                       images: layer.images, fallbackImage: nil, clickStyle: nil)
    let duration = try await AVURLAsset(url: source).load(.duration).seconds
    let started = Date()
    try await RecordingStudioFlattenExporter.flatten(
      sourceURL: source, outputURL: output, recipe: VideoEditorStudioRecipe(layers: [layer]), frameRate: 60
    )
    let wall = Date().timeIntervalSince(started)
    XCTContext.runActivity(named: "FLATTEN_BENCH size=\(Int(size.width))x\(Int(size.height)) duration=\(duration) wall=\(wall) ratio=\(wall / duration)") { _ in }
  }
}
