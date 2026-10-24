//
//  Frame.swift
//  SnapzyCLIProtocol
//
//  Length-prefixed framing for the CLI socket: a 4-byte big-endian payload
//  length followed by one UTF-8 JSON document.
//

import Foundation

public enum FrameError: Error, Equatable, Sendable {
  case payloadTooLarge(Int)
  case emptyPayload
}

public enum Frame {
  public static let headerByteCount = 4

  /// Responses carry file paths, never image bytes, so 1 MiB is generous.
  public static let maxPayloadByteCount = 1 << 20

  public static func encode(_ payload: Data) throws -> Data {
    guard !payload.isEmpty else { throw FrameError.emptyPayload }
    guard payload.count <= maxPayloadByteCount else {
      throw FrameError.payloadTooLarge(payload.count)
    }

    var length = UInt32(payload.count).bigEndian
    var frame = Data(bytes: &length, count: headerByteCount)
    frame.append(payload)
    return frame
  }
}

/// Reassembles frames from arbitrarily split socket reads.
public struct FrameDecoder: Sendable {
  private var buffer = Data()

  public init() {}

  public var bufferedByteCount: Int {
    buffer.count
  }

  public mutating func append(_ data: Data) {
    buffer.append(data)
  }

  /// Returns the next complete payload, or `nil` when more bytes are needed.
  public mutating func nextPayload() throws -> Data? {
    guard buffer.count >= Frame.headerByteCount else { return nil }

    let length = buffer.prefix(Frame.headerByteCount).reduce(0) { ($0 << 8) | Int($1) }
    guard length > 0 else { throw FrameError.emptyPayload }
    guard length <= Frame.maxPayloadByteCount else { throw FrameError.payloadTooLarge(length) }

    let frameByteCount = Frame.headerByteCount + length
    guard buffer.count >= frameByteCount else { return nil }

    let payload = Data(buffer.dropFirst(Frame.headerByteCount).prefix(length))
    buffer = Data(buffer.dropFirst(frameByteCount))
    return payload
  }
}
