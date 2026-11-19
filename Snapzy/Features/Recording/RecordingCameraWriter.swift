//
//  RecordingCameraWriter.swift
//  Snapzy
//
//  Studio recording: writes the camera overlay's frames to their own movie, on the
//  screen recording's timeline (time 0 = first screen frame, pauses cut), taken from
//  the same AVCaptureSession that drives the overlay preview.
//

import AVFoundation
import Foundation

nonisolated final class RecordingCameraWriter: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
  struct Result {
    let url: URL
    let naturalSize: CGSize
    let gaps: [RecordingTimeRange]
  }

  /// A pause between camera frames longer than this is recorded as a gap.
  static let gapThreshold: TimeInterval = 0.5

  let output = AVCaptureVideoDataOutput()

  private let outputURL: URL
  /// Host-clock sample time → recording time; `nil` drops the frame.
  private let timeProvider: @Sendable (CMTime) -> CMTime?
  private let queue = DispatchQueue(label: "com.trongduong.snapzy.recording.camera-writer", qos: .userInitiated)
  private let lock = NSLock()
  private var writer: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
  private var lastTime: CMTime?
  private var naturalSize: CGSize = .zero
  private var gaps: [RecordingTimeRange] = []
  private var isFinished = false
  private var didFail = false

  init(outputURL: URL, timeProvider: @escaping @Sendable (CMTime) -> CMTime?) {
    self.outputURL = outputURL
    self.timeProvider = timeProvider
    super.init()
    output.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    ]
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: queue)
  }

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
          let time = timeProvider(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    else { return }
    append(pixelBuffer, at: time)
  }

  /// Appends one frame at recording time `time` (internal for tests).
  func append(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
    lock.withLock {
      guard !isFinished, !didFail else { return }
      if writer == nil, !startWriter(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer)) {
        didFail = true
        return
      }
      guard let input, let adaptor, input.isReadyForMoreMediaData else { return }
      if let lastTime, time <= lastTime { return }
      let previous = lastTime?.seconds ?? 0
      if time.seconds - previous > Self.gapThreshold {
        gaps.append(RecordingTimeRange(start: previous, end: time.seconds))
      }
      if adaptor.append(pixelBuffer, withPresentationTime: time) {
        lastTime = time
      }
    }
  }

  /// Ends the movie at `duration` (the screen recording's length; the last frame holds).
  func finish(duration: TimeInterval) async -> Result? {
    output.setSampleBufferDelegate(nil, queue: nil)
    let (writer, input, lastTime, naturalSize, gaps) = lock.withLock {
      isFinished = true
      return (self.writer, self.input, self.lastTime, self.naturalSize, self.gaps)
    }
    guard let writer, let input, let lastTime, writer.status == .writing else {
      self.writer?.cancelWriting()
      try? FileManager.default.removeItem(at: outputURL)
      return nil
    }
    input.markAsFinished()
    let end = max(duration, lastTime.seconds + 1.0 / 30)
    writer.endSession(atSourceTime: CMTime(seconds: end, preferredTimescale: 600))
    await writer.finishWriting()
    guard writer.status == .completed else {
      DiagnosticLogger.shared.log(.error, .recording, "Studio camera sidecar failed", context: [
        "error": writer.error?.localizedDescription ?? "status \(writer.status.rawValue)",
      ])
      try? FileManager.default.removeItem(at: outputURL)
      return nil
    }
    var allGaps = gaps
    if duration - lastTime.seconds > Self.gapThreshold {
      allGaps.append(RecordingTimeRange(start: lastTime.seconds, end: duration))
    }
    return Result(url: outputURL, naturalSize: naturalSize, gaps: allGaps)
  }

  func cancel() {
    output.setSampleBufferDelegate(nil, queue: nil)
    let writer = lock.withLock {
      isFinished = true
      return self.writer
    }
    writer?.cancelWriting()
    try? FileManager.default.removeItem(at: outputURL)
  }

  /// Called under `lock` on the first frame.
  private func startWriter(width: Int, height: Int) -> Bool {
    do {
      try? FileManager.default.removeItem(at: outputURL)
      let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
      let bitrate = max(Double(width * height) * 30 * 0.12, 2_000_000)
      let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [
          AVVideoAverageBitRateKey: bitrate,
          AVVideoAllowFrameReorderingKey: false,
        ],
      ])
      input.expectsMediaDataInRealTime = true
      let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
      guard writer.canAdd(input) else { return false }
      writer.add(input)
      guard writer.startWriting() else { return false }
      writer.startSession(atSourceTime: .zero)
      self.writer = writer
      self.input = input
      self.adaptor = adaptor
      naturalSize = CGSize(width: width, height: height)
      return true
    } catch {
      DiagnosticLogger.shared.logError(.recording, error, "Studio camera writer setup failed")
      return false
    }
  }
}

/// Camera overlay placement captured for a Studio recording's metadata.
nonisolated struct RecordingStudioCameraLayout: Equatable, Sendable {
  var shape: RecordingCameraShape
  var isMirrored: Bool
  var normalizedFrame: CGRect
  var pointSize: CGSize
}
