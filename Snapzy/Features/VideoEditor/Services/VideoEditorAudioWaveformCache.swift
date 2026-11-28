//
//  VideoEditorAudioWaveformCache.swift
//  Snapzy
//
//  Background AVAssetReader peak extractor and URL-keyed cache for timeline clip waveforms.
//

import AVFoundation
import Combine
import Foundation

@MainActor
final class VideoEditorAudioWaveformCache: ObservableObject {
  @Published private(set) var waveforms: [URL: VideoEditorAudioWaveform] = [:]

  private var inFlightTokens: [URL: UUID] = [:]

  /// Explicit and nonisolated: avoids macOS 13-15 swift_task_deinitOnExecutor abort (#668).
  nonisolated deinit {}

  func waveform(for url: URL) -> VideoEditorAudioWaveform? {
    waveforms[url]
  }

  func isLoading(for url: URL) -> Bool {
    inFlightTokens[url] != nil
  }

  /// Decode and cache a downsampled waveform for `url` unless already cached or in progress.
  func ensureLoaded(for url: URL) {
    guard waveforms[url] == nil, inFlightTokens[url] == nil else { return }
    let token = UUID()
    inFlightTokens[url] = token

    Task { [weak self] in
      let extracted = await Self.extractWaveform(for: url)
      guard let self else { return }
      // Respect cache invalidation & prevent ABA stale writes if `forget(url:)` + reload raced.
      guard inFlightTokens[url] == token else { return }
      waveforms[url] = extracted
      inFlightTokens[url] = nil
    }
  }

  func forget(url: URL) {
    waveforms[url] = nil
    inFlightTokens[url] = nil
  }

  func clearAll() {
    waveforms.removeAll()
    inFlightTokens.removeAll()
  }

  // MARK: - Extraction

  private nonisolated static let sampleRate: Double = 8000

  nonisolated static func extractWaveform(for url: URL) async -> VideoEditorAudioWaveform {
    let asset = AVURLAsset(url: url)
    guard let duration = try? await asset.load(.duration) else { return .empty }
    let rawSeconds = CMTimeGetSeconds(duration)
    guard rawSeconds.isFinite, rawSeconds > 0 else { return .empty }
    let seconds = min(rawSeconds, VideoEditorAudioWaveform.maxSupportedDuration)

    guard let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
          !audioTracks.isEmpty
    else {
      return .empty
    }

    let targetBuckets = VideoEditorAudioWaveform.recommendedBucketCount(for: seconds)
    return await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        autoreleasepool {
          let result = Self.readPeaksSync(
            asset: asset,
            audioTracks: audioTracks,
            duration: seconds,
            bucketCount: targetBuckets
          )
          continuation.resume(returning: result)
        }
      }
    }
  }

  private nonisolated static let pcmOutputSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatLinearPCM,
    AVLinearPCMBitDepthKey: 32,
    AVLinearPCMIsFloatKey: true,
    AVLinearPCMIsBigEndianKey: false,
    AVLinearPCMIsNonInterleaved: false,
    AVNumberOfChannelsKey: 1,
    AVSampleRateKey: sampleRate,
  ]

  private nonisolated static func readPeaksSync(
    asset: AVAsset,
    audioTracks: [AVAssetTrack],
    duration: TimeInterval,
    bucketCount: Int
  ) -> VideoEditorAudioWaveform {
    guard let reader = try? AVAssetReader(asset: asset) else { return .empty }

    let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: pcmOutputSettings)
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { return .empty }
    reader.add(output)
    guard reader.startReading() else { return .empty }

    let clampedDuration = duration.isFinite && duration > 0
      ? min(duration, VideoEditorAudioWaveform.maxSupportedDuration)
      : 0
    let scaledSamples = min(clampedDuration * sampleRate, Double(Int.max / 2048))
    let expectedTotalSamples = max(1, Int(scaledSamples.rounded()))
    var bucketPeaks = [Float](repeating: 0, count: bucketCount)
    var sampleCursor = 0
    var globalPeak: Float = 0
    var scratchSamples: [Float] = []

    while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
      guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
      let byteLength = CMBlockBufferGetDataLength(blockBuffer)
      let floatCount = byteLength / MemoryLayout<Float>.size
      guard floatCount > 0 else { continue }

      if scratchSamples.count < floatCount {
        scratchSamples = [Float](repeating: 0, count: max(floatCount, 4096))
      }
      let copyByteCount = floatCount * MemoryLayout<Float>.size
      let copyStatus = scratchSamples.withUnsafeMutableBytes { rawBuffer -> OSStatus in
        guard let baseAddress = rawBuffer.baseAddress else {
          return kCMBlockBufferBadPointerParameterErr
        }
        return CMBlockBufferCopyDataBytes(
          blockBuffer,
          atOffset: 0,
          dataLength: copyByteCount,
          destination: baseAddress
        )
      }
      guard copyStatus == kCMBlockBufferNoErr else { continue }

      for i in 0 ..< floatCount {
        let magnitude = abs(scratchSamples[i])
        if magnitude.isFinite {
          let clampedCursor = min(sampleCursor, expectedTotalSamples)
          let bucketIdx = min(bucketCount - 1, (clampedCursor * bucketCount) / expectedTotalSamples)
          if magnitude > bucketPeaks[bucketIdx] {
            bucketPeaks[bucketIdx] = magnitude
          }
          if magnitude > globalPeak {
            globalPeak = magnitude
          }
        }
        sampleCursor &+= 1
      }
    }

    guard sampleCursor > 0, globalPeak > VideoEditorAudioWaveform.silenceFloor else { return .empty }

    let normalized = bucketPeaks.map { VideoEditorAudioWaveform.shapePeak($0, globalPeak: globalPeak) }
    return VideoEditorAudioWaveform(samples: normalized, duration: max(duration, clampedDuration))
  }
}
