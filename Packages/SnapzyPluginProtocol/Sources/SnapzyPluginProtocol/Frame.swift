import Foundation

/// A wire frame: one kind byte, a 4-byte big-endian length, then the payload.
///
/// The header is deliberately not extensible. Anything that changes the frame
/// shape is a protocol major bump; anything expressible inside the payload is
/// a minor bump. `PROTOCOL.md` states this and the version rules enforce it.
public struct Frame: Sendable, Equatable {
  public enum Kind: UInt8, Sendable, Equatable {
    case json = 1
    case blob = 2
    case close = 3
  }

  /// Largest legal payload. Enforced on decode *and* encode: a host bug that
  /// writes a giant frame must not become a peer's allocation problem.
  public static let maxPayloadBytes = 32 * 1024 * 1024

  public static let headerByteCount = 5

  public let kind: Kind
  public let payload: Data

  public init(kind: Kind, payload: Data) {
    self.kind = kind
    self.payload = payload
  }

  public init(json payload: Data) {
    self.init(kind: .json, payload: payload)
  }

  public init(blobID: UInt64, data: Data) {
    var payload = Data()
    payload.append(contentsOf: withUnsafeBytes(of: blobID.bigEndian) { Data($0) })
    payload.append(data)
    self.init(kind: .blob, payload: payload)
  }

  public static let close = Frame(kind: .close, payload: Data())

  /// The blob id carried by a blob frame, or nil for other kinds.
  public var blobID: UInt64? {
    guard kind == .blob, payload.count >= 8 else { return nil }
    return payload.prefix(8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).bigEndian }
  }

  /// The blob bytes carried by a blob frame, or nil for other kinds.
  public var blobData: Data? {
    guard kind == .blob, payload.count >= 8 else { return nil }
    return payload.dropFirst(8)
  }

  public func encode() throws -> Data {
    guard payload.count <= Self.maxPayloadBytes else {
      throw ProtocolError.oversizedFrame(declared: payload.count)
    }
    var out = Data(capacity: Self.headerByteCount + payload.count)
    out.append(kind.rawValue)
    out.append(contentsOf: withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Data($0) })
    out.append(payload)
    return out
  }

  /// Decodes one complete frame from `data`. Trailing bytes are ignored, so
  /// callers can feed a buffer that contains the next frame after this one.
  public static func decode(from data: Data) throws -> (frame: Frame, consumed: Int) {
    guard data.count >= headerByteCount else { throw ProtocolError.truncatedFrame }
    guard let kind = Kind(rawValue: data[data.startIndex]) else {
      throw ProtocolError.unknownFrameKind(data[data.startIndex])
    }
    let length = data.subdata(in: 1..<5).withUnsafeBytes {
      $0.loadUnaligned(as: UInt32.self).bigEndian
    }
    guard Int(length) <= maxPayloadBytes else {
      throw ProtocolError.oversizedFrame(declared: Int(length))
    }
    let bodyStart = data.startIndex + headerByteCount
    let bodyEnd = bodyStart + Int(length)
    guard data.count >= bodyEnd else { throw ProtocolError.truncatedFrame }
    let payload = data.subdata(in: bodyStart..<bodyEnd)
    return (Frame(kind: kind, payload: payload), bodyEnd)
  }
}
