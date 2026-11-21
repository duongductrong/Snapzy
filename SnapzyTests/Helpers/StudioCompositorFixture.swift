//
//  StudioCompositorFixture.swift
//  SnapzyTests
//
//  Tiny solid-color movies and a first-frame reader for compositor tests.
//

import AVFoundation
import CoreVideo
import Foundation

enum StudioCompositorFixture {
  enum Color { case red, green, blue }

  struct Pixel: CustomStringConvertible {
    let r: Int, g: Int, b: Int

    func isDominantly(_ color: Color) -> Bool {
      switch color {
      case .red: r > 180 && g < 80 && b < 80
      case .green: g > 180 && r < 80 && b < 80
      case .blue: b > 180 && r < 80 && g < 80
      }
    }

    var description: String { "rgb(\(r), \(g), \(b))" }
  }

  /// Writes a 0.5 s, 30 fps H.264 movie filled with `color`.
  static func solidMovie(color: Color, size: CGSize, in directory: URL) async throws -> URL {
    let url = directory.appendingPathComponent("\(color)-\(UUID().uuidString).mov")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: Int(size.width),
      AVVideoHeightKey: Int(size.height),
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: Int(size.width),
      kCVPixelBufferHeightKey as String: Int(size.height),
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let bgra: [UInt8] = switch color {
    case .red: [0, 0, 255, 255]
    case .green: [0, 255, 0, 255]
    case .blue: [255, 0, 0, 255]
    }
    for frame in 0 ..< 15 {
      while !input.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 2_000_000)
      }
      guard let pool = adaptor.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }
      var buffer: CVPixelBuffer?
      CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
      guard let buffer else { throw CocoaError(.fileWriteUnknown) }
      fill(buffer, bgra: bgra)
      adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    return url
  }

  /// Appends the movie's video track to `composition`; returns the new track ID.
  static func insertVideo(from url: URL, into composition: AVMutableComposition) async throws -> CMPersistentTrackID {
    let asset = AVURLAsset(url: url)
    guard let source = try await asset.loadTracks(withMediaType: .video).first,
          let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else { throw CocoaError(.fileReadUnknown) }
    let duration = try await asset.load(.duration)
    try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: .zero)
    return track.trackID
  }

  /// Renders the first composed frame and samples one pixel (top-left origin).
  static func firstPixel(
    of asset: AVAsset,
    videoComposition: AVVideoComposition,
    at point: CGPoint
  ) async throws -> Pixel {
    let reader = try AVAssetReader(asset: asset)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    let output = AVAssetReaderVideoCompositionOutput(videoTracks: tracks, videoSettings: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ])
    output.videoComposition = videoComposition
    reader.add(output)
    guard reader.startReading(),
          let sample = output.copyNextSampleBuffer(),
          let buffer = CMSampleBufferGetImageBuffer(sample)
    else { throw reader.error ?? CocoaError(.fileReadUnknown) }
    reader.cancelReading()

    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let row = CVPixelBufferGetBytesPerRow(buffer)
    let x = min(max(Int(point.x), 0), CVPixelBufferGetWidth(buffer) - 1)
    let y = min(max(Int(point.y), 0), CVPixelBufferGetHeight(buffer) - 1)
    let pixel = base + y * row + x * 4
    return Pixel(r: Int(pixel[2]), g: Int(pixel[1]), b: Int(pixel[0]))
  }

  private static func fill(_ buffer: CVPixelBuffer, bgra: [UInt8]) {
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
}
