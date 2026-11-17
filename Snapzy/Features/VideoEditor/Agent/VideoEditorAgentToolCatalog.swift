//
//  VideoEditorAgentToolCatalog.swift
//  Snapzy
//
//  Names, descriptions and JSON schemas of the Video Editor agent tools. Times
//  are seconds on the structural timeline (the ruler the user sees); a number or
//  "m:ss.s" text is accepted. Ids are short: c1… clips, z1… zooms, s1… speeds.
//

import Foundation

nonisolated enum VideoEditorAgentToolName: String, CaseIterable {
  case getTimeline = "get_timeline"
  case seek
  case cutRange = "cut_range"
  case trimClip = "trim_clip"
  case split
  case moveClip = "move_clip"
  case deleteClip = "delete_clip"
  case addZoom = "add_zoom"
  case updateZoom = "update_zoom"
  case removeZoom = "remove_zoom"
  case addSpeed = "add_speed"
  case updateSpeed = "update_speed"
  case removeSpeed = "remove_speed"
  case setBackground = "set_background"
  case setAudio = "set_audio"

  /// Read-only tools are not paced and don't count as changes. `seek` only moves the playhead.
  var isReadOnly: Bool {
    self == .getTimeline || self == .seek
  }
}

nonisolated enum VideoEditorAgentToolCatalog {
  // MARK: Schema helpers

  private typealias JSON = AnnotateAgentJSON

  private static func object(_ properties: [(String, JSON)], required: [String] = []) -> JSON {
    var pairs: [(String, JSON)] = [
      ("type", .string("object")),
      ("properties", .object(properties)),
    ]
    if !required.isEmpty {
      pairs.append(("required", .array(required.map { .string($0) })))
    }
    pairs.append(("additionalProperties", .bool(false)))
    return .object(pairs)
  }

  private static func string(_ description: String, enum values: [String]? = nil) -> JSON {
    var pairs: [(String, JSON)] = [("type", .string("string")), ("description", .string(description))]
    if let values { pairs.append(("enum", .array(values.map { .string($0) }))) }
    return .object(pairs)
  }

  private static func number(_ description: String) -> JSON {
    .object([("type", .string("number")), ("description", .string(description))])
  }

  private static func integer(_ description: String) -> JSON {
    .object([("type", .string("integer")), ("description", .string(description))])
  }

  private static func bool(_ description: String) -> JSON {
    .object([("type", .string("boolean")), ("description", .string(description))])
  }

  /// Seconds as a number, or "m:ss.s" text; loose on purpose so small models get it right.
  private static func time(_ description: String) -> JSON {
    .object([
      ("description", .string(description + " Seconds on the timeline (number) or \"m:ss.s\".")),
      ("anyOf", .array([.object([("type", .string("number"))]), .object([("type", .string("string"))])])),
    ])
  }

  private static func ids(_ description: String) -> JSON {
    .object([
      ("type", .string("array")),
      ("items", .object([("type", .string("string"))])),
      ("description", .string(description)),
    ])
  }

  private static func point(_ description: String) -> JSON {
    .object([
      ("type", .string("array")),
      ("items", .object([("type", .string("number"))])),
      ("minItems", .number(2)),
      ("maxItems", .number(2)),
      ("description", .string(description)),
    ])
  }

  private static func spec(_ name: VideoEditorAgentToolName, _ description: String, _ parameters: JSON) -> AgentToolSpec {
    AgentToolSpec(name: name.rawValue, description: description, parametersJSON: parameters.serialized)
  }

  // MARK: Tools

  static let backgroundStyles = ["none"] + GradientPreset.allCases.map(\.rawValue)
  static let alignments = ImageAlignment.allCases.map(\.rawValue)
  static let aspectRatios = ["original", "free", "1:1", "4:3", "3:2", "16:9"]

  static let all: [AgentToolSpec] = [
    spec(
      .getTimeline,
      "Read the timeline: duration, clips (c#), zooms (z#), speed blocks (s#), background, audio, playhead and selection.",
      object([])
    ),
    spec(
      .seek,
      "Move the playhead so the user sees a spot. Does not change the video.",
      object([("time", time("Where to put the playhead."))], required: ["time"])
    ),
    spec(
      .cutRange,
      "Remove a part of the video; everything after it slides left. Cut before adding effects.",
      object([
        ("start", time("Start of the part to remove.")),
        ("end", time("End of the part to remove.")),
        ("shift_effects", bool("Slide zoom and speed blocks after the cut left with the video (default true).")),
      ], required: ["start", "end"])
    ),
    spec(
      .trimClip,
      "Change which part of a clip plays, within the clip's own span on the timeline. Nothing slides.",
      object([
        ("clip", string("Clip id, like c1.")),
        ("start", time("New start of the playing part.")),
        ("end", time("New end of the playing part.")),
      ], required: ["clip"])
    ),
    spec(
      .split,
      "Split the clip at a time into two clips.",
      object([("time", time("Where to split."))], required: ["time"])
    ),
    spec(
      .moveClip,
      "Move a clip to another position in the sequence.",
      object([
        ("clip", string("Clip id, like c2.")),
        ("position", integer("New position, 1 = first.")),
      ], required: ["clip", "position"])
    ),
    spec(
      .deleteClip,
      "Delete a whole clip; the rest slides left. Effects stay where they are.",
      object([("clip", string("Clip id, like c2."))], required: ["clip"])
    ),
    spec(
      .addZoom,
      "Zoom in for a while. Without center it follows the mouse when the recording has mouse data, else zooms on the middle.",
      object([
        ("start", time("When the zoom starts.")),
        ("duration", number("Seconds, \(fmt(ZoomSegment.minDuration))–\(fmt(ZoomSegment.maxDuration)) (default \(fmt(ZoomSegment.defaultDuration))).")),
        ("level", number("Zoom factor \(fmt(ZoomSegment.minZoomLevel))–\(fmt(ZoomSegment.maxZoomLevel)) (default \(fmt(ZoomSegment.defaultZoomLevel))).")),
        ("center", point("Point to zoom on, [x, y] from 0 to 1, origin at the top left.")),
        ("follow_mouse", bool("Follow the recorded mouse instead of a fixed center.")),
      ], required: ["start"])
    ),
    spec(
      .updateZoom,
      "Change a zoom block.",
      object([
        ("id", string("Zoom id, like z1.")),
        ("start", time("New start.")),
        ("duration", number("New length in seconds.")),
        ("level", number("Zoom factor \(fmt(ZoomSegment.minZoomLevel))–\(fmt(ZoomSegment.maxZoomLevel)).")),
        ("center", point("Fixed point [x, y] from 0 to 1, origin at the top left.")),
        ("follow_mouse", bool("true: follow the mouse; false: fixed center.")),
        ("enabled", bool("Turn the block on or off.")),
      ], required: ["id"])
    ),
    spec(
      .removeZoom,
      "Remove zoom blocks.",
      object([("ids", ids("Zoom ids like [\"z1\"], or [\"all\"]."))], required: ["ids"])
    ),
    spec(
      .addSpeed,
      "Play a part faster or slower. Speed blocks cannot overlap.",
      object([
        ("start", time("Start of the part.")),
        ("end", time("End of the part.")),
        ("rate", number("\(fmt(SpeedSegment.minRate))–\(fmt(SpeedSegment.maxRate)); 4 = four times faster, 0.5 = half speed.")),
      ], required: ["start", "end", "rate"])
    ),
    spec(
      .updateSpeed,
      "Change a speed block.",
      object([
        ("id", string("Speed id, like s1.")),
        ("start", time("New start.")),
        ("end", time("New end.")),
        ("rate", number("\(fmt(SpeedSegment.minRate))–\(fmt(SpeedSegment.maxRate)).")),
        ("enabled", bool("Turn the block on or off.")),
      ], required: ["id"])
    ),
    spec(
      .removeSpeed,
      "Remove speed blocks.",
      object([("ids", ids("Speed ids like [\"s1\"], or [\"all\"]."))], required: ["ids"])
    ),
    spec(
      .setBackground,
      "Frame the video: background behind it, padding, shadow, rounded corners, alignment, canvas aspect ratio.",
      object([
        ("style", string("none, a gradient (\(GradientPreset.allCases.map(\.rawValue).joined(separator: ", "))) or a color name/hex.")),
        ("padding", number("Space around the video in points, 0–300.")),
        ("shadow", number("Shadow strength 0–1.")),
        ("corner_radius", number("Corner radius in points, 0–60.")),
        ("alignment", string("Where the video sits in the canvas.", enum: alignments)),
        ("aspect_ratio", string("Canvas shape.", enum: aspectRatios)),
      ])
    ),
    spec(
      .setAudio,
      "Mute or change the exported audio volume.",
      object([
        ("muted", bool("true removes all audio; false keeps it.")),
        ("volume", number("Percent, 0–200 (100 = original).")),
        ("track", string("Which audio to change (default all).", enum: ["all", "system", "microphone"])),
      ])
    ),
  ]

  private static func fmt(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(value)
  }

  private static func fmt(_ value: CGFloat) -> String {
    fmt(Double(value))
  }
}
