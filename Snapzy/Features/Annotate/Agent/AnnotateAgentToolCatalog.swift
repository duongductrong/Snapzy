//
//  AnnotateAgentToolCatalog.swift
//  Snapzy
//
//  Names, descriptions and JSON schemas of the Annotate AI prompt tools. One
//  catalog feeds every provider: OpenAI-style `tools`, MCP `tools/list`, and the
//  Apple Intelligence `Tool` wrappers.
//

import Foundation

nonisolated enum AnnotateAgentToolName: String, CaseIterable {
  case getScene = "get_scene"
  case findText = "find_text"
  case addBox = "add_box"
  case addOval = "add_oval"
  case addArrow = "add_arrow"
  case addLine = "add_line"
  case addText = "add_text"
  case addHighlight = "add_highlight"
  case addBlur = "add_blur"
  case addSpotlight = "add_spotlight"
  case addCounter = "add_counter"
  case addWatermark = "add_watermark"
  case updateAnnotation = "update_annotation"
  case deleteAnnotations = "delete_annotations"
  case arrange = "arrange"
  case select = "select"
  case setCanvas = "set_canvas"

  var isReadOnly: Bool {
    self == .getScene || self == .findText
  }
}

/// Minimal JSON value for schemas, so the catalog stays a plain value type.
nonisolated indirect enum AnnotateAgentJSON: Equatable, Encodable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case array([AnnotateAgentJSON])
  case object([(String, AnnotateAgentJSON)])

  static func == (lhs: AnnotateAgentJSON, rhs: AnnotateAgentJSON) -> Bool {
    lhs.serialized == rhs.serialized
  }

  func encode(to encoder: Encoder) throws {
    switch self {
    case .string(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .number(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .bool(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .array(let values):
      var container = encoder.unkeyedContainer()
      for value in values { try container.encode(value) }
    case .object(let pairs):
      var container = encoder.container(keyedBy: DynamicKey.self)
      for (key, value) in pairs { try container.encode(value, forKey: DynamicKey(key)) }
    }
  }

  var serialized: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
  }

  private struct DynamicKey: CodingKey {
    let stringValue: String
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
  }
}

nonisolated struct AnnotateAgentToolSpec: Equatable {
  let name: AnnotateAgentToolName
  let description: String
  /// JSON Schema (object) for the arguments.
  let parameters: AnnotateAgentJSON
}

nonisolated enum AnnotateAgentToolCatalog {
  // MARK: Schema helpers

  private static func object(_ properties: [(String, AnnotateAgentJSON)], required: [String] = []) -> AnnotateAgentJSON {
    var pairs: [(String, AnnotateAgentJSON)] = [
      ("type", .string("object")),
      ("properties", .object(properties)),
    ]
    if !required.isEmpty {
      pairs.append(("required", .array(required.map { .string($0) })))
    }
    pairs.append(("additionalProperties", .bool(false)))
    return .object(pairs)
  }

  private static func string(_ description: String, enum values: [String]? = nil) -> AnnotateAgentJSON {
    var pairs: [(String, AnnotateAgentJSON)] = [("type", .string("string")), ("description", .string(description))]
    if let values { pairs.append(("enum", .array(values.map { .string($0) }))) }
    return .object(pairs)
  }

  private static func number(_ description: String) -> AnnotateAgentJSON {
    .object([("type", .string("number")), ("description", .string(description))])
  }

  private static func integer(_ description: String) -> AnnotateAgentJSON {
    .object([("type", .string("integer")), ("description", .string(description))])
  }

  private static func stringArray(_ description: String) -> AnnotateAgentJSON {
    .object([
      ("type", .string("array")),
      ("items", .object([("type", .string("string"))])),
      ("description", .string(description)),
    ])
  }

  /// Target is deliberately loose (string or object) so small models get it right.
  private static func target(_ description: String) -> AnnotateAgentJSON {
    .object([
      ("description", .string(description + " " + targetHelp)),
      ("anyOf", .array([
        .object([("type", .string("string"))]),
        .object([
          ("type", .string("object")),
          ("properties", .object([
            ("text", .object([("type", .string("string"))])),
            ("id", .object([("type", .string("string"))])),
            ("rect", .object([("type", .string("array")), ("items", .object([("type", .string("number"))]))])),
            ("point", .object([("type", .string("array")), ("items", .object([("type", .string("number"))]))])),
          ])),
        ]),
      ])),
    ])
  }

  static let targetHelp = "Use an id from the scene (\"t3\" text block, \"e2\" UI element, \"a5\" annotation), {\"text\": \"Sign in\"} to match visible text, {\"rect\": [x, y, width, height]} or {\"point\": [x, y]}. Coordinates: image units, origin top-left."

  private static let color = string("Color name (\(AnnotateAgentColor.validValuesDescription)).")
  private static let strokeWidth = number("Line thickness 1–20.")

  // MARK: Catalog

  static let all: [AnnotateAgentToolSpec] = [
    AnnotateAgentToolSpec(
      name: .getScene,
      description: "Describe the image: size, text blocks (t#), UI elements (e#), existing annotations (a#), current selection and canvas settings. Coordinates are image units with a top-left origin.",
      parameters: object([])
    ),
    AnnotateAgentToolSpec(
      name: .findText,
      description: "Find text blocks whose text matches the query (case and accent insensitive). Returns ids and rects, best match first.",
      parameters: object([("query", string("Text to look for."))], required: ["query"])
    ),
    AnnotateAgentToolSpec(
      name: .addBox,
      description: "Draw a rectangle around a target.",
      parameters: object([
        ("target", target("What to enclose.")),
        ("color", color),
        ("filled", .object([("type", .string("boolean")), ("description", .string("Solid filled box instead of an outline."))])),
        ("stroke_width", strokeWidth),
        ("corner_radius", number("Corner radius 0–40.")),
        ("padding", number("Space between target and box, default 6.")),
      ], required: ["target"])
    ),
    AnnotateAgentToolSpec(
      name: .addOval,
      description: "Draw an ellipse around a target.",
      parameters: object([
        ("target", target("What to circle.")),
        ("color", color),
        ("stroke_width", strokeWidth),
        ("padding", number("Space between target and ellipse, default 10.")),
      ], required: ["target"])
    ),
    AnnotateAgentToolSpec(
      name: .addArrow,
      description: "Draw an arrow pointing at a target. Without 'from', the arrow starts in the nearest free space.",
      parameters: object([
        ("to", target("What the arrow points at.")),
        ("from", target("Optional start.")),
        ("color", color),
        ("stroke_width", strokeWidth),
        ("style", string("Arrow shape.", enum: ["straight", "curved"])),
      ], required: ["to"])
    ),
    AnnotateAgentToolSpec(
      name: .addLine,
      description: "Draw a straight line between two targets (their centers).",
      parameters: object([
        ("from", target("Start.")),
        ("to", target("End.")),
        ("color", color),
        ("stroke_width", strokeWidth),
        ("dashed", .object([("type", .string("boolean"))])),
      ], required: ["from", "to"])
    ),
    AnnotateAgentToolSpec(
      name: .addText,
      description: "Add a text note. With a target, the note is placed next to it (a callout points at it by default).",
      parameters: object([
        ("text", string("The note.")),
        ("target", target("Optional: what the note is about.")),
        ("placement", string("Where to put the note relative to the target.", enum: ["auto", "above", "below", "left", "right", "over"])),
        ("style", string("plain = bare text, label = text on a colored pill, callout = pill with a pointer.", enum: ["plain", "label", "callout"])),
        ("color", string("Pill color for label/callout, text color for plain. \(AnnotateAgentColor.validValuesDescription).")),
        ("font_size", number("Font size 12–72.")),
      ], required: ["text"])
    ),
    AnnotateAgentToolSpec(
      name: .addHighlight,
      description: "Highlight text like a marker pen (one bar per text row).",
      parameters: object([
        ("target", target("Text to highlight.")),
        ("color", color),
      ], required: ["target"])
    ),
    AnnotateAgentToolSpec(
      name: .addBlur,
      description: "Hide something (e-mail, name, token) with a blur.",
      parameters: object([
        ("target", target("What to hide.")),
        ("kind", string("Blur style.", enum: BlurType.allCases.map(\.rawValue))),
      ], required: ["target"])
    ),
    AnnotateAgentToolSpec(
      name: .addSpotlight,
      description: "Dim everything except the target.",
      parameters: object([
        ("target", target("What stays bright.")),
        ("padding", number("Extra space around the target, default 8.")),
      ], required: ["target"])
    ),
    AnnotateAgentToolSpec(
      name: .addCounter,
      description: "Place a numbered step badge next to a target. Numbers continue from existing badges unless given.",
      parameters: object([
        ("target", target("What the step refers to.")),
        ("number", integer("Optional explicit number.")),
        ("color", color),
        ("placement", string("Side of the target.", enum: ["auto", "left", "right", "above", "below", "over"])),
      ], required: ["target"])
    ),
    AnnotateAgentToolSpec(
      name: .addWatermark,
      description: "Add a watermark text over the image.",
      parameters: object([
        ("text", string("Watermark text.")),
        ("style", string("Layout.", enum: WatermarkStyle.allCases.map(\.rawValue))),
      ], required: ["text"])
    ),
    AnnotateAgentToolSpec(
      name: .updateAnnotation,
      description: "Change an existing annotation (a#). Only the given fields change.",
      parameters: object([
        ("id", string("Annotation id, e.g. a5.")),
        ("color", color),
        ("stroke_width", strokeWidth),
        ("font_size", number("Font size 12–72 (text).")),
        ("opacity", number("0.1–1.")),
        ("text", string("New text (text and watermark).")),
        ("style", string("Text style.", enum: ["plain", "label", "callout"])),
        ("move_to", target("Center the annotation on this target.")),
      ], required: ["id"])
    ),
    AnnotateAgentToolSpec(
      name: .deleteAnnotations,
      description: "Delete annotations by id, or [\"all\"] for every annotation.",
      parameters: object([("ids", stringArray("Annotation ids (a#) or [\"all\"]."))], required: ["ids"])
    ),
    AnnotateAgentToolSpec(
      name: .arrange,
      description: "Change stacking order of annotations.",
      parameters: object([
        ("ids", stringArray("Annotation ids (a#).")),
        ("order", string("New position.", enum: ["front", "forward", "backward", "back"])),
      ], required: ["ids", "order"])
    ),
    AnnotateAgentToolSpec(
      name: .select,
      description: "Select annotations so the user can keep editing them.",
      parameters: object([("ids", stringArray("Annotation ids (a#)."))], required: ["ids"])
    ),
    AnnotateAgentToolSpec(
      name: .setCanvas,
      description: "Style the canvas around the screenshot: background, padding, inset, shadow, rounded corners, alignment.",
      parameters: object([
        ("background", string("\"none\", a gradient (\(GradientPreset.allCases.map(\.rawValue).joined(separator: ", "))) or a solid color (\(AnnotateAgentColor.validValuesDescription)).")),
        ("padding", number("Space around the image 0–100. A background needs padding to show; default 48 when a background is set.")),
        ("inset", number("Inner inset 0–50.")),
        ("shadow", number("Shadow 0–1.")),
        ("corner_radius", number("Image corner radius 0–32.")),
        ("alignment", string("Image position on the canvas.", enum: ImageAlignment.allCases.map(\.rawValue))),
      ])
    ),
  ]

  static func spec(named name: String) -> AnnotateAgentToolSpec? {
    all.first { $0.name.rawValue == name }
  }
}
