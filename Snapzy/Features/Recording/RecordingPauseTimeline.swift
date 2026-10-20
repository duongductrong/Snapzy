//
//  RecordingPauseTimeline.swift
//  Snapzy
//
//  Maps capture-clock sample timestamps onto the written timeline, cutting out paused spans.
//

import CoreMedia

/// Pause and resume points are measured on the host time clock, the same clock ScreenCaptureKit
/// and AVCaptureSession stamp samples with, so each sample is classified by its own timestamp
/// rather than by when it happens to reach the writer queue.
nonisolated struct RecordingPauseTimeline: Sendable {
  /// Total paused time removed from samples captured after the latest resume.
  private(set) var accumulatedOffset: CMTime = .zero
  private var pausedAt: CMTime?
  private var resumedAt: CMTime?
  private(set) var lastVideoTime: CMTime?

  var isPaused: Bool { pausedAt != nil }

  mutating func pause(at hostTime: CMTime) {
    guard pausedAt == nil, hostTime.isNumeric else { return }
    pausedAt = hostTime
  }

  mutating func resume(at hostTime: CMTime) {
    guard let pausedAt, hostTime.isNumeric else { return }
    let pausedDuration = CMTimeSubtract(hostTime, pausedAt)
    if pausedDuration > .zero {
      accumulatedOffset = CMTimeAdd(accumulatedOffset, pausedDuration)
    }
    self.pausedAt = nil
    resumedAt = CMTimeMaximum(hostTime, pausedAt)
  }

  /// Output timestamp for a sample, or nil when it was captured while paused.
  /// Samples captured before the latest resume but delivered after it are dropped too.
  func outputTime(for sourceTime: CMTime) -> CMTime? {
    guard sourceTime.isNumeric else { return nil }
    if let pausedAt, sourceTime >= pausedAt { return nil }
    if let resumedAt, sourceTime < resumedAt { return nil }
    return accumulatedOffset > .zero ? CMTimeSubtract(sourceTime, accumulatedOffset) : sourceTime
  }

  /// Like `outputTime(for:)`, but also rejects frames that would not advance the video track:
  /// AVAssetWriter fails the whole file on a non-increasing video presentation time.
  mutating func acceptVideoFrame(at sourceTime: CMTime) -> CMTime? {
    guard let output = outputTime(for: sourceTime) else { return nil }
    if let lastVideoTime, output <= lastVideoTime { return nil }
    lastVideoTime = output
    return output
  }
}
