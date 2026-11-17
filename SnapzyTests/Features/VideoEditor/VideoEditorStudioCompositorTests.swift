//
//  VideoEditorStudioCompositorTests.swift
//  SnapzyTests
//
//  Studio layer hooks in the zoom compositor: pass-through when no layer is active,
//  source/canvas hooks run when one is, and the screen track is chosen explicitly when
//  an auxiliary (camera) track is present.
//

import AVFoundation
import CoreImage
import SwiftUI
import XCTest
@testable import Snapzy

private struct SolidFillLayer: VideoEditorStudioLayer {
  let space: VideoEditorStudioLayerSpace
  let isActive: Bool
  let color: CIColor

  func composite(onto image: CIImage, context: VideoEditorStudioLayerContext) -> CIImage {
    CIImage(color: color).cropped(to: context.extent)
  }
}

/// Draws the camera frame over the whole canvas.
private struct CameraFillLayer: VideoEditorStudioLayer {
  var space: VideoEditorStudioLayerSpace { .canvas }
  var isActive: Bool { true }
  var auxiliaryTracks: Set<VideoEditorStudioAuxiliaryTrack> { [.camera] }

  func composite(onto image: CIImage, context: VideoEditorStudioLayerContext) -> CIImage {
    guard let frame = context.auxiliaryFrames[.camera] else { return image }
    return CIImage(cvPixelBuffer: frame).cropped(to: context.extent)
  }
}

@MainActor
final class VideoEditorStudioCompositorTests: XCTestCase {
  private var tempDirectory: URL!
  private let size = CGSize(width: 128, height: 128)

  override func setUp() async throws {
    try await super.setUp()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_StudioCompositor_\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    if let tempDirectory {
      try? FileManager.default.removeItem(at: tempDirectory)
    }
    try await super.tearDown()
  }

  // MARK: - Recipe

  func testEmptyRecipeHasNoActiveLayers() {
    XCTAssertFalse(VideoEditorStudioRecipe.empty.hasActiveLayers)
    let inactive = VideoEditorStudioRecipe(layers: [SolidFillLayer(space: .source, isActive: false, color: .red)])
    XCTAssertFalse(inactive.hasActiveLayers)
    XCTAssertTrue(VideoEditorStudioRecipe(layers: [CameraFillLayer()]).hasActiveLayers)
    XCTAssertEqual(VideoEditorStudioRecipe(layers: [CameraFillLayer()]).requiredAuxiliaryTracks, [.camera])
  }

  func testInstructionRequiresScreenTrackFirstThenAuxiliaryTracks() {
    let instruction = ZoomVideoCompositionInstruction(
      timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1)),
      zooms: [],
      autoFocusPaths: [:],
      trackID: 7,
      renderSize: size,
      transitionDuration: 0.3,
      auxiliaryTrackIDs: [.camera: 3]
    )
    XCTAssertEqual(instruction.requiredSourceTrackIDs?.compactMap { ($0 as? NSNumber)?.int32Value }, [7, 3])
    XCTAssertFalse(instruction.hasStudioLayers)
  }

  func testResolveScreenTrackRefusesFirstTrackGuessWhenAuxiliaryTracksExist() throws {
    XCTAssertEqual(try ZoomCompositor.resolveScreenTrackID(explicit: nil, available: [1], auxiliary: []), 1)
    XCTAssertEqual(try ZoomCompositor.resolveScreenTrackID(explicit: 2, available: [1, 2], auxiliary: [1]), 2)
    XCTAssertThrowsError(try ZoomCompositor.resolveScreenTrackID(explicit: nil, available: [1, 2], auxiliary: [1]))
    XCTAssertThrowsError(try ZoomCompositor.resolveScreenTrackID(explicit: 1, available: [1, 2], auxiliary: [1]))
    XCTAssertThrowsError(try ZoomCompositor.resolveScreenTrackID(explicit: 9, available: [1, 2], auxiliary: []))
  }

  // MARK: - Rendering

  func testNoActiveLayerPassesScreenFrameThrough() async throws {
    let screen = try await StudioCompositorFixture.solidMovie(color: .blue, size: size, in: tempDirectory)
    let inactive = VideoEditorStudioRecipe(layers: [SolidFillLayer(space: .canvas, isActive: false, color: .red)])

    let pixel = try await renderFirstPixel(screen: screen, recipe: inactive)

    XCTAssertTrue(pixel.isDominantly(.blue), "\(pixel)")
  }

  func testSourceSpaceLayerRunsBeforeZoom() async throws {
    let screen = try await StudioCompositorFixture.solidMovie(color: .blue, size: size, in: tempDirectory)
    let recipe = VideoEditorStudioRecipe(layers: [SolidFillLayer(space: .source, isActive: true, color: .red)])

    let pixel = try await renderFirstPixel(screen: screen, recipe: recipe)

    XCTAssertTrue(pixel.isDominantly(.red), "\(pixel)")
  }

  func testCanvasSpaceLayerCoversBackgroundPadding() async throws {
    let screen = try await StudioCompositorFixture.solidMovie(color: .blue, size: size, in: tempDirectory)
    let recipe = VideoEditorStudioRecipe(layers: [SolidFillLayer(space: .canvas, isActive: true, color: .green)])

    let pixel = try await renderFirstPixel(
      screen: screen,
      recipe: recipe,
      background: .solidColor(.white),
      padding: 16,
      samplePoint: CGPoint(x: 4, y: 4) // inside the padding, outside the video
    )

    XCTAssertTrue(pixel.isDominantly(.green), "\(pixel)")
  }

  func testCameraLayerReadsAuxiliaryTrackWhileScreenTrackStaysExplicit() async throws {
    let screen = try await StudioCompositorFixture.solidMovie(color: .blue, size: size, in: tempDirectory)
    let camera = try await StudioCompositorFixture.solidMovie(color: .green, size: size, in: tempDirectory)

    // Camera inserted FIRST so a "first video track" fallback would pick it.
    let withoutLayer = try await renderFirstPixel(screen: screen, camera: camera, recipe: .empty)
    XCTAssertTrue(withoutLayer.isDominantly(.blue), "Screen track must win: \(withoutLayer)")

    let withLayer = try await renderFirstPixel(
      screen: screen,
      camera: camera,
      recipe: VideoEditorStudioRecipe(layers: [CameraFillLayer()])
    )
    XCTAssertTrue(withLayer.isDominantly(.green), "\(withLayer)")
  }

  // MARK: - Helpers

  private func renderFirstPixel(
    screen: URL,
    camera: URL? = nil,
    recipe: VideoEditorStudioRecipe,
    background: Snapzy.BackgroundStyle = .none,
    padding: CGFloat = 0,
    samplePoint: CGPoint? = nil
  ) async throws -> StudioCompositorFixture.Pixel {
    let composition = AVMutableComposition()
    var auxiliary: [VideoEditorStudioAuxiliaryTrack: CMPersistentTrackID] = [:]
    if let camera {
      auxiliary[.camera] = try await StudioCompositorFixture.insertVideo(from: camera, into: composition)
    }
    let screenTrackID = try await StudioCompositorFixture.insertVideo(from: screen, into: composition)

    let compositor = ZoomCompositor(
      zooms: [],
      renderSize: size,
      backgroundStyle: background,
      backgroundPadding: padding,
      studioRecipe: recipe
    )
    let videoComposition = try await compositor.createVideoComposition(
      for: composition,
      timeRange: CMTimeRange(start: .zero, duration: composition.duration),
      screenTrackID: screenTrackID,
      auxiliaryTrackIDs: auxiliary
    )
    videoComposition.renderSize = compositor.paddedRenderSize
    let point = samplePoint ?? CGPoint(x: compositor.paddedRenderSize.width / 2, y: compositor.paddedRenderSize.height / 2)
    return try await StudioCompositorFixture.firstPixel(of: composition, videoComposition: videoComposition, at: point)
  }
}
