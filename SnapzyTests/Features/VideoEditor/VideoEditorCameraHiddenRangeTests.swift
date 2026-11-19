//
//  VideoEditorCameraHiddenRangeTests.swift
//  SnapzyTests
//
//  Hidden-camera ranges (fade, merge, export opacity, timeline pieces) and dragging the
//  camera on the preview with anchor snapping.
//

import CoreImage
import XCTest
@testable import Snapzy

final class VideoEditorCameraHiddenRangeTests: XCTestCase {
  func testVisibilityIsZeroInsideAndFadesAtTheEdges() {
    var settings = VideoEditorCameraSettings.default
    settings.hiddenRanges = [VideoEditorCameraHiddenRange(start: 2, end: 4)]
    XCTAssertEqual(settings.visibility(atSource: 3), 0)
    XCTAssertEqual(settings.visibility(atSource: 1.9), 0.5, accuracy: 0.001)
    XCTAssertEqual(settings.visibility(atSource: 4.1), 0.5, accuracy: 0.001)
    XCTAssertEqual(settings.visibility(atSource: 5), 1)
  }

  func testAddingMergesOverlapsAndKeepsOrder() {
    let settings = VideoEditorCameraSettings.default
      .addingHiddenRange(.init(start: 6, end: 8))
      .addingHiddenRange(.init(start: 1, end: 2))
      .addingHiddenRange(.init(start: 7, end: 9))
    XCTAssertEqual(settings.hiddenRanges.map(\.start), [1, 6])
    XCTAssertEqual(settings.hiddenRanges.last?.end, 9)
  }

  func testOldSettingsDecodeWithoutHiddenRanges() throws {
    let decoded = try JSONDecoder().decode(VideoEditorCameraSettings.self, from: Data(#"{"size":0.3}"#.utf8))
    XCTAssertTrue(decoded.hiddenRanges.isEmpty)
    XCTAssertEqual(decoded.size, 0.3, accuracy: 0.0001)
  }

  func testPiecesFollowCutsOnTheTimeline() {
    // 0–4 and 6–10 of the recording: a range over the cut shows as two pieces.
    let clips = [
      TimelineClip(source: .primary, sourceDuration: 10, sourceStart: 0, sourceEnd: 4),
      TimelineClip(source: .primary, sourceDuration: 10, sourceStart: 6, sourceEnd: 10),
    ]
    let id = UUID()
    let pieces = VideoEditorSourceTrackLayout.pieces(
      [(id, 3, 7)], placements: TimelineSequence.layout(clips), duration: 10, width: 100
    )
    XCTAssertEqual(pieces.count, 2)
    XCTAssertTrue(pieces.allSatisfy { $0.rangeID == id })
  }

  func testDragSnapsToNearbyAnchorAndStaysFreeElsewhere() {
    let video = CGSize(width: 400, height: 300)
    let camera = CGSize(width: 80, height: 80)
    // 10 % inset = 40 pt: the bottom-right anchor centers the camera at (320, 220).
    let snapped = VideoEditorCameraSettings.draggedPlacement(
      from: CGPoint(x: 0.5, y: 0.5), translation: CGSize(width: 115, height: 65),
      videoSize: video, cameraSize: camera, edgeInset: 0.1, threshold: 32
    )
    XCTAssertEqual(snapped.anchor, CGPoint(x: 1, y: 1))
    XCTAssertEqual(snapped.center.x, 0.8, accuracy: 0.001)
    XCTAssertEqual(snapped.center.y, 220.0 / 300, accuracy: 0.001)

    let free = VideoEditorCameraSettings.draggedPlacement(
      from: CGPoint(x: 0.5, y: 0.5), translation: CGSize(width: 60, height: 0),
      videoSize: video, cameraSize: camera, edgeInset: 0.1, threshold: 32
    )
    XCTAssertNil(free.anchor)
    XCTAssertEqual(free.center.x, 0.65, accuracy: 0.001)

    let clamped = VideoEditorCameraSettings.draggedPlacement(
      from: CGPoint(x: 0.5, y: 0.5), translation: CGSize(width: -1000, height: 0),
      videoSize: video, cameraSize: camera, threshold: 0
    )
    XCTAssertEqual(clamped.center.x, 0.1, accuracy: 0.001, "half the camera width keeps it inside")
  }

  func testAnchoredCameraKeepsTheSameEdgeGapAtAnySize() {
    var settings = VideoEditorCameraSettings.default
    settings.shape = "square"
    settings.anchor = CGPoint(x: 1, y: 1)
    let video = CGRect(x: 0, y: 0, width: 1000, height: 500)
    for size in [0.1, 0.2, 0.4] as [CGFloat] {
      settings.size = size
      let rect = settings.rect(in: video, aspect: 1, edgeInset: 0.02)
      XCTAssertEqual(video.maxX - rect.maxX, 20, accuracy: 1e-6)
      XCTAssertEqual(video.maxY - rect.maxY, 20, accuracy: 1e-6)
    }
  }

  func testExportLayerFadesOutInsideHiddenRange() {
    let source = RecordingCameraSource(
      fileName: "cam.mov", naturalSize: CGSize(width: 1280, height: 720), isMirrored: false, shape: "square",
      normalizedFrame: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), pointSize: CGSize(width: 120, height: 120),
      gaps: []
    )
    var settings = VideoEditorCameraSettings.recorded(source)
    settings.center = CGPoint(x: 0.5, y: 0.5)
    settings.hiddenRanges = [.init(start: 2, end: 4)]
    let clips = [TimelineClip(source: .primary, sourceDuration: 10)]
    let layer = VideoEditorCameraLayer(
      settings: settings, source: source,
      mapping: VideoEditorSourceTimeMapping(
        sequenceMap: TimelineSequenceMap(clips: clips, speedSegments: []),
        playbackPlacements: TimelineSequence.playableLayout(clips)
      )
    )
    let canvas = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
    let buffer = VideoEditorCameraLayerTests.greenBuffer()
    func green(_ time: TimeInterval) -> Int {
      let image = layer.composite(onto: canvas, context: VideoEditorStudioLayerContext(
        outputTime: time, extent: canvas.extent, auxiliaryFrames: [.camera: buffer]
      ))
      var pixel = [UInt8](repeating: 0, count: 4)
      CIContext().render(image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 100, y: 100, width: 1, height: 1),
                         format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
      return Int(pixel[1])
    }
    XCTAssertEqual(green(1), 255)
    XCTAssertEqual(green(3), 0)
    XCTAssertGreaterThan(green(4.1), 60)
    XCTAssertLessThan(green(4.1), 200, "half faded")
  }
}
