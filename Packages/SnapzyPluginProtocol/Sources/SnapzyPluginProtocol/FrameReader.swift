import Dispatch
import Foundation

/// Reads complete `Frame`s off a file descriptor without parking a
/// cooperative thread: a `DispatchSourceRead` on its own serial queue
/// accumulates bytes, and each `nextFrame()` awaits a continuation that the
/// source resumes when a full frame is buffered.
///
/// One outstanding `nextFrame()` at a time — the channel's read loop is the
/// only caller, and that is by design: frames are consumed in order.
///
/// EOF and read errors surface as `ProtocolError.peerDied`, so a caller never
/// has to map errno itself.
final class FrameReader: @unchecked Sendable {
  private let fd: Int32
  private let queue: DispatchQueue
  private var source: DispatchSourceRead?
  private var buffer = Data()
  private var waiting: CheckedContinuation<Frame, Error>?
  private var stopped = false

  init(fd: Int32, label: String) {
    self.fd = fd
    self.queue = DispatchQueue(label: label)
  }

  func start() {
    queue.async {
      guard self.source == nil, !self.stopped else { return }
      let source = DispatchSource.makeReadSource(fileDescriptor: self.fd, queue: self.queue)
      source.setEventHandler { [weak self] in self?.drainAvailableBytes() }
      source.setCancelHandler { [weak self] in
        // The fd is not closed here: the caller owns descriptor lifetime.
        // Closing on cancel made a cancelled reader destroy whatever fd the
        // OS later recycled the number for — a cross-test socket killer.
        self?.source = nil
      }
      self.source = source
      source.resume()
    }
  }

  /// Awaits the next complete frame. Throws `ProtocolError.peerDied` on EOF
  /// or read failure, `ProtocolError.channelClosed` after `stop()`.
  func nextFrame() async throws -> Frame {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Frame, Error>) in
        queue.async {
          if self.stopped {
            continuation.resume(throwing: ProtocolError.channelClosed)
            return
          }
          if let frame = self.extractFrame() {
            continuation.resume(returning: frame)
            return
          }
          self.waiting = continuation
        }
      }
    } onCancel: {
      queue.async {
        guard let waiting = self.waiting else { return }
        self.waiting = nil
        waiting.resume(throwing: CancellationError())
      }
    }
  }

  /// Stops the source and fails any pending read. Safe to call more than once.
  func stop() {
    queue.async {
      self.stopped = true
      if let source = self.source {
        source.cancel()
        self.source = nil
      }
      if let waiting = self.waiting {
        self.waiting = nil
        waiting.resume(throwing: ProtocolError.channelClosed)
      }
    }
  }

  // All queue-confined below.

  private func drainAvailableBytes() {
    var chunk = [UInt8](repeating: 0, count: 64 * 1024)
    let n = read(fd, &chunk, chunk.count)
    if n > 0 {
      buffer.append(contentsOf: chunk[0..<n])
    } else if n == 0 {
      // A peer that died mid-frame is a truncation, not a clean death —
      // the diagnostic difference is what the host logs and shows.
      failPending(buffer.isEmpty ? ProtocolError.peerDied : ProtocolError.truncatedFrame)
      source?.cancel()
      return
    } else {
      // EAGAIN: no more data right now.
      if errno == EAGAIN || errno == EWOULDBLOCK { return }
      failPending(ProtocolError.peerDied)
      source?.cancel()
      return
    }
    deliverIfPossible()
  }

  private func deliverIfPossible() {
    guard let waiting else { return }
    guard let frame = extractFrame() else { return }
    self.waiting = nil
    waiting.resume(returning: frame)
  }

  private func extractFrame() -> Frame? {
    do {
      let (frame, consumed) = try Frame.decode(from: buffer)
      if consumed < buffer.count {
        buffer = buffer.subdata(in: consumed..<buffer.count)
      } else {
        buffer.removeAll(keepingCapacity: true)
      }
      return frame
    } catch ProtocolError.truncatedFrame {
      return nil
    } catch {
      failPending(error)
      source?.cancel()
      return nil
    }
  }

  private func failPending(_ error: Error) {
    if let waiting {
      self.waiting = nil
      waiting.resume(throwing: error)
    }
  }
}
