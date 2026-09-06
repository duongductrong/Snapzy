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

/// Samples the whole viewport so freshly delivered animation frames are not
/// mistaken for a settled page. Re-observing an unchanged frame is intentional:
/// ScreenCaptureKit can stop publishing when the desktop is idle.
struct ScrollingCaptureFrameStability {
  private var previousPixels: [UInt8]?
  private var lastChangedAt: TimeInterval?
  static let quietInterval: TimeInterval = 0.10

  mutating func observe(_ image: CGImage, at time: TimeInterval) -> Bool {
    let size = 64
    var pixels = [UInt8](repeating: 0, count: size * size)
    let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard let context = CGContext(
        data: buffer.baseAddress,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
      ) else { return false }
      context.interpolationQuality = .low
      context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
      return true
    }
    guard drew else { return false }
    if let previousPixels {
      let difference = zip(pixels, previousPixels).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
      if Double(difference) / Double(pixels.count) > 0.5 {
        lastChangedAt = time
      }
    } else {
      lastChangedAt = time
    }
    previousPixels = pixels
    return time - (lastChangedAt ?? time) >= Self.quietInterval
  }
}
