//
//  VideoEditorAgentTranscript.swift
//  Snapzy
//
//  What the AI panel shows: the conversation as messages, and each assistant reply's
//  edits as steps ("Cut 0:10.0 – 0:15.0", "Zoom 2× at 0:12.0"). A step that has a time
//  moves the playhead there when clicked, so every change can be checked in place.
//

import Foundation

struct VideoEditorAgentMessage: Identifiable, Equatable {
  enum Role: Equatable {
    case user
    case assistant
  }

  enum Outcome: Equatable {
    case running
    case finished
    case stopped
    case failed(offersSettings: Bool)
  }

  let id: UUID
  let role: Role
  /// The prompt, or the reply (markdown) once the run ends.
  var text: String
  var steps: [VideoEditorAgentStep]
  var outcome: Outcome
  var changeCount: Int
  /// Set when Undo took this reply's changes back.
  var isUndone: Bool
  /// Quick actions answer without a prompt; the panel labels them.
  var quickActionTitle: String?

  static func user(_ text: String) -> VideoEditorAgentMessage {
    VideoEditorAgentMessage(
      id: UUID(), role: .user, text: text, steps: [], outcome: .finished,
      changeCount: 0, isUndone: false, quickActionTitle: nil
    )
  }

  static func pendingReply(quickActionTitle: String? = nil) -> VideoEditorAgentMessage {
    VideoEditorAgentMessage(
      id: UUID(), role: .assistant, text: "", steps: [], outcome: .running,
      changeCount: 0, isUndone: false, quickActionTitle: quickActionTitle
    )
  }
}

struct VideoEditorAgentStep: Identifiable, Equatable {
  let id = UUID()
  let symbolName: String
  let title: String
  /// Secondary line ("2.0 s", "−5.0 s").
  var detail: String?
  /// Timeline seconds the step is about; clicking the step seeks here.
  var time: TimeInterval?

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.id == rhs.id && lhs.title == rhs.title && lhs.detail == rhs.detail && lhs.time == rhs.time
  }
}

// MARK: - Describing tool calls

enum VideoEditorAgentStepDescriber {
  /// A step for a successful change; `nil` for reads and failed calls (the model retries those).
  static func step(
    for tool: VideoEditorAgentToolName,
    argumentsJSON: String,
    result: AgentToolResult
  ) -> VideoEditorAgentStep? {
    guard !tool.isReadOnly, !result.isError else { return nil }
    let args = object(argumentsJSON)
    let payload = object(result.text)
    let clock = VideoEditorAgentToolbox.clock

    switch tool {
    case .cutRange:
      let start = seconds(args["start"])
      let end = seconds(args["end"])
      let removed = number(payload["removed_seconds"])
      return VideoEditorAgentStep(
        symbolName: "scissors",
        title: L10n.VideoEditorAI.stepCut(clock(start ?? 0), clock(end ?? 0)),
        detail: removed.map { "−" + format($0) + " s" },
        time: start
      )
    case .trimClip:
      let clip = (args["clip"] as? String) ?? ""
      return VideoEditorAgentStep(
        symbolName: "timeline.selection",
        title: L10n.VideoEditorAI.stepTrim(clip.uppercased()),
        detail: range(seconds(args["start"]), seconds(args["end"])),
        time: seconds(payload["start"]) ?? seconds(args["start"])
      )
    case .split:
      let time = seconds(args["time"])
      return VideoEditorAgentStep(
        symbolName: "square.split.2x1",
        title: L10n.VideoEditorAI.stepSplit(clock(time ?? 0)),
        time: time
      )
    case .moveClip:
      let clip = ((args["clip"] as? String) ?? "").uppercased()
      let position = number(args["position"]).map { Int($0) } ?? 1
      return VideoEditorAgentStep(symbolName: "arrow.left.arrow.right", title: L10n.VideoEditorAI.stepMove(clip, position))
    case .deleteClip:
      let clip = ((args["clip"] as? String) ?? "").uppercased()
      return VideoEditorAgentStep(symbolName: "trash", title: L10n.VideoEditorAI.stepDeleteClip(clip))
    case .addZoom:
      let start = seconds(payload["start"]) ?? seconds(args["start"])
      let end = seconds(payload["end"])
      let level = number(payload["level"]) ?? number(args["level"]) ?? Double(ZoomSegment.defaultZoomLevel)
      return VideoEditorAgentStep(
        symbolName: "plus.magnifyingglass",
        title: L10n.VideoEditorAI.stepZoom(format(level), clock(start ?? 0)),
        detail: duration(start, end),
        time: start
      )
    case .updateZoom:
      let id = ((payload["id"] as? String) ?? (args["id"] as? String) ?? "").uppercased()
      let start = seconds(payload["start"])
      return VideoEditorAgentStep(
        symbolName: "slider.horizontal.3",
        title: L10n.VideoEditorAI.stepEditZoom(id),
        detail: range(start, seconds(payload["end"])),
        time: start
      )
    case .removeZoom:
      return VideoEditorAgentStep(symbolName: "minus.magnifyingglass", title: L10n.VideoEditorAI.stepRemoveZoom(ids(args)))
    case .addSpeed:
      let start = seconds(payload["start"]) ?? seconds(args["start"])
      let end = seconds(payload["end"]) ?? seconds(args["end"])
      let rate = number(payload["rate"]) ?? number(args["rate"]) ?? 1
      return VideoEditorAgentStep(
        symbolName: "gauge.with.dots.needle.67percent",
        title: L10n.VideoEditorAI.stepSpeed(format(rate)),
        detail: range(start, end),
        time: start
      )
    case .updateSpeed:
      let id = ((payload["id"] as? String) ?? (args["id"] as? String) ?? "").uppercased()
      let start = seconds(payload["start"])
      return VideoEditorAgentStep(
        symbolName: "slider.horizontal.3",
        title: L10n.VideoEditorAI.stepEditSpeed(id),
        detail: range(start, seconds(payload["end"])),
        time: start
      )
    case .removeSpeed:
      return VideoEditorAgentStep(symbolName: "gauge.with.dots.needle.0percent", title: L10n.VideoEditorAI.stepRemoveSpeed(ids(args)))
    case .setBackground:
      return VideoEditorAgentStep(symbolName: "paintpalette", title: L10n.VideoEditorAI.stepBackground)
    case .setAudio:
      if (args["muted"] as? Bool) == true {
        return VideoEditorAgentStep(symbolName: "speaker.slash", title: L10n.VideoEditorAI.stepMuted)
      }
      let volume = number(args["volume"]).map { "\(Int($0))%" }
      return VideoEditorAgentStep(symbolName: "speaker.wave.2", title: L10n.VideoEditorAI.stepAudio, detail: volume)
    case .removeSilences:
      return oneStep(.removeSilences, payload: payload, symbolName: "waveform.badge.minus")
    case .speedUpIdle:
      return oneStep(.speedUpIdle, payload: payload, symbolName: "forward.fill")
    case .autoZoomActivity:
      return oneStep(.autoZoom, payload: payload, symbolName: "plus.magnifyingglass")
    case .getTimeline, .seek, .getActivity, .getFrame, .findOnScreen, .getTranscript:
      return nil
    }
  }

  private static func oneStep(
    _ action: VideoEditorAgentController.QuickAction,
    payload: [String: Any],
    symbolName: String
  ) -> VideoEditorAgentStep? {
    // Nothing found: not an edit, the reply says so.
    let count = (payload["cuts"] as? Int) ?? (payload["added"] as? [Any])?.count ?? 0
    guard count > 0 else { return nil }
    return VideoEditorAgentStep(
      symbolName: symbolName,
      title: VideoEditorAgentController.quickMessage(action, payload: payload),
      time: firstTime(payload)
    )
  }

  private static func firstTime(_ payload: [String: Any]) -> TimeInterval? {
    if let removed = payload["removed"] as? [[Double]], let first = removed.first?.first { return first }
    if let added = payload["added"] as? [[String: Any]], let first = added.first?["start"] as? Double { return first }
    return nil
  }

  // MARK: Helpers

  private static func object(_ json: String) -> [String: Any] {
    guard let data = json.data(using: .utf8), !data.isEmpty else { return [:] }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
  }

  private static func number(_ value: Any?) -> Double? {
    switch value {
    case let value as NSNumber: value.doubleValue
    case let value as String: Double(value)
    default: nil
    }
  }

  /// Seconds as a number or "m:ss.s".
  private static func seconds(_ value: Any?) -> Double? {
    if let value = value as? String { return VideoEditorAgentTime.parse(value) }
    return number(value)
  }

  private static func ids(_ args: [String: Any]) -> String {
    let list = (args["ids"] as? [String]) ?? []
    return list.map { $0.lowercased() == "all" ? L10n.VideoEditorAI.stepAll : $0.uppercased() }.joined(separator: ", ")
  }

  private static func range(_ start: Double?, _ end: Double?) -> String? {
    guard let start, let end else { return nil }
    return "\(VideoEditorAgentToolbox.clock(start)) – \(VideoEditorAgentToolbox.clock(end))"
  }

  private static func duration(_ start: Double?, _ end: Double?) -> String? {
    guard let start, let end, end > start else { return nil }
    return format(end - start) + " s"
  }

  static func format(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
  }
}
