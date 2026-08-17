import Foundation

// The published document projection. A deliberately lossy *view* of the host's
// internal models — never `AnnotationItem`, never SwiftUI types. Internal
// refactors and plugin compatibility move on separate clocks.
//
// Forward-compatibility discipline (copied from `PersistedAnnotationSession`):
// new fields are optional and default; enum payloads decode with safe
// fallbacks so unknown future values never break decoding.

/// A document a plugin was invoked on.
///
/// `documentSchema` version is carried per-case; bumping it is additive-only.
public enum SnapzyDocument: Codable, Sendable, Hashable {
  case annotate(AnnotateDocument)
  case media(MediaDocument)

  private enum CodingKeys: String, CodingKey { case kind }
  private enum Kind: String, Codable { case annotate, media }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decodeIfPresent(Kind.self, forKey: .kind) {
    case .annotate:
      self = .annotate(try AnnotateDocument(from: decoder))
    case .media:
      self = .media(try MediaDocument(from: decoder))
    case nil:
      // Unknown future document kind: decode fails loudly only for the
      // unknown case; callers that want tolerance catch it. There is no
      // safe projection for a shape the host does not know.
      throw DecodingError.dataCorruptedError(
        forKey: .kind, in: container,
        debugDescription: "Unknown SnapzyDocument kind."
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .annotate(let document):
      try container.encode(Kind.annotate, forKey: .kind)
      try document.encode(to: encoder)
    case .media(let document):
      try container.encode(Kind.media, forKey: .kind)
      try document.encode(to: encoder)
    }
  }
}

/// Projection of an open Annotate document.
///
/// Coordinate space: `size` is the source image's **logical point space** —
/// the same space `AnnotationItem.bounds` lives in, pinned at authoring time
/// by `sourceLogicalSize`. OCR boxes from `snapzy.ocr` arrive in the same
/// space. `scale` is the backing scale for export-fidelity decisions.
public struct AnnotateDocument: Codable, Sendable, Hashable {
  public let schema: Int
  public let size: SnapzySize
  public let scale: Double
  public let items: [AnnotateDocItem]
  public let crop: SnapzyRect?

  public init(
    schema: Int = SnapzyVocabulary.documentSchemaVersion,
    size: SnapzySize,
    scale: Double = 1,
    items: [AnnotateDocItem],
    crop: SnapzyRect? = nil
  ) {
    self.schema = schema
    self.size = size
    self.scale = scale
    self.items = items
    self.crop = crop
  }
}

/// A single projected annotation item.
///
/// `kind` is a raw string ("text", "rect", "ellipse", "arrow", "highlight",
/// "blur", "counter", …): unknown values decode and are preserved, so a plugin
/// written for an older host still round-trips items it does not understand.
public struct AnnotateDocItem: Codable, Sendable, Hashable {
  /// Stable string id. For projected items this is the host item's id; for
  /// added items it is the id the plugin chose, stable for the session.
  public let id: String
  public let kind: String
  /// Bounds in logical point space.
  public let rect: SnapzyRect
  public let text: String?
  public let style: AnnotateDocStyle
  public let zIndex: Int

  public init(
    id: String,
    kind: String,
    rect: SnapzyRect,
    text: String? = nil,
    style: AnnotateDocStyle = AnnotateDocStyle(),
    zIndex: Int = 0
  ) {
    self.id = id
    self.kind = kind
    self.rect = rect
    self.text = text
    self.style = style
    self.zIndex = zIndex
  }

  /// `style` and `zIndex` decode with defaults so sidecars written before a
  /// field existed keep loading (the `PersistedAnnotationSession` discipline).
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    kind = try container.decode(String.self, forKey: .kind)
    rect = try container.decode(SnapzyRect.self, forKey: .rect)
    text = try container.decodeIfPresent(String.self, forKey: .text)
    style = try container.decodeIfPresent(AnnotateDocStyle.self, forKey: .style)
      ?? AnnotateDocStyle()
    zIndex = try container.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0
  }

  private enum CodingKeys: String, CodingKey {
    case id, kind, rect, text, style, zIndex
  }
}

/// Style of a projected item. Every field optional and defaulted, so old
/// clients decode new styles without breaking.
public struct AnnotateDocStyle: Codable, Sendable, Hashable {
  public var strokeColor: SnapzyColor?
  public var fillColor: SnapzyColor?
  public var strokeWidth: Double?
  public var fontSize: Double?
  public var fontName: String?
  public var opacity: Double?
  public var rotation: Double?
  /// "plain" | "label" | "callout" — raw string, unknown values tolerated.
  public var presentation: String?

  public init(
    strokeColor: SnapzyColor? = nil,
    fillColor: SnapzyColor? = nil,
    strokeWidth: Double? = nil,
    fontSize: Double? = nil,
    fontName: String? = nil,
    opacity: Double? = nil,
    rotation: Double? = nil,
    presentation: String? = nil
  ) {
    self.strokeColor = strokeColor
    self.fillColor = fillColor
    self.strokeWidth = strokeWidth
    self.fontSize = fontSize
    self.fontName = fontName
    self.opacity = opacity
    self.rotation = rotation
    self.presentation = presentation
  }
}

/// Projection of a media document (video or GIF). Read-only in v1: video
/// commands can produce `.text`/`.asset` outcomes; the caption track and
/// `captions[]` land with the host feature.
public struct MediaDocument: Codable, Sendable, Hashable {
  public let schema: Int
  public let duration: Double?
  public let size: SnapzySize?
  public let fps: Double?
  public let segments: [MediaDocumentSegment]

  public init(
    schema: Int = SnapzyVocabulary.documentSchemaVersion,
    duration: Double? = nil,
    size: SnapzySize? = nil,
    fps: Double? = nil,
    segments: [MediaDocumentSegment] = []
  ) {
    self.schema = schema
    self.duration = duration
    self.size = size
    self.fps = fps
    self.segments = segments
  }
}

public struct MediaDocumentSegment: Codable, Sendable, Hashable {
  /// "zoom" | "speed" — raw string, unknown values tolerated.
  public let kind: String
  public let start: Double
  public let end: Double

  public init(kind: String, start: Double, end: Double) {
    self.kind = kind
    self.start = start
    self.end = end
  }
}
