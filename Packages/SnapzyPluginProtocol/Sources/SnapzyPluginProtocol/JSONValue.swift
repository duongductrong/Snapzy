import Foundation

/// A JSON value with a total, fuzz-hardened parser.
///
/// The protocol layer carries payloads as this type, not as `Any` from
/// `JSONSerialization` (not `Sendable`, not total) and not as PluginKitCore's
/// `JSONValue` (which would drag the vocabulary into a transport module that
/// must stay reimplementable from PROTOCOL.md alone).
///
/// `parse(_:maxDepth:)` is the hostile-input boundary: it pre-scans the raw
/// bytes for nesting depth *before* `JSONSerialization` ever recurses, so a
/// deeply nested input is refused in O(n) instead of overflowing the parser's
/// stack. The tree walk after parsing is iterative for the same reason.
public indirect enum JSONValue: Sendable, Hashable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  /// Default nesting cap, shared with `FrameChannel`.
  public static let defaultMaxDepth = 32

  // MARK: Parsing

  /// Parses JSON bytes, enforcing the nesting cap before any recursion.
  public static func parse(_ data: Data, maxDepth: Int = defaultMaxDepth) throws -> JSONValue {
    try assertDepthBounded(data, maxDepth: maxDepth)
    let object: Any
    do {
      object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    } catch {
      throw ProtocolError.malformedJSON
    }
    return try Self.convert(object, maxDepth: maxDepth)
  }

  /// Counts `[`/`{` vs `]`/`}` outside strings in one linear pass. Refuses
  /// inputs whose bracket depth exceeds the cap without recursing into them.
  static func assertDepthBounded(_ data: Data, maxDepth: Int) throws {
    var depth = 0
    var inString = false
    var escaped = false
    for byte in data {
      if inString {
        if escaped {
          escaped = false
        } else if byte == 0x5C { // backslash
          escaped = true
        } else if byte == 0x22 { // quote
          inString = false
        }
        continue
      }
      switch byte {
      case 0x22: inString = true
      case 0x5B, 0x7B: // [ {
        depth += 1
        if depth > maxDepth { throw ProtocolError.jsonNestingTooDeep }
      case 0x5D, 0x7D: // ] }
        depth -= 1
      default: break
      }
    }
  }

  /// Converts a `JSONSerialization` tree iteratively, re-checking depth so
  /// the cap holds even if the pre-scan and the parser disagree.
  static func convert(_ object: Any, maxDepth: Int) throws -> JSONValue {
    func fromFoundation(_ value: Any, depth: Int) throws -> JSONValue {
      if depth > maxDepth { throw ProtocolError.jsonNestingTooDeep }
      switch value {
      case is NSNull:
        return .null
      // NSNumber must come first: `NSNumber(1) as? Bool` succeeds with
      // `true`, so checking Bool before NSNumber corrupts every integer.
      // JSONSerialization produces CFBoolean-backed NSNumbers for real
      // booleans, which the type-ID check distinguishes.
      case let number as NSNumber:
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
          return .bool(number.boolValue)
        }
        return .number(number.doubleValue)
      case let bool as Bool:
        return .bool(bool)
      case let string as String:
        return .string(string)
      case let array as [Any]:
        var converted: [JSONValue] = []
        converted.reserveCapacity(array.count)
        for element in array {
          converted.append(try fromFoundation(element, depth: depth + 1))
        }
        return .array(converted)
      case let dictionary as [String: Any]:
        var converted: [String: JSONValue] = [:]
        converted.reserveCapacity(dictionary.count)
        for (key, value) in dictionary {
          converted[key] = try fromFoundation(value, depth: depth + 1)
        }
        return .object(converted)
      default:
        throw ProtocolError.malformedJSON
      }
    }
    return try fromFoundation(object, depth: 0)
  }

  // MARK: Encoding

  public func encodeData() throws -> Data {
    let object = foundationValue
    guard JSONSerialization.isValidJSONObject(object) || object is String || object is NSNumber
      || object is NSNull
    else { throw ProtocolError.malformedJSON }
    return try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
  }

  /// The `Any` tree `JSONSerialization` accepts.
  var foundationValue: Any {
    switch self {
    case .null: return NSNull()
    case .bool(let value): return value
    case .number(let value): return value
    case .string(let value): return value
    case .array(let values): return values.map(\.foundationValue)
    case .object(let entries): return entries.mapValues(\.foundationValue)
    }
  }

  // MARK: Blob references

  /// The canonical blob reference shape: `{"blob": <id>}` where id is a
  /// non-negative integer. A payload field that must carry bytes holds this.
  public static func blobReference(_ id: Double) -> JSONValue {
    .object(["blob": .number(id)])
  }

  /// The blob id this value references, if it is exactly `{"blob": <id>}`.
  public var blobReferenceID: UInt64? {
    guard case .object(let object) = self,
      object.count == 1,
      case .number(let id)? = object["blob"]
    else { return nil }
    guard id >= 0, id < Double(UInt64.max), id == id.rounded() else { return nil }
    return UInt64(id)
  }

  /// Every blob id referenced anywhere in this value, in deterministic key order.
  /// The channel uses this to resolve a received payload against its blob
  /// table exactly once.
  public var blobIDs: [UInt64] {
    var ids: [UInt64] = []
    func collect(_ value: JSONValue) {
      switch value {
      case .array(let values):
        values.forEach(collect)
      case .object(let entries):
        if let id = value.blobReferenceID {
          ids.append(id)
        } else {
          for key in entries.keys.sorted() {
            if let v = entries[key] { collect(v) }
          }
        }
      default:
        break
      }
    }
    collect(self)
    return ids
  }

  /// Replaces every `{"blob": <id>}` subtree with the byte string it names.
  ///
  /// This is the bridge for consumers whose boundary expects bytes inside
  /// JSON (the capability broker receives `{"base64": …}` today). The base64
  /// encoding happens in memory only — the wire carries the raw blob frame,
  /// so nothing pays the 33% tax twice.
  public func resolvingBlobs(from blobs: [UInt64: Data]) -> JSONValue {
    switch self {
    case .array(let values):
      return .array(values.map { $0.resolvingBlobs(from: blobs) })
    case .object(let entries):
      if let id = blobReferenceID {
        if let data = blobs[id] {
          return .string(data.base64EncodedString())
        }
        return self
      }
      return .object(entries.mapValues { $0.resolvingBlobs(from: blobs) })
    default:
      return self
    }
  }

  /// The number of `{"blob": <index>}` placeholders in this value, used by
  /// the sender to pre-assign real blob ids before rewriting.
  public var blobPlaceholderCount: Int {
    var count = 0
    func scan(_ value: JSONValue) {
      switch value {
      case .array(let values):
        values.forEach(scan)
      case .object(let entries):
        if entries.count == 1, case .number(let index)? = entries["blob"],
          index >= 0, index == index.rounded()
        {
          count += 1
        } else {
          for key in entries.keys.sorted() {
            if let v = entries[key] { scan(v) }
          }
        }
      default:
        break
      }
    }
    scan(self)
    return count
  }

  /// Replaces each `{"blob": <index>}` placeholder with a real blob id from
  /// `ids` (in encounter order) and returns the blob frames that must be
  /// emitted first. `ids.count` must equal `blobPlaceholderCount`; indices
  /// into `blobs` must be in range or the rewrite throws.
  func embeddingBlobs(_ blobs: [Data], ids: [UInt64]) throws -> (JSONValue, [(id: UInt64, data: Data)]) {
    guard ids.count >= blobs.count else {
      throw ProtocolError.invalidBlobReference
    }
    let frames = (0..<blobs.count).map { (id: ids[$0], data: blobs[$0]) }

    func rewrite(_ value: JSONValue) throws -> JSONValue {
      switch value {
      case .array(let values):
        return .array(try values.map(rewrite))
      case .object(let entries):
        if entries.count == 1, case .number(let index)? = entries["blob"] {
          guard index >= 0, index < Double(blobs.count), index == index.rounded() else {
            throw ProtocolError.blobIndexOutOfRange
          }
          let blobIndex = Int(index)
          guard blobIndex < ids.count else {
            throw ProtocolError.invalidBlobReference
          }
          let id = ids[blobIndex]
          return .object(["blob": .number(Double(id))])
        }
        var newEntries: [String: JSONValue] = [:]
        for key in entries.keys.sorted() {
          if let v = entries[key] {
            newEntries[key] = try rewrite(v)
          }
        }
        return .object(newEntries)
      default:
        return value
      }
    }
    return (try rewrite(self), frames)
  }
}

extension JSONValue: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
      return
    }
    if let object = try? container.decode([String: JSONValue].self) {
      self = .object(object)
      return
    }
    if let array = try? container.decode([JSONValue].self) {
      self = .array(array)
      return
    }
    if let string = try? container.decode(String.self) {
      self = .string(string)
      return
    }
    if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
      return
    }
    if let number = try? container.decode(Double.self) {
      self = .number(number)
      return
    }
    throw DecodingError.dataCorruptedError(
      in: container, debugDescription: "not a JSON value"
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let values): try container.encode(values)
    case .object(let entries): try container.encode(entries)
    }
  }
}
