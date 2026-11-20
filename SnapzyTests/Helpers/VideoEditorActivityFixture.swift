//
//  VideoEditorActivityFixture.swift
//  SnapzyTests
//
//  A 12 s Snapzy-style recording for the video agent tests: a 16 kHz tone track —
//  sound 0–2, 5–7, 10–12; silence 2–5 and 7–10 — and cursor samples: still 0–4,
//  small circles 4–7, still 7–12 (circles start and end where the cursor rests).
//

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
@testable import Snapzy

@MainActor
enum VideoEditorActivityFixture {
  /// Loaded editor state for the fixture file; callers keep it alive (the toolbox holds it weakly).
  static func makeState(in directory: URL, audio: Bool = true, cursor: Bool = true) async throws -> VideoEditorState {
    let url = try await makeVideoFile(in: directory, duration: 12, audio: audio)
    let metadata = cursor
      ? RecordingMetadata(captureSize: CGSize(width: 64, height: 64), samplesPerSecond: 30, mouseSamples: cursorSamples())
      : nil
    let state = VideoEditorState(url: url, sessionData: VideoEditorSessionData(sourceSnapshotURL: url, recordingMetadata: metadata))
    await state.loadMetadata()
    return state
  }

  /// Still at (0.25, 0.2) 0–4 s, small circles around (0.2, 0.2) 4–7 s, still at (0.25, 0.2) after.
  static func cursorSamples() -> [RecordedMouseSample] {
    (0 ... 360).map { index in
      let t = Double(index) / 30
      let point: CGPoint
      if t < 4 {
        point = CGPoint(x: 0.25, y: 0.2)
      } else if t <= 7 {
        let angle = (t - 4) * 2 * .pi
        point = CGPoint(x: 0.2 + 0.05 * cos(angle), y: 0.2 + 0.05 * sin(angle))
      } else {
        point = CGPoint(x: 0.25, y: 0.2)
      }
      return RecordedMouseSample(time: t, normalizedX: point.x, normalizedY: point.y, isInsideCapture: true)
    }
  }

  static func isLoud(_ t: Double) -> Bool {
    t < 2 || (t >= 5 && t < 7) || t >= 10
  }

  /// Encoded fixtures by `duration`/`audio`, written once per test process. The bytes never
  /// change, and the H.264 encoder on headless CI runners is slow and can stall for good, so
  /// every extra encode is another chance to hang a test until its time allowance runs out.
  private static var encodedFixtures: [String: URL] = [:]
  private static let encodeAttempts = 3
  /// How long the writer may refuse more media before an attempt is abandoned.
  private static let stallTimeout: TimeInterval = 15

  /// A fresh copy of the fixture in `directory`, so callers may move or delete it freely.
  static func makeVideoFile(in directory: URL, duration: TimeInterval, audio: Bool) async throws -> URL {
    let key = "\(duration)-\(audio)"
    let cached: URL
    if let existing = encodedFixtures[key], FileManager.default.fileExists(atPath: existing.path) {
      cached = existing
    } else {
      let cacheDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("VideoEditorActivityFixture-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
      try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
      cached = try await encodeWithRetry(in: cacheDirectory, duration: duration, audio: audio)
      encodedFixtures[key] = cached
    }
    let url = directory.appendingPathComponent("analyzer-\(UUID().uuidString).mov")
    try FileManager.default.copyItem(at: cached, to: url)
    return url
  }

  private static func encodeWithRetry(in directory: URL, duration: TimeInterval, audio: Bool) async throws -> URL {
    var lastError: Error?
    for _ in 0 ..< encodeAttempts {
      do {
        return try await encodeVideoFile(in: directory, duration: duration, audio: audio)
      } catch let error as FixtureStall {
        lastError = error
      }
    }
    throw lastError ?? FixtureStall()
  }

  private struct FixtureStall: Error, CustomStringConvertible {
    var description: String { "AVAssetWriter stopped accepting fixture media" }
  }

  private static func encodeVideoFile(in directory: URL, duration: TimeInterval, audio: Bool) async throws -> URL {
    let url = directory.appendingPathComponent("analyzer-\(UUID().uuidString).mov")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
    ])
    video.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
      kCVPixelBufferWidthKey as String: 64,
      kCVPixelBufferHeightKey as String: 64,
    ])
    writer.add(video)

    let sampleRate = 16_000.0
    var asbd = AudioStreamBasicDescription(
      mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
      mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0
    )
    var format: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(
      allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
      extensions: nil, formatDescriptionOut: &format
    )
    let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
      AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ])
    audioInput.expectsMediaDataInRealTime = false
    if audio { writer.add(audioInput) }

    guard writer.startWriting() else { throw writer.error ?? NSError(domain: "VideoEditorActivityFixture", code: 1) }
    writer.startSession(atSourceTime: .zero)

    // Feed whichever input is ready and behind: waiting on one input while the writer waits
    // for the other to catch up deadlocks (it did under parallel test load).
    let frameRate: Int32 = 10
    let framesPerStep = Int(sampleRate / Double(frameRate))
    let steps = Int(duration * Double(frameRate))
    var videoIndex = 0
    var audioIndex = audio ? 0 : steps
    var lastProgress = Date()
    while videoIndex < steps || audioIndex < steps {
      let progressMark = videoIndex + audioIndex
      defer {
        if videoIndex + audioIndex != progressMark { lastProgress = Date() }
      }
      if Date().timeIntervalSince(lastProgress) > stallTimeout {
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: url)
        throw FixtureStall()
      }
      var progressed = false
      if videoIndex < steps, videoIndex <= audioIndex || audioIndex >= steps, video.isReadyForMoreMediaData {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard let buffer, adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(videoIndex), timescale: frameRate)) else {
          throw writer.error ?? NSError(domain: "VideoEditorActivityFixture", code: 2)
        }
        videoIndex += 1
        progressed = true
      }
      if audioIndex < steps, audioIndex <= videoIndex || videoIndex >= steps, audioInput.isReadyForMoreMediaData, let format {
        try Self.appendAudio(step: audioIndex, framesPerStep: framesPerStep, sampleRate: sampleRate, format: format, to: audioInput, writer: writer)
        audioIndex += 1
        progressed = true
      }
      if !progressed {
        // Neither eligible input is ready: let the other one go first if it can.
        if videoIndex < steps, video.isReadyForMoreMediaData, audioIndex < steps, !audioInput.isReadyForMoreMediaData {
          var buffer: CVPixelBuffer?
          CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer)
          guard let buffer, adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(videoIndex), timescale: frameRate)) else {
            throw writer.error ?? NSError(domain: "VideoEditorActivityFixture", code: 2)
          }
          videoIndex += 1
        } else if audioIndex < steps, audioInput.isReadyForMoreMediaData, let format {
          try Self.appendAudio(step: audioIndex, framesPerStep: framesPerStep, sampleRate: sampleRate, format: format, to: audioInput, writer: writer)
          audioIndex += 1
        } else {
          try await Task.sleep(nanoseconds: 1_000_000)
        }
      }
    }
    video.markAsFinished()
    if audio { audioInput.markAsFinished() }
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? NSError(domain: "VideoEditorActivityFixture", code: 5) }
    return url
  }

  private static func appendAudio(
    step: Int,
    framesPerStep: Int,
    sampleRate: Double,
    format: CMAudioFormatDescription,
    to input: AVAssetWriterInput,
    writer: AVAssetWriter
  ) throws {
    let firstFrame = step * framesPerStep
    var pcm = [Int16](repeating: 0, count: framesPerStep)
    for offset in 0 ..< framesPerStep {
      let t = Double(firstFrame + offset) / sampleRate
      pcm[offset] = Self.isLoud(t) ? Int16(16_000 * sin(2 * .pi * 440 * t)) : 0
    }
    let bytes = framesPerStep * 2
    var block: CMBlockBuffer?
    CMBlockBufferCreateWithMemoryBlock(
      allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil, customBlockSource: nil,
      offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block
    )
    guard let block else { throw NSError(domain: "VideoEditorActivityFixture", code: 3) }
    pcm.withUnsafeBytes { raw in
      _ = CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
    }
    var sample: CMSampleBuffer?
    CMAudioSampleBufferCreateReadyWithPacketDescriptions(
      allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: framesPerStep,
      presentationTimeStamp: CMTime(value: CMTimeValue(firstFrame), timescale: CMTimeScale(sampleRate)),
      packetDescriptions: nil, sampleBufferOut: &sample
    )
    guard let sample, input.append(sample) else { throw writer.error ?? NSError(domain: "VideoEditorActivityFixture", code: 4) }
  }
}
