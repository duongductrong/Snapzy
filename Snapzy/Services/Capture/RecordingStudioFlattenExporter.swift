//
//  RecordingStudioFlattenExporter.swift
//  Snapzy
//
//  Studio recording flatten pass: re-renders the cursor-less recording through the
//  video editor compositor with the recording's own Studio layers (cursor now, camera
//  in phase 3), writing a hardware-encoded file. AVAssetReader → AVAssetWriter with
//  explicit VideoToolbox settings (see the phase 0 flatten spike), audio passed through.
//

import AVFoundation
import Foundation
import VideoToolbox

nonisolated enum RecordingStudioFlattenExporter {
  enum FlattenError: LocalizedError {
    case noVideoTrack
    case cannotRead(String)
    case cannotWrite(String)
    case appendFailed(String)
    case cancelled

    var errorDescription: String? {
      switch self {
      case .noVideoTrack: "The recording has no video track."
      case .cannotRead(let reason): "Cannot read the recording: \(reason)"
      case .cannotWrite(let reason): "Cannot write the flattened recording: \(reason)"
      case .appendFailed(let label): "Writing \(label) samples failed."
      case .cancelled: "Flatten was cancelled."
      }
    }
  }

  /// Renders `sourceURL` with `recipe` into `outputURL` (must not exist). Blocking; call
  /// off the main actor. `progress` receives 0...1 from the encoding queue.
  static func flatten(
    sourceURL: URL,
    outputURL: URL,
    recipe: VideoEditorStudioRecipe,
    frameRate: Int,
    progress: (@Sendable (Double) -> Void)? = nil
  ) async throws {
    let asset = AVURLAsset(url: sourceURL)
    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
      throw FlattenError.noVideoTrack
    }
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    let duration = try await asset.load(.duration)
    let (naturalSize, dataRate, formatDescriptions) = try await videoTrack.load(
      .naturalSize, .estimatedDataRate, .formatDescriptions
    )
    let fps = max(1, min(frameRate, 120))
    let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

    let compositor = ZoomCompositor(
      zooms: [],
      renderSize: naturalSize,
      frameDuration: frameDuration,
      studioRecipe: recipe
    )
    let timeRange = CMTimeRange(start: .zero, duration: duration)
    let videoComposition = try await compositor.createVideoComposition(
      for: asset,
      timeRange: timeRange,
      screenTrackID: videoTrack.trackID
    )

    let reader: AVAssetReader
    let writer: AVAssetWriter
    do {
      reader = try AVAssetReader(asset: asset)
      writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType(for: outputURL))
    } catch {
      throw FlattenError.cannotRead(error.localizedDescription)
    }

    let videoOutput = AVAssetReaderVideoCompositionOutput(
      videoTracks: [videoTrack],
      videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    )
    videoOutput.videoComposition = videoComposition
    videoOutput.alwaysCopiesSampleData = false
    guard reader.canAdd(videoOutput) else { throw FlattenError.cannotRead("video output") }
    reader.add(videoOutput)

    let codec = sourceCodec(formatDescriptions.first)
    let videoInput = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: videoSettings(codec: codec, size: naturalSize, sourceDataRate: dataRate, fps: fps)
    )
    videoInput.expectsMediaDataInRealTime = false
    guard writer.canAdd(videoInput) else { throw FlattenError.cannotWrite("video input") }
    writer.add(videoInput)

    var pairs: [(String, AVAssetReaderOutput, AVAssetWriterInput)] = [("video", videoOutput, videoInput)]
    for (index, track) in audioTracks.enumerated() {
      let hint = try await track.load(.formatDescriptions).first
      let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
      let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: hint)
      input.expectsMediaDataInRealTime = false
      guard reader.canAdd(output), writer.canAdd(input) else { continue }
      reader.add(output)
      writer.add(input)
      pairs.append(("audio-\(index)", output, input))
    }

    guard reader.startReading() else {
      throw FlattenError.cannotRead(reader.error?.localizedDescription ?? "unknown")
    }
    guard writer.startWriting() else {
      throw FlattenError.cannotWrite(writer.error?.localizedDescription ?? "unknown")
    }
    writer.startSession(atSourceTime: .zero)

    let totalSeconds = max(duration.seconds, 0.001)
    try await withTaskCancellationHandler {
      try await copySamples(reader: reader, writer: writer, pairs: pairs) { time in
        progress?(min(max(time.seconds / totalSeconds, 0), 1))
      }
    } onCancel: {
      reader.cancelReading()
      writer.cancelWriting()
    }
    if Task.isCancelled { throw FlattenError.cancelled }

    await writer.finishWriting()
    guard writer.status == .completed else {
      throw FlattenError.cannotWrite(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")
    }
    progress?(1)
  }

  // MARK: - Settings

  static func videoSettings(
    codec: AVVideoCodecType,
    size: CGSize,
    sourceDataRate: Float,
    fps: Int
  ) -> [String: Any] {
    // Keep the recording's quality: its own data rate plus headroom for the re-encode,
    // floored so near-static recordings still encode legible text.
    let floor = 2_500_000.0
    let bitrate = max(Double(sourceDataRate) * 1.15, floor)
    var compression: [String: Any] = [
      AVVideoAverageBitRateKey: bitrate,
      AVVideoExpectedSourceFrameRateKey: fps,
      AVVideoAllowFrameReorderingKey: false,
      kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String: true,
      kVTCompressionPropertyKey_RealTime as String: false,
    ]
    if codec == .h264 {
      compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
    }
    return [
      AVVideoCodecKey: codec,
      AVVideoWidthKey: Int(size.width.rounded()),
      AVVideoHeightKey: Int(size.height.rounded()),
      AVVideoCompressionPropertiesKey: compression,
    ]
  }

  static func sourceCodec(_ description: CMFormatDescription?) -> AVVideoCodecType {
    guard let description else { return .h264 }
    switch CMFormatDescriptionGetMediaSubType(description) {
    case kCMVideoCodecType_HEVC, kCMVideoCodecType_HEVCWithAlpha: return .hevc
    default: return .h264
    }
  }

  static func fileType(for url: URL) -> AVFileType {
    url.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
  }

  // MARK: - Copy loop

  private static func copySamples(
    reader: AVAssetReader,
    writer: AVAssetWriter,
    pairs: [(String, AVAssetReaderOutput, AVAssetWriterInput)],
    onVideoTime: @escaping @Sendable (CMTime) -> Void
  ) async throws {
    let state = CopyState()
    await withTaskGroup(of: Void.self) { group in
      for (label, output, input) in pairs {
        nonisolated(unsafe) let output = output
        nonisolated(unsafe) let input = input
        nonisolated(unsafe) let reader = reader
        nonisolated(unsafe) let writer = writer
        group.addTask {
          await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let queue = DispatchQueue(label: "com.trongduong.snapzy.studio-flatten.\(label)")
            var finished = false
            input.requestMediaDataWhenReady(on: queue) {
              while input.isReadyForMoreMediaData, !finished {
                guard let buffer = output.copyNextSampleBuffer() else {
                  finished = true
                  input.markAsFinished()
                  continuation.resume()
                  return
                }
                if label == "video" {
                  onVideoTime(CMSampleBufferGetPresentationTimeStamp(buffer))
                }
                if !input.append(buffer) {
                  state.record(FlattenError.appendFailed(label)) {
                    reader.cancelReading()
                    writer.cancelWriting()
                  }
                  finished = true
                  input.markAsFinished()
                  continuation.resume()
                  return
                }
              }
            }
          }
        }
      }
    }
    if let error = state.error { throw error }
    if reader.status == .failed {
      throw FlattenError.cannotRead(reader.error?.localizedDescription ?? "unknown")
    }
  }

  private final class CopyState: @unchecked Sendable {
    private let lock = NSLock()
    private var firstError: Error?

    var error: Error? { lock.withLock { firstError } }

    func record(_ error: Error, onFirst: () -> Void) {
      let isFirst = lock.withLock { () -> Bool in
        guard firstError == nil else { return false }
        firstError = error
        return true
      }
      if isFirst { onFirst() }
    }
  }
}
