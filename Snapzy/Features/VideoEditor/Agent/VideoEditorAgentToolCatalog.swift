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
  case getActivity = "get_activity"
  case removeSilences = "remove_silences"
  case speedUpIdle = "speed_up_idle"
  case autoZoomActivity = "auto_zoom_activity"
  case getFrame = "get_frame"
  case findOnScreen = "find_on_screen"
  case getTranscript = "get_transcript"

  /// Read-only tools are not paced and don't count as changes. `seek` only moves the playhead.
  var isReadOnly: Bool {
    switch self {
    case .getTimeline, .seek, .getActivity, .getFrame, .findOnScreen, .getTranscript: true
    default: false
    }
  }

  /// Looks at frames or listens to speech, which takes a while (`VideoEditorAgentVision`,
  /// `VideoEditorAgentTranscriber`). `add_zoom` does too when it is given `text`.
  var readsMedia: Bool {
    self == .getFrame || self == .findOnScreen || self == .getTranscript
  }

  /// Reads the recording's audio and cursor first (`VideoEditorAgentAnalyzer`).
  var needsAnalysis: Bool {
    self == .getActivity || isOneStep
  }

  /// One call, many edits, worked out in the app; each edit counts toward the run's limit.
  var isOneStep: Bool {
    self == .removeSilences || self == .speedUpIdle || self == .autoZoomActivity
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
      "Zoom in for a while. Give text to zoom on words or a button on screen: it is found in the video and the zoom "
        + "starts when it appears (after start, when given). Without center or text it follows the mouse when the "
        + "recording has mouse data, else zooms on the middle.",
      object([
        ("start", time("When the zoom starts. Required unless text is given.")),
        ("duration", number("Seconds, \(fmt(ZoomSegment.minDuration))–\(fmt(ZoomSegment.maxDuration)) (default \(fmt(ZoomSegment.defaultDuration))).")),
        ("level", number("Zoom factor \(fmt(ZoomSegment.minZoomLevel))–\(fmt(ZoomSegment.maxZoomLevel)) (default \(fmt(ZoomSegment.defaultZoomLevel))).")),
        ("center", point("Point to zoom on, [x, y] from 0 to 1, origin at the top left.")),
        ("follow_mouse", bool("Follow the recorded mouse instead of a fixed center.")),
        ("text", string("Words shown on screen to zoom on, like a button label (\"Deploy\").")),
      ])
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
    spec(
      .getActivity,
      "What happens when in the recording: silence and speech in the audio, idle (cursor still, nobody talking) "
        + "and motion (cursor moving; area = [x, y, w, h] it covered, 0–1 from the top left). Inserted videos are not analyzed.",
      object([
        ("start", time("Only report from here (default: the start).")),
        ("end", time("Only report up to here (default: the end).")),
      ])
    ),
    spec(
      .removeSilences,
      "Cut every pause in the audio at once, latest first; zooms and speeds follow. Use this instead of cutting silences one by one.",
      object([
        ("min_duration", number("Only pauses at least this long, in seconds (default \(fmt(VideoEditorAgentToolbox.silenceDefaults.minDuration))).")),
        ("padding", number("Seconds of pause kept on each side so speech isn't clipped (default \(fmt(VideoEditorAgentToolbox.silenceDefaults.padding))).")),
        ("start", time("Only from here.")),
        ("end", time("Only up to here.")),
      ])
    ),
    spec(
      .speedUpIdle,
      "Speed up every stretch where the cursor stays still and nobody talks (waiting for a build, a page to load).",
      object([
        ("rate", number("\(fmt(SpeedSegment.minRate))–\(fmt(SpeedSegment.maxRate)) (default \(fmt(VideoEditorAgentToolbox.idleDefaults.rate))).")),
        ("min_duration", number("Only stretches at least this long, in seconds (default \(fmt(VideoEditorAgentToolbox.idleDefaults.minDuration))).")),
        ("start", time("Only from here.")),
        ("end", time("Only up to here.")),
      ])
    ),
    spec(
      .autoZoomActivity,
      "Add zooms that follow the cursor where it works in a small area (typing, clicking through a form). Skips parts that already zoom.",
      object([
        ("level", number("Zoom factor \(fmt(ZoomSegment.minZoomLevel))–\(fmt(ZoomSegment.maxZoomLevel)) (default \(fmt(ZoomSegment.defaultZoomLevel))).")),
        ("max_zooms", integer("At most this many zooms (default \(VideoEditorAgentToolbox.autoZoomDefaults.maxZooms)).")),
        ("start", time("Only from here.")),
        ("end", time("Only up to here.")),
      ])
    ),
    spec(
      .getFrame,
      "Look at the recording at a time: the frame as an image when you can see images, and the text on it "
        + "with boxes [x, y, w, h] from 0 to 1 (top left), the same space as zoom centers. Raw footage, without zoom or background.",
      object([("time", time("Which moment."))], required: ["time"])
    ),
    spec(
      .findOnScreen,
      "Find when and where words appear on screen (a button, a title, an error). Reads frames across the video, "
        + "so it takes a few seconds; narrow it with start and end when you can.",
      object([
        ("text", string("The words to find; case and accents don't matter.")),
        ("start", time("Only from here.")),
        ("end", time("Only up to here.")),
      ], required: ["text"])
    ),
    spec(
      .getTranscript,
      "What is said in the recording, as timed phrases (transcribed on this Mac; the first call takes a while).",
      object([
        ("start", time("Only from here.")),
        ("end", time("Only up to here.")),
        ("language", string("Spoken language, BCP-47 like en-US or vi-VN (default: the Mac's language).")),
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
