import Foundation

/// The framed transport: a full-duplex, multiplexed channel over one socket.
///
/// Responsibilities, and nothing else:
/// - framing (via `FrameReader`/`FrameWriter`), with caps enforced on both
///   directions;
/// - id correlation: `request` awaits a reply; `fire` sends without one;
///   `reply(to:)` answers an incoming request id;
/// - blob frames: a payload can carry `{"blob": <index>}` placeholders
///   resolved against the `blobs` list passed to the send, and received
///   envelopes deliver their referenced bytes in `Reply.blobs`;
/// - peer death: one read error or EOF fails every outstanding request with
///   `ProtocolError.peerDied` and ends `events`;
/// - forward compatibility: unknown kinds are delivered as events, never
///   fatal, never guessed at.
///
/// Ids are parity-partitioned: the host side assigns even ids, the plugin
/// side odd ones. An incoming envelope with the *peer's* parity is a
/// message; one with *our* parity must match a pending request or the
/// channel fails. That is what makes "monotonic per direction" collision-free
/// in both directions simultaneously.
public actor FrameChannel {
  public struct Event: Sendable, Equatable {
    public let envelope: Envelope
  }

  public struct Reply: Sendable, Equatable {
    public let kind: String
    public let payload: JSONValue
    public let blobs: [UInt64: Data]
  }

  /// Maximum requests awaiting a reply in one direction.
  public static let maxInFlight = 64

  public enum IDParity: Sendable {
    case even
    case odd

    var start: UInt64 { self == .even ? 0 : 1 }
  }

  private struct Pending {
    let continuation: CheckedContinuation<Reply, Error>
    let timeoutTask: Task<Void, Never>?
  }

  private let reader: FrameReader
  private let writer: FrameWriter
  private let blobTable = BlobTable()
  private let parity: IDParity
  private let eventContinuation: AsyncStream<Event>.Continuation
  public let events: AsyncStream<Event>

  private var nextEnvelopeID: UInt64
  private var nextBlobID: UInt64
  private var pending: [UInt64: Pending] = [:]
  private var readTask: Task<Void, Never>?
  private var closed = false

  public init(readFD: Int32, writeFD: Int32, parity: IDParity, label: String) {
    // Without this, a write to a peer-closed socket raises SIGPIPE and
    // kills the whole process — containment demands an error instead.
    var enabled: Int32 = 1
    _ = setsockopt(readFD, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
    _ = setsockopt(writeFD, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
    self.reader = FrameReader(fd: readFD, label: "\(label).reader")
    self.writer = FrameWriter(fd: writeFD, label: "\(label).writer")
    self.parity = parity
    self.nextEnvelopeID = parity.start
    self.nextBlobID = parity.start
    let (stream, continuation) = AsyncStream<Event>.makeStream()
    self.events = stream
    self.eventContinuation = continuation
  }

  /// Begins the read loop. Idempotent. The channel is unusable for receives
  /// until this is called; sends work immediately.
  public func start() {
    guard readTask == nil, !closed else { return }
    reader.start()
    readTask = Task { [weak self] in await self?.readLoop() }
  }

  /// Sends a request and awaits its reply. `timeout` fails only this request;
  /// the channel keeps serving.
  public func request(
    _ kind: String,
    payload: JSONValue,
    blobs: [Data] = [],
    timeout: Duration? = nil
  ) async throws -> Reply {
    let id = try nextEnvelopeIDValue()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Reply, Error>) in
        var timeoutTask: Task<Void, Never>?
        if let timeout {
          timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.timeoutRequest(id: id)
          }
        }
        pending[id] = Pending(continuation: continuation, timeoutTask: timeoutTask)
        sendEnvelope(id: id, kind: kind, payload: payload, blobs: blobs) { error in
          if let error { Task { await self.failRequest(id: id, error: error) } }
        }
      }
    } onCancel: {
      Task { await self.failRequest(id: id, error: CancellationError()) }
    }
  }

  /// Sends a message that expects no reply (progress, log, cancel).
  public func fire(_ kind: String, payload: JSONValue, blobs: [Data] = []) throws {
    try ensureOpen()
    let id = try nextEnvelopeIDValue()
    sendEnvelope(id: id, kind: kind, payload: payload, blobs: blobs, completion: nil)
  }

  /// Replies to an incoming request id. The id must have the peer's parity;
  /// anything else is a protocol violation.
  public func reply(to id: UInt64, kind: String, payload: JSONValue, blobs: [Data] = []) throws {
    try ensureOpen()
    guard idParity(id) != parity else {
      throw ProtocolError.protocolViolation("reply id \(id) has the wrong parity")
    }
    sendEnvelope(id: id, kind: kind, payload: payload, blobs: blobs, completion: nil)
  }

  /// Sends a `close` frame, fails outstanding requests, and tears down.
  /// Idempotent; safe after the peer is already gone.
  public func close() async {
    guard !closed else { return }
    closed = true
    let frame = try? Frame.close.encode()
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      writer.write(frame ?? Data()) { [weak self] _ in
        guard let self else {
          continuation.resume()
          return
        }
        self.writer.close { [weak self] in
          Task {
            guard let self else {
              continuation.resume()
              return
            }
            self.reader.stop()
            await self.failAll(ProtocolError.channelClosed)
            self.eventContinuation.finish()
            continuation.resume()
          }
        }
      }
    }
  }

  /// Requests currently awaiting a reply. Internal for tests (@testable):
  /// the in-flight cap test needs to observe when requests are registered.
  var pendingRequestCount: Int { pending.count }

  // MARK: Sending

  private func sendEnvelope(
    id: UInt64,
    kind: String,
    payload: JSONValue,
    blobs: [Data],
    completion: (@Sendable (Error?) -> Void)?
  ) {
    // Blob ids come from the same parity space as envelope ids; they never
    // correlate with envelopes, so sharing the parity keeps the peer's blob
    // table collision-free in both directions.
    var blobIDs: [UInt64] = []
    for _ in 0..<payload.blobPlaceholderCount {
      blobIDs.append(nextBlobID)
      nextBlobID &+= 2
    }
    let rewritten: JSONValue
    let blobFrames: [(id: UInt64, data: Data)]
    do {
      (rewritten, blobFrames) = try payload.embeddingBlobs(blobs, ids: blobIDs)
    } catch {
      completion?(error)
      return
    }
    for (blobID, data) in blobFrames {
      let frame = Frame(blobID: blobID, data: data)
      if let encoded = try? frame.encode() {
        writer.write(encoded, completion: nil)
      }
    }
    let envelope = Envelope(id: id, kind: kind, payload: rewritten)
    guard let json = try? envelope.encode().encodeData() else {
      completion?(ProtocolError.malformedJSON)
      return
    }
    let frame = Frame(json: json)
    guard let encoded = try? frame.encode() else {
      completion?(ProtocolError.oversizedFrame(declared: json.count))
      return
    }
    writer.write(encoded, completion: completion)
  }

  private func nextEnvelopeIDValue() throws -> UInt64 {
    try ensureOpen()
    guard pending.count < Self.maxInFlight else {
      throw ProtocolError.tooManyInFlight
    }
    let id = nextEnvelopeID
    nextEnvelopeID &+= 2
    return id
  }

  private func ensureOpen() throws {
    guard !closed else { throw ProtocolError.channelClosed }
  }

  // MARK: Receiving

  private func readLoop() async {
    while !closed {
      do {
        let frame = try await reader.nextFrame()
        try await process(frame)
      } catch is CancellationError {
        return
      } catch let error as ProtocolError {
        closed = true
        failAll(error)
        eventContinuation.finish()
        return
      } catch {
        closed = true
        failAll(ProtocolError.peerDied)
        eventContinuation.finish()
        return
      }
    }
  }

  private func process(_ frame: Frame) async throws {
    switch frame.kind {
    case .json:
      let value = try JSONValue.parse(frame.payload)
      let envelope = try Envelope.decode(value)
      if idParity(envelope.id) == parity {
        // Our id space: this must be a reply to something we asked for.
        guard let pendingEntry = pending.removeValue(forKey: envelope.id) else {
          throw ProtocolError.protocolViolation("unsolicited reply id \(envelope.id)")
        }
        pendingEntry.timeoutTask?.cancel()
        var blobs: [UInt64: Data] = [:]
        do {
          for id in envelope.payload.blobIDs {
            guard let data = await blobTable.take(id) else {
              throw ProtocolError.missingBlob(id: id)
            }
            blobs[id] = data
          }
        } catch {
          // The continuation was already removed from `pending`; it must be
          // failed here or it hangs forever while the channel also dies.
          pendingEntry.continuation.resume(throwing: error)
          throw error
        }
        pendingEntry.continuation.resume(
          returning: Reply(kind: envelope.kind, payload: envelope.payload, blobs: blobs)
        )
      } else {
        eventContinuation.yield(Event(envelope: envelope))
      }
    case .blob:
      guard let id = frame.blobID, let data = frame.blobData else {
        throw ProtocolError.protocolViolation("blob frame without id")
      }
      try await blobTable.store(id, data: data)
    case .close:
      failAll(ProtocolError.channelClosed)
      eventContinuation.finish()
      closed = true
    }
  }

  private func idParity(_ id: UInt64) -> IDParity {
    id % 2 == 0 ? .even : .odd
  }


  private func timeoutRequest(id: UInt64) {
    guard let pending = pending.removeValue(forKey: id) else { return }
    pending.timeoutTask?.cancel()
    pending.continuation.resume(throwing: ProtocolError.timedOut)
  }

  private func failRequest(id: UInt64, error: Error) {
    guard let pending = pending.removeValue(forKey: id) else { return }
    pending.timeoutTask?.cancel()
    pending.continuation.resume(throwing: error)
  }

  private func failAll(_ error: Error) {
    let pending = self.pending
    self.pending.removeAll()
    for (_, entry) in pending {
      entry.timeoutTask?.cancel()
      entry.continuation.resume(throwing: error)
    }
  }
}
