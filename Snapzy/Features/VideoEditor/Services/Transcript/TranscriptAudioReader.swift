//
//  TranscriptAudioReader.swift
//  Snapzy
//
//  Reads audio tracks of an asset as PCM buffers in a given format and time range
//  (mixing several tracks down to the format's channel count).
//

import AVFoundation
import Foundation

nonisolated enum TranscriptAudioReader {
  /// 16 kHz mono Float32: what `SFSpeechRecognizer` is fed.
  static func speechFormat() -> AVAudioFormat? {
    AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)
  }

  /// Calls `handle` with each buffer of `range` (whole asset when nil) and the
  /// seconds of audio delivered so far, relative to the start of `range`.
  static func read(
    asset: AVAsset,
    tracks: [AVAssetTrack],
    format: AVAudioFormat,
    range: ClosedRange<TimeInterval>? = nil,
    handle: (AVAudioPCMBuffer, TimeInterval) async throws -> Void
  ) async throws {
    let reader = try AVAssetReader(asset: asset)
    if let range {
      reader.timeRange = CMTimeRange(
        start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
        duration: CMTime(seconds: range.upperBound - range.lowerBound, preferredTimescale: 600)
      )
    }
    let isFloat = format.commonFormat == .pcmFormatFloat32
    let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: format.sampleRate,
      AVNumberOfChannelsKey: Int(format.channelCount),
      AVLinearPCMBitDepthKey: isFloat ? 32 : 16,
      AVLinearPCMIsFloatKey: isFloat,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: !format.isInterleaved,
    ])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw VideoEditorTranscriptError.failed("audio reader") }
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? VideoEditorTranscriptError.failed("audio reader") }

    var delivered = 0.0
    while let sample = output.copyNextSampleBuffer() {
      try Task.checkCancellation()
      let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
      guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { continue }
      buffer.frameLength = frames
      let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
        sample, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList
      )
      guard status == noErr else { continue }
      delivered += Double(frames) / format.sampleRate
      try await handle(buffer, delivered)
    }
    if reader.status == .failed { throw reader.error ?? VideoEditorTranscriptError.failed("audio reader") }
  }
}
