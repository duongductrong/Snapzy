import Dispatch
import Foundation

/// Serializes writes onto one fd, off the cooperative thread pool.
///
/// Writes run on a private serial queue, so ordering is exactly enqueue
/// order — the property the channel needs to guarantee blob frames precede
/// the envelope that references them. A `write()` that blocks (a stalled
/// peer) blocks this queue only, which is the backpressure design: the
/// kernel socket buffer is the bound, and a caller that keeps firing into a
/// stalled peer blocks only itself.
final class FrameWriter: @unchecked Sendable {
  private let fd: Int32
  private let queue: DispatchQueue
  private var closed = false

  init(fd: Int32, label: String) {
    self.fd = fd
    self.queue = DispatchQueue(label: label)
  }

  /// Enqueues a full frame. `completion` reports failure; nil means written.
  /// A writer that has failed stays failed: every subsequent completion
  /// receives the same error, so a broken connection cannot be half-ignored.
  func write(_ data: Data, completion: (@Sendable (Error?) -> Void)? = nil) {
    queue.async { [weak self] in
      guard let self else { return }
      if self.closed {
        completion?(ProtocolError.channelClosed)
        return
      }
      data.withUnsafeBytes { bytes in
        var written = 0
        while written < bytes.count {
          let n = Darwin.write(self.fd, bytes.baseAddress!.advanced(by: written), bytes.count - written)
          if n > 0 {
            written += n
            continue
          }
          if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
            usleep(2_000)
            continue
          }
          self.closed = true
          completion?(ProtocolError.peerDied)
          return
        }
        completion?(nil)
      }
    }
  }

  /// Waits for all pending writes, then runs `completion`. No new writes are
  /// accepted afterwards.
  func close(completion: @escaping @Sendable () -> Void) {
    queue.async { [weak self] in
      self?.closed = true
      completion()
    }
  }
}
