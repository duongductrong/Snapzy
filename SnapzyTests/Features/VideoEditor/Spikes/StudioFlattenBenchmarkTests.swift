//
//  StudioFlattenBenchmarkTests.swift
//  SnapzyTests
//
//  SPIKE (Decision D1). Times a "flatten" of a Studio recording through the real
//  ZoomCompositor + Studio hooks with stand-in cursor/camera layers, against a plain
//  re-encode. Gated: SNAPZY_SPIKE_FLATTEN=1 (xcodebuild: TEST_RUNNER_ prefix) and
//  SNAPZY_SPIKE_SCREEN=<movie>; optional SNAPZY_SPIKE_CAMERA=<movie>,
//  SNAPZY_SPIKE_PRESET=<AVAssetExportPreset…> (default HEVCHighestQuality).
//

import AVFoundation
import CoreImage
import XCTest
@testable import Snapzy

/// Stand-in cursor: a 32×48 sprite with an outline, moving on a circle (source space).
private struct BenchCursorLayer: VideoEditorStudioLayer {
  var space: VideoEditorStudioLayerSpace { .source }
  var isActive: Bool { true }

  func composite(onto image: CIImage, context: VideoEditorStudioLayerContext) -> CIImage {
    let e = context.extent
    let angle = context.outputTime * 1.3
    let origin = CGPoint(x: e.midX + cos(angle) * e.width * 0.3, y: e.midY + sin(angle) * e.height * 0.3)
    let outline = CIImage(color: .black).cropped(to: CGRect(origin: origin, size: CGSize(width: 34, height: 50)))
    let body = CIImage(color: .white).cropped(to: CGRect(x: origin.x + 1, y: origin.y + 1, width: 32, height: 48))
    return body.composited(over: outline).composited(over: image)
  }
}

/// Stand-in camera bubble: circle-masked camera frame, 22 % of canvas width (canvas space).
private struct BenchCameraLayer: VideoEditorStudioLayer {
  var space: VideoEditorStudioLayerSpace { .canvas }
  var isActive: Bool { true }
  var auxiliaryTracks: Set<VideoEditorStudioAuxiliaryTrack> { [.camera] }

  func composite(onto image: CIImage, context: VideoEditorStudioLayerContext) -> CIImage {
    guard let frame = context.auxiliaryFrames[.camera] else { return image }
    let e = context.extent
    let camera = CIImage(cvPixelBuffer: frame)
    let diameter = e.width * 0.22
    let scale = diameter / min(camera.extent.width, camera.extent.height)
    let rect = CGRect(x: e.maxX - diameter - 40, y: e.minY + 40, width: diameter, height: diameter)
    let placed = camera.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
      .cropped(to: rect)
    let mask = CIFilter(name: "CIRadialGradient", parameters: [
      "inputCenter": CIVector(x: rect.midX, y: rect.midY),
      "inputRadius0": diameter / 2 - 1, "inputRadius1": diameter / 2,
      "inputColor0": CIColor.white, "inputColor1": CIColor.clear,
    ])?.outputImage?.cropped(to: rect)
    guard let mask else { return placed.composited(over: image) }
    return placed.applyingFilter("CIBlendWithMask", parameters: [
      kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask,
    ])
  }
}

@MainActor
final class StudioFlattenBenchmarkTests: XCTestCase {
  func testFlattenBenchmark() async throws {
    let env = ProcessInfo.processInfo.environment
    guard env["SNAPZY_SPIKE_FLATTEN"] == "1", let screenPath = env["SNAPZY_SPIKE_SCREEN"] else {
      throw XCTSkip("Set SNAPZY_SPIKE_FLATTEN=1 and SNAPZY_SPIKE_SCREEN")
    }
    let preset = env["SNAPZY_SPIKE_PRESET"] ?? AVAssetExportPresetHEVCHighestQuality
    let screenURL = URL(fileURLWithPath: screenPath)
    let cameraURL = env["SNAPZY_SPIKE_CAMERA"].map(URL.init(fileURLWithPath:))

    var variants: [(String, VideoEditorStudioRecipe?)] = [
      ("plain-reencode", nil),
      ("compositor-passthrough", .empty),
      ("cursor", VideoEditorStudioRecipe(layers: [BenchCursorLayer()])),
    ]
    if cameraURL != nil {
      variants.append(("cursor+camera", VideoEditorStudioRecipe(layers: [BenchCursorLayer(), BenchCameraLayer()])))
    }
    for (name, recipe) in variants {
      let result = try await flatten(screen: screenURL, camera: recipe?.requiredAuxiliaryTracks.isEmpty == false ? cameraURL : nil, recipe: recipe, preset: preset)
      SpikeMetrics.emit(String(
        format: "{\"variant\":\"%@\",\"preset\":\"%@\",\"size\":\"%@\",\"durationS\":%.1f,\"wallS\":%.1f,\"ratio\":%.3f,\"machineCpuPct\":%.1f}",
        name, preset, result.size, result.duration, result.wall, result.wall / result.duration, result.machineCPU
      ))
    }
  }

  private func flatten(
    screen: URL,
    camera: URL?,
    recipe: VideoEditorStudioRecipe?,
    preset: String
  ) async throws -> (size: String, duration: Double, wall: Double, machineCPU: Double) {
    let composition = AVMutableComposition()
    let screenAsset = AVURLAsset(url: screen)
    let duration = try await screenAsset.load(.duration)
    let screenSourceTracks = try await screenAsset.loadTracks(withMediaType: .video)
    let screenSource = try XCTUnwrap(screenSourceTracks.first)
    let naturalSize = try await screenSource.load(.naturalSize)
    let screenTrack = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
    try screenTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: screenSource, at: .zero)

    var auxiliary: [VideoEditorStudioAuxiliaryTrack: CMPersistentTrackID] = [:]
    if let camera {
      let cameraAsset = AVURLAsset(url: camera)
      let cameraSourceTracks = try await cameraAsset.loadTracks(withMediaType: .video)
      let cameraSource = try XCTUnwrap(cameraSourceTracks.first)
      let cameraDuration = try await cameraAsset.load(.duration)
      let track = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
      try track.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, cameraDuration)), of: cameraSource, at: .zero)
      auxiliary[.camera] = track.trackID
    }

    let session = try XCTUnwrap(AVAssetExportSession(asset: composition, presetName: preset))
    if let recipe {
      let fps = try await screenSource.load(.nominalFrameRate)
      let compositor = ZoomCompositor(
        zooms: [], renderSize: naturalSize,
        frameDuration: CMTime(value: 1, timescale: CMTimeScale(max(fps.rounded(), 1))),
        studioRecipe: recipe
      )
      session.videoComposition = try await compositor.createVideoComposition(
        for: composition,
        timeRange: CMTimeRange(start: .zero, duration: duration),
        screenTrackID: screenTrack.trackID,
        auxiliaryTrackIDs: auxiliary
      )
    }
    let output = FileManager.default.temporaryDirectory.appendingPathComponent("flatten-\(UUID().uuidString).mov")
    defer { try? FileManager.default.removeItem(at: output) }
    session.outputURL = output
    session.outputFileType = .mov

    let ticks0 = SpikeMetrics.machineTicks(), start = Date()
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
      session.exportAsynchronously { done.resume() }
    }
    let wall = Date().timeIntervalSince(start), ticks1 = SpikeMetrics.machineTicks()
    XCTAssertEqual(session.status, .completed, "\(String(describing: session.error))")
    let busy = Double(ticks1.busy - ticks0.busy), total = Double(max(ticks1.total - ticks0.total, 1))
    return ("\(Int(naturalSize.width))x\(Int(naturalSize.height))", CMTimeGetSeconds(duration), wall, busy / total * 100)
  }
}
