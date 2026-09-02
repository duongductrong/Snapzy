//
//  ScrollingCaptureFrameRing.swift
//  Snapzy
//
//  Bounded frame history shared by scrolling capture preview and commit lanes.
//

import CoreGraphics
import Foundation

enum ScrollingCaptureCommitFrameSource {
  case stream
  case stillFallback
}

struct ScrollingCaptureFrame {
  let sequenceNumber: Int
  let image: CGImage
  let capturedAt: TimeInterval
  let motionScore: Double?

  var pixelWidth: Int { image.width }
  var pixelHeight: Int { image.height }
}

final class ScrollingCaptureFrameRing {
  private let capacity: Int
  private(set) var frames: [ScrollingCaptureFrame] = []
  private(set) var lastCommittedSequenceNumber: Int?

  init(capacity: Int = 8) {
    self.capacity = max(1, capacity)
  }

  var latest: ScrollingCaptureFrame? {
    frames.last
  }

  @discardableResult
  func append(_ frame: ScrollingCaptureFrame) -> ScrollingCaptureFrame {
    frames.append(frame)
    if frames.count > capacity {
      frames.removeFirst(frames.count - capacity)
    }
    return frame
  }

  func latestFrame(after sequenceNumber: Int?) -> ScrollingCaptureFrame? {
    guard let sequenceNumber else { return latest }
    return frames.last { $0.sequenceNumber > sequenceNumber }
  }

  func latestFrame(
    capturedAfter timestamp: TimeInterval,
    afterSequenceNumber sequenceNumber: Int?
  ) -> ScrollingCaptureFrame? {
    frames.last { frame in
      frame.capturedAt > timestamp
        && (sequenceNumber.map { frame.sequenceNumber > $0 } ?? true)
    }
  }

  func markCommitted(sequenceNumber: Int?) {
    guard let sequenceNumber else { return }
    lastCommittedSequenceNumber = max(lastCommittedSequenceNumber ?? sequenceNumber, sequenceNumber)
  }

  func reset() {
    frames.removeAll()
    lastCommittedSequenceNumber = nil
  }
}
