import Foundation

/// A message envelope: a correlated id, a kind string, and a JSON payload.
///
/// Forward-compatible by construction: unknown keys in the wire JSON are
/// ignored, unknown kinds are delivered to the consumer rather than fatal,
/// and the id is only ever used for correlation. A newer peer can send more
/// fields and a newer kind to an older peer without a protocol major bump —
/// exactly the discipline `PluginManifest` and `PluginIndexEntry` already
/// follow.
public struct Envelope: Sendable, Equatable {
  public let id: UInt64
  public let kind: String
  public let payload: JSONValue

  public init(id: UInt64, kind: String, payload: JSONValue) {
    self.id = id
    self.kind = kind
    self.payload = payload
  }

  /// Decodes the canonical wire shape `{"id": N, "kind": "...", "payload": …}`.
  public static func decode(_ payload: JSONValue) throws -> Envelope {
    guard case .object(let entries) = payload,
      case .number(let id)? = entries["id"],
      case .string(let kind)? = entries["kind"],
      let body = entries["payload"]
    else { throw ProtocolError.malformedJSON }
    guard id >= 0, id < Double(UInt64.max), id == id.rounded() else {
      throw ProtocolError.malformedJSON
    }
    return Envelope(id: UInt64(id), kind: kind, payload: body)
  }

  public func encode() -> JSONValue {
    .object([
      "id": .number(Double(id)),
      "kind": .string(kind),
      "payload": payload
    ])
  }
}
