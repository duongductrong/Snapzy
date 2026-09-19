//
//  SingleFrameStreamCaptureSession.swift
//  Snapzy
//
//  macOS 13 fallback for single-frame ScreenCaptureKit capture
//  (`SCScreenshotManager` requires macOS 14).
//

import CoreGraphics
import CoreImage
import CoreMedia
import ScreenCaptureKit

/// Captures a single frame via `SCStream` (macOS 13 fallback where
/// `SCScreenshotManager` is unavailable).
///
/// The session owns the stream, the stream output and the stream delegate for the
/// whole capture so they stay alive until the first frame arrives (`SCStream` does
/// not retain them). Every outcome — first complete frame, stream error, timeout or
/// cancellation — funnels through a single lock-guarded `finish`, so the continuation
/// always resumes exactly once and the wait can never hang forever (GitHub issue #286).
final class SingleFrameStreamCaptureSession: NSObject, @unchecked Sendable {
  /// Upper bound for waiting on the first frame. A healthy stream delivers the first
  /// frame in well under a second.
  nonisolated static let defaultTimeout: TimeInterval = 5

  /// Shared CIContext: immutable and documented thread-safe for concurrent rendering;
  /// avoids per-frame allocation on delivered frames.
  // CIContext is internally thread-safe and is shared by the nonisolated frame callback.
  private nonisolated static let sharedCIContext = CIContext()

  private let lock = NSLock()
  private nonisolated(unsafe) var continuation: CheckedContinuation<CGImage, Error>?
  private nonisolated(unsafe) var stream: SCStream?
  private nonisolated(unsafe) var timeoutTask: Task<Void, Never>?
  private nonisolated(unsafe) var finished = false

  /// Starts a single-frame capture and returns the first complete frame.
  ///
  /// - Throws: `CaptureError.captureFailed` when the stream cannot be set up or no
  ///   complete frame arrives within `timeout`, `CaptureError.cancelled` on task
  ///   cancellation, or any error reported by the stream itself.
  @MainActor
  static func capture(
    contentFilter: SCContentFilter,
    configuration: SCStreamConfiguration,
    timeout: TimeInterval = defaultTimeout
  ) async throws -> CGImage {
    let session = SingleFrameStreamCaptureSession()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        session.begin(
          contentFilter: contentFilter,
          configuration: configuration,
          timeout: timeout,
          continuation: continuation
        )
      }
    } onCancel: {
      session.cancel()
    }
  }

  @MainActor
  private func begin(
    contentFilter: SCContentFilter,
    configuration: SCStreamConfiguration,
    timeout: TimeInterval,
    continuation: CheckedContinuation<CGImage, Error>
  ) {
    arm(continuation: continuation, timeout: timeout)

    let stream = SCStream(filter: contentFilter, configuration: configuration, delegate: self)
    lock.lock()
    self.stream = stream
    lock.unlock()

    do {
      try stream.addStreamOutput(
        self,
        type: .screen,
        sampleHandlerQueue: DispatchQueue(label: "com.trongduong.snapzy.single-frame-capture")
      )
    } catch {
      finish(.failure(error))
      return
    }

    Task { [weak self] in
      do {
        try await stream.startCapture()
      } catch {
        self?.finish(.failure(error))
      }
    }
  }

  /// Installs the continuation and arms the timeout. Nonisolated (lock-guarded) so
  /// tests can drive the session's state machine without a real `SCStream` (which
  /// requires Screen Recording permission).
  nonisolated func arm(continuation: CheckedContinuation<CGImage, Error>, timeout: TimeInterval) {
    lock.lock()
    self.continuation = continuation
    lock.unlock()

    let timeoutTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
      guard !Task.isCancelled else { return }
      self?.finish(.failure(CaptureError.captureFailed(L10n.ScreenCapture.captureTimedOut)))
    }
    lock.lock()
    self.timeoutTask = timeoutTask
    lock.unlock()
  }

  /// Terminates the wait, if still pending, without delivering a frame.
  nonisolated func cancel() {
    finish(.failure(CaptureError.cancelled))
  }

  /// Funnels every outcome (frame, stream error, timeout, cancellation) into a single
  /// exactly-once continuation resume, then tears the stream down.
  nonisolated func finish(_ result: Result<CGImage, Error>) {
    lock.lock()
    guard !finished else {
      lock.unlock()
      return
    }
    finished = true
    let continuation = self.continuation
    self.continuation = nil
    let timeoutTask = self.timeoutTask
    self.timeoutTask = nil
    let stream = self.stream
    self.stream = nil
    lock.unlock()

    timeoutTask?.cancel()
    switch result {
    case .success(let image):
      continuation?.resume(returning: image)
    case .failure(let error):
      continuation?.resume(throwing: error)
    }
    if let stream {
      Task {
        try? await stream.stopCapture()
      }
    }
  }
}

// MARK: - SCStreamOutput

extension SingleFrameStreamCaptureSession: SCStreamOutput {
  nonisolated func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .screen else { return }

    // Check that the sample buffer contains a valid image
    guard let imageBuffer = sampleBuffer.imageBuffer else { return }

    // Skip frames that are not fully rendered (e.g. idle/blank first frames)
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
      as? [[SCStreamFrameInfo: Any]],
      let statusRaw = attachments.first?[.status] as? Int,
      let status = SCFrameStatus(rawValue: statusRaw),
      status != .complete {
      return
    }

    // Convert CVPixelBuffer to CGImage
    let ciImage = CIImage(cvPixelBuffer: imageBuffer)
    let rect = CGRect(
      x: 0, y: 0,
      width: CVPixelBufferGetWidth(imageBuffer),
      height: CVPixelBufferGetHeight(imageBuffer)
    )

    guard let cgImage = Self.sharedCIContext.createCGImage(ciImage, from: rect) else {
      finish(.failure(CaptureError.captureFailed(L10n.ScreenCapture.failedToCreateImageFromFrame)))
      return
    }

    finish(.success(cgImage))
  }
}

// MARK: - SCStreamDelegate

extension SingleFrameStreamCaptureSession: SCStreamDelegate {
  nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
    finish(.failure(error))
  }
}
