import Foundation
import PluginKitCore

// Payload types for the host services behind `snapzy.network`, `snapzy.ocr`,
// `snapzy.image`, `snapzy.media`, `snapzy.ui`. Every one is Codable-only:
// no references, no platform types, so they cross the XPC boundary verbatim.

// MARK: - Network

public struct PluginHTTPRequest: Codable, Sendable, Hashable {
  public let url: String
  public let method: String
  public let headers: [String: String]
  public let body: Data?

  public init(
    url: String,
    method: String = "GET",
    headers: [String: String] = [:],
    body: Data? = nil
  ) {
    self.url = url
    self.method = method
    self.headers = headers
    self.body = body
  }
}

public struct PluginHTTPResponse: Codable, Sendable {
  public let status: Int
  public let headers: [String: String]
  public let body: Data

  public init(status: Int, headers: [String: String] = [:], body: Data) {
    self.status = status
    self.headers = headers
    self.body = body
  }

  public var bodyText: String? { String(data: body, encoding: .utf8) }
}

// MARK: - OCR

public struct PluginOCRRequest: Codable, Sendable, Hashable {
  /// Image bytes to recognize (PNG/JPEG/WebP/HEIC, anything ImageIO reads).
  public let image: Data
  /// Preferred language identifier (BCP-47), optional.
  public let language: String?
  /// "interfaceText" | "denseDocument" | "code".
  public let contentType: String?
  /// When provided, boxes are scaled into this coordinate space — the same
  /// logical point space the document projection lives in. Pass the projected
  /// document's `size` to get boxes that line up with edits directly.
  public let coordinateSize: SnapzySize?

  public init(
    image: Data,
    language: String? = nil,
    contentType: String? = nil,
    coordinateSize: SnapzySize? = nil
  ) {
    self.image = image
    self.language = language
    self.contentType = contentType
    self.coordinateSize = coordinateSize
  }
}

/// One recognized line. `box` is in the image's **logical point space**
/// (top-left origin, 1× authoring coordinates) — the same space document
/// edits live in, so a plugin can map lines back onto boxes without any
/// coordinate math of its own.
public struct PluginOCRLine: Codable, Sendable, Hashable {
  public let text: String
  public let box: SnapzyRect
  public let confidence: Double

  public init(text: String, box: SnapzyRect, confidence: Double) {
    self.text = text
    self.box = box
    self.confidence = confidence
  }
}

public struct PluginOCRResult: Codable, Sendable, Hashable {
  public let lines: [PluginOCRLine]
  public let text: String

  public init(lines: [PluginOCRLine], text: String) {
    self.lines = lines
    self.text = text
  }
}

// MARK: - Image

public struct PluginImageOperation: Codable, Sendable, Hashable {
  /// "decode" | "resize" | "crop" | "encode".
  public let operation: String
  /// Input bytes for decode/crop/resize; decode output feeds encode.
  public let image: Data?
  public let targetSize: SnapzySize?
  public let cropRect: SnapzyRect?
  /// "png" | "jpeg" | "webp" | "heic" | "tiff".
  public let format: String?
  public let quality: Double?

  public init(
    operation: String,
    image: Data? = nil,
    targetSize: SnapzySize? = nil,
    cropRect: SnapzyRect? = nil,
    format: String? = nil,
    quality: Double? = nil
  ) {
    self.operation = operation
    self.image = image
    self.targetSize = targetSize
    self.cropRect = cropRect
    self.format = format
    self.quality = quality
  }
}

public struct PluginImageResult: Codable, Sendable, Hashable {
  public let image: Data
  public let size: SnapzySize
  public let format: String?

  public init(image: Data, size: SnapzySize, format: String? = nil) {
    self.image = image
    self.size = size
    self.format = format
  }
}

// MARK: - Media

public struct PluginMediaOperation: Codable, Sendable, Hashable {
  /// "duration" | "frameAt" | "extractAudio".
  public let operation: String
  /// Time in seconds, for frameAt.
  public let time: Double?

  public init(operation: String, time: Double? = nil) {
    self.operation = operation
    self.time = time
  }
}

public struct PluginMediaResult: Codable, Sendable, Hashable {
  public let duration: Double?
  public let size: SnapzySize?
  public let fps: Double?
  /// For frameAt: image bytes.
  public let image: Data?
  /// For extractAudio: audio bytes (m4a).
  public let audio: Data?

  public init(
    duration: Double? = nil,
    size: SnapzySize? = nil,
    fps: Double? = nil,
    image: Data? = nil,
    audio: Data? = nil
  ) {
    self.duration = duration
    self.size = size
    self.fps = fps
    self.image = image
    self.audio = audio
  }
}

// MARK: - Declarative UI

/// The host renders these — a plugin never draws.
public enum PluginUIRequest: Codable, Sendable, Hashable {
  /// Present a form built from the schema; returns the submitted values.
  case form(PluginUIForm)
  /// Present a yes/no confirmation.
  case confirm(title: String, message: String)
  /// Show a result panel with copyable text.
  case showResult(title: String, text: String)

  private enum CodingKeys: String, CodingKey {
    case kind, form, title, message, text
  }

  private enum Kind: String, Codable {
    case form, confirm, showResult
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard let kind = try container.decodeIfPresent(Kind.self, forKey: .kind) else {
      throw DecodingError.dataCorruptedError(
        forKey: .kind, in: container, debugDescription: "Missing PluginUIRequest kind."
      )
    }
    switch kind {
    case .form:
      self = .form(try container.decode(PluginUIForm.self, forKey: .form))
    case .confirm:
      self = .confirm(
        title: try container.decode(String.self, forKey: .title),
        message: try container.decode(String.self, forKey: .message)
      )
    case .showResult:
      self = .showResult(
        title: try container.decode(String.self, forKey: .title),
        text: try container.decode(String.self, forKey: .text)
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .form(let form):
      try container.encode(Kind.form, forKey: .kind)
      try container.encode(form, forKey: .form)
    case .confirm(let title, let message):
      try container.encode(Kind.confirm, forKey: .kind)
      try container.encode(title, forKey: .title)
      try container.encode(message, forKey: .message)
    case .showResult(let title, let text):
      try container.encode(Kind.showResult, forKey: .kind)
      try container.encode(title, forKey: .title)
      try container.encode(text, forKey: .text)
    }
  }
}

public enum PluginUIResult: Codable, Sendable, Hashable {
  case submitted(JSONValue)
  case confirmed(Bool)
  case dismissed

  private enum CodingKeys: String, CodingKey {
    case kind, values, confirmed
  }

  private enum Kind: String, Codable {
    case submitted, confirmed, dismissed
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard let kind = try container.decodeIfPresent(Kind.self, forKey: .kind) else {
      throw DecodingError.dataCorruptedError(
        forKey: .kind, in: container, debugDescription: "Missing PluginUIResult kind."
      )
    }
    switch kind {
    case .submitted:
      self = .submitted(
        try container.decodeIfPresent(JSONValue.self, forKey: .values) ?? .object([:])
      )
    case .confirmed:
      self = .confirmed(try container.decodeIfPresent(Bool.self, forKey: .confirmed) ?? false)
    case .dismissed:
      self = .dismissed
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .submitted(let values):
      try container.encode(Kind.submitted, forKey: .kind)
      try container.encode(values, forKey: .values)
    case .confirmed(let confirmed):
      try container.encode(Kind.confirmed, forKey: .kind)
      try container.encode(confirmed, forKey: .confirmed)
    case .dismissed:
      try container.encode(Kind.dismissed, forKey: .kind)
    }
  }
}

/// A declarative form schema. Field kinds: "string" | "secret" | "number" |
/// "boolean" | "enum" | "url".
public struct PluginUIForm: Codable, Sendable, Hashable {
  public let title: String
  public let message: String?
  public let fields: [PluginUIFormField]
  public let submitLabel: String?

  public init(
    title: String,
    message: String? = nil,
    fields: [PluginUIFormField],
    submitLabel: String? = nil
  ) {
    self.title = title
    self.message = message
    self.fields = fields
    self.submitLabel = submitLabel
  }
}

public struct PluginUIFormField: Codable, Sendable, Hashable {
  public let name: String
  public let label: String
  /// "string" | "secret" | "number" | "boolean" | "enum" | "url".
  public let kind: String
  public let defaultValue: JSONValue?
  public let options: [String]?
  public let required: Bool

  public init(
    name: String,
    label: String,
    kind: String = "string",
    defaultValue: JSONValue? = nil,
    options: [String]? = nil,
    required: Bool = false
  ) {
    self.name = name
    self.label = label
    self.kind = kind
    self.defaultValue = defaultValue
    self.options = options
    self.required = required
  }
}

public extension RuntimeID {
  static let process = RuntimeID("process")
}

