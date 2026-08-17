import Foundation

/// A self-describing JSON value.
///
/// PluginKit needs to carry data whose *type it does not know* across three
/// boundaries: declarative contribution metadata (the host knows the type, the
/// framework never does), capability scopes, and configuration values. Using
/// `Any` would forfeit `Sendable` and `Equatable`; using a generic parameter
/// would force the framework to be generic over every host's vocabulary at once.
///
/// So metadata travels as ``JSONValue`` and is decoded into the host's concrete
/// type at the edge, by a closure the host registered along with its extension
/// point. That is what lets a manifest be validated — including its metadata
/// shape — before a single line of plugin code is loaded.
@frozen
public enum JSONValue: Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: - Coding

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Value is not representable as JSON."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    // MARK: - Bridging

    /// The `JSONSerialization`-compatible representation.
    public var foundationObject: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .string(let value): return value
        case .array(let value): return value.map(\.foundationObject)
        case .object(let value): return value.mapValues(\.foundationObject)
        }
    }

    /// Wraps a `JSONSerialization` output. Returns `nil` for anything JSON
    /// cannot represent.
    public init?(foundationObject object: Any) {
        switch object {
        case is NSNull:
            self = .null
        case let value as NSNumber:
            // Swift `Bool` and `Int` both bridge to `NSNumber`, so an `as Bool`
            // cast would turn every `1` into `true`. The CFBoolean type ID is
            // the only reliable discrimination between the two.
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else if value.doubleValue == value.doubleValue.rounded(),
                      let exact = Int(exactly: value.doubleValue) {
                self = .int(exact)
            } else {
                self = .double(value.doubleValue)
            }
        case let value as String:
            self = .string(value)
        case let value as [Any]:
            var items: [JSONValue] = []
            items.reserveCapacity(value.count)
            for item in value {
                guard let wrapped = JSONValue(foundationObject: item) else { return nil }
                items.append(wrapped)
            }
            self = .array(items)
        case let value as [String: Any]:
            var members: [String: JSONValue] = [:]
            members.reserveCapacity(value.count)
            for (key, item) in value {
                guard let wrapped = JSONValue(foundationObject: item) else { return nil }
                members[key] = wrapped
            }
            self = .object(members)
        default:
            return nil
        }
    }

    /// Re-encodes into a concrete `Decodable` type.
    ///
    /// The seam that makes host-owned metadata types work: the framework holds
    /// the value opaquely, and the host's registered decoder — which does know
    /// the type — turns it into something typed at the edge.
    public func decode<T: Decodable>(
        as type: T.Type,
        using decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        let data = try JSONSerialization.data(
            withJSONObject: foundationObject,
            options: [.fragmentsAllowed]
        )
        return try decoder.decode(T.self, from: data)
    }

    /// Captures any `Encodable` value.
    public init<T: Encodable>(encoding value: T, using encoder: JSONEncoder = JSONEncoder()) throws {
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let wrapped = JSONValue(foundationObject: object) else {
            throw PluginManifestError.malformedValue(reason: "Encoded value is not valid JSON.")
        }
        self = wrapped
    }

    // MARK: - Access

    public subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members[key]
    }

    public subscript(index: Int) -> JSONValue? {
        guard case .array(let items) = self, items.indices.contains(index) else { return nil }
        return items[index]
    }

    public var isNull: Bool { self == .null }
    public var boolValue: Bool? { if case .bool(let value) = self { return value } else { return nil } }
    public var stringValue: String? { if case .string(let value) = self { return value } else { return nil } }
    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value } else { return nil }
    }
    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value } else { return nil }
    }

    /// Integers survive a `double` round-trip through JSON, so accept both.
    public var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(exactly: value.rounded())
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int(let value): return Double(value)
        case .double(let value): return value
        default: return nil
        }
    }
}

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

extension JSONValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .string(let value): return "\"\(value)\""
        case .array(let items):
            return "[" + items.map(\.description).joined(separator: ",") + "]"
        case .object(let members):
            // Sorted so the rendering is stable — this ends up in diagnostics
            // and in golden-file test comparisons.
            let body = members.sorted { $0.key < $1.key }
                .map { "\"\($0.key)\":\($0.value.description)" }
                .joined(separator: ",")
            return "{" + body + "}"
        }
    }
}

/// A metadata type for extension points that carry no declarative payload.
///
/// Decodes from anything, including a missing value, so a point can gain
/// metadata later without invalidating manifests written against the version
/// that had none.
public struct EmptyMetadata: Codable, Hashable, Sendable {
    public init() {}
    public init(from decoder: any Decoder) throws { self.init() }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode([String: String]())
    }
}
