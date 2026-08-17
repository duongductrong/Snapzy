import Foundation
import SnapzyPluginProtocol

/// The `Codable` ↔ `JSONValue` bridge.
///
/// A message struct is encoded to JSON bytes and re-parsed as `JSONValue`,
/// or the reverse — one `JSONEncoder`/`JSONDecoder` round trip per message,
/// at plugin scale. Keeping the transport's payload type (`JSONValue`)
/// separate from the vocabulary's `Codable` types is what lets the protocol
/// module stay Foundation-only while the vocabulary keeps its own clock.
enum JSONValueCodec {
  static func encode<T: Encodable>(_ value: T) throws -> JSONValue {
    let data: Data
    do {
      data = try JSONEncoder().encode(value)
    } catch {
      throw ProtocolError.malformedJSON
    }
    return try JSONValue.parse(data)
  }

  static func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
    let data = try value.encodeData()
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      throw ProtocolError.malformedJSON
    }
  }
}
