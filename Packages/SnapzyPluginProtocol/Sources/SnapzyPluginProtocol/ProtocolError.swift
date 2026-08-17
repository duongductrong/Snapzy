import Foundation

/// Errors thrown by every parse and channel path. The wire faces hostile
/// bytes; every failure is typed so a caller can distinguish "peer is broken"
/// from "peer is gone" without string-matching.
public enum ProtocolError: Error, Equatable, Sendable {
  /// A frame header or payload was cut off mid-stream.
  case truncatedFrame
  /// A frame declared a payload larger than `Frame.maxPayloadBytes`.
  case oversizedFrame(declared: Int)
  /// A frame kind byte outside the known set.
  case unknownFrameKind(UInt8)
  /// JSON payload did not parse.
  case malformedJSON
  /// JSON nesting exceeded the cap (bracket pre-scan or tree walk).
  case jsonNestingTooDeep
  /// A message kind the protocol does not define (forward compatibility:
  /// consumers decide whether to ignore it).
  case unknownMessageKind(String)
  /// The remote speaks a different protocol major, or a newer minor.
  case incompatibleProtocol(local: String, remote: String, reason: String)
  /// The peer's socket closed without a `close` frame.
  case peerDied
  /// A request did not receive its reply in time.
  case timedOut
  /// More than `FrameChannel.maxInFlight` requests are outstanding.
  case tooManyInFlight
  /// The channel has been closed; new sends are refused.
  case channelClosed
  /// A reply arrived for a request id that already received one.
  case duplicateReply(id: UInt64)
  /// A payload referenced a blob id that never arrived.
  case missingBlob(id: UInt64)
  /// A payload's `{"blob": n}` reference is not a non-negative number.
  case invalidBlobReference
  /// The peer sent more blob bytes than the channel is willing to buffer.
  case blobLimitExceeded
  /// A blob index reference was out of range for the accompanying list.
  case blobIndexOutOfRange
  /// The peer misused the protocol in a way that cannot be attributed to a
  /// single frame (e.g. an oversized handshake payload).
  case protocolViolation(String)
}
