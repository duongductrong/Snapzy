//
//  ScrollingCaptureFrameSource.swift
//  Snapzy
//
//  Region-scoped ScreenCaptureKit stream used for low-latency scrolling preview.
//

import AppKit
import CoreImage
import CoreMedia
import Foundation
import ScreenCaptureKit

final class ScrollingCaptureFrameSource: NSObject {
  private let sampleQueue = DispatchQueue(
    label: "com.snapzy.scrolling-capture.preview-stream",
    qos: .userInteractive
  )
  private let minimumPublishInterval: TimeInterval
  private let ciContext: CIContext

  private var stream: SCStream?
  private nonisolated(unsafe) var lastPublishedAt: TimeInterval = 0
  private var onFrame: ((CGImage) -> Void)?
  private var onFailure: ((String) -> Void)?

  init(previewFPS: Int = 30) {
    minimumPublishInterval = 1.0 / Double(max(1, previewFPS))
    ciContext = CIContext(options: [.cacheIntermediates: false])
  }

  @MainActor
  func start(
    with context: ScreenCaptureManager.PreparedAreaCaptureContext,
    frameHandler: @escaping (CGImage) -> Void,
    failureHandler: @escaping (String) -> Void
  ) async throws {
    stop()

    onFrame = frameHandler
    onFailure = failureHandler
    lastPublishedAt = 0

    let configuration = ScreenCaptureManager.shared.makeAreaStreamConfiguration(
      from: context,
      maximumFrameRate: 30,
      showsCursor: false
    )
    let stream = SCStream(filter: context.contentFilter, configuration: configuration, delegate: self)
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
    self.stream = stream
    try await stream.startCapture()
  }

  @MainActor
  func stop() {
    let activeStream = stream
    stream = nil
    onFrame = nil
    onFailure = nil

    guard let activeStream else { return }

    do {
      try activeStream.removeStreamOutput(self, type: .screen)
    } catch {
      // Best-effort teardown: stream may already be winding down.
    }

    Task.detached(priority: .userInitiated) {
      do {
        try await activeStream.stopCapture()
      } catch {
        // Best-effort teardown: stream may already be stopped.
      }
    }
  }
}

extension ScrollingCaptureFrameSource: SCStreamOutput {
  nonisolated func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    autoreleasepool {
      guard type == .screen, sampleBuffer.isValid else { return }
      guard let pixelBuffer = sampleBuffer.imageBuffer else { return }

      if
        let attachments = CMSampleBufferGetSampleAttachmentsArray(
          sampleBuffer,
          createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
        let statusRaw = attachments.first?[.status] as? Int,
        let status = SCFrameStatus(rawValue: statusRaw),
        status != .complete
      {
        return
      }

      let now = ProcessInfo.processInfo.systemUptime
      guard now - lastPublishedAt >= minimumPublishInterval else { return }

      let imageRect = CGRect(
        x: 0,
        y: 0,
        width: CVPixelBufferGetWidth(pixelBuffer),
        height: CVPixelBufferGetHeight(pixelBuffer)
      )
      let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
      guard let cgImage = ciContext.createCGImage(ciImage, from: imageRect) else {
        return
      }

      lastPublishedAt = now
      DispatchQueue.main.async { [weak self] in
        self?.onFrame?(cgImage)
      }
    }
  }
}

extension ScrollingCaptureFrameSource: SCStreamDelegate {
  nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
    DispatchQueue.main.async { [weak self] in
      self?.onFailure?(error.localizedDescription)
    }
  }
}
