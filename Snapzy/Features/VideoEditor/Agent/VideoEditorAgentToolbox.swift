//
//  VideoEditorAgentToolbox.swift
//  Snapzy
//
//  The one place where an agent's tool calls become Video Editor edits. Every
//  provider (custom endpoint, agent CLI over MCP, mock) calls `execute`.
//
//  - Arguments and results are JSON, so providers only pass strings through.
//  - Times in and out are seconds on the structural timeline (the ruler).
//  - Ids are short and stable for the toolbox's life: c# clips, z# zooms, s# speeds.
//  - A run (one prompt) is one undo group in `VideoEditorState`: one ⌘Z undoes it all.
//  - Export, save, share and file access are deliberately not tools.
//

import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

nonisolated struct VideoEditorAgentRunSummary: Equatable {
  let changeCount: Int
  /// The undo entry the run pushed (nil when it changed nothing). The result pill
  /// offers Undo only while this is still the latest entry.
  let undoEntry: EditorAction?
}

/// Errors are written for the model: each says what to do instead.
nonisolated enum VideoEditorAgentToolError: Error, Equatable {
  case unknownTool(String)
  case invalidArguments(String)
  case notFound(String)
  case unavailable(String)
  case limitReached(Int)

  var message: String {
    switch self {
    case .unknownTool(let name):
      return "Unknown tool '\(name)'. Use one of: \(VideoEditorAgentToolName.allCases.map(\.rawValue).joined(separator: ", "))."
    case .invalidArguments(let detail):
      return "Invalid arguments: \(detail)"
    case .notFound(let detail):
      return "Not found: \(detail). Call get_timeline for the current ids."
    case .unavailable(let detail):
      return detail
    case .limitReached(let limit):
      return "This request already made \(limit) changes, the limit for one request. Stop and summarize."
    }
  }
}

@MainActor
final class VideoEditorAgentToolbox {
  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  static let maximumChangesPerRun = 80

  nonisolated static let silenceDefaults = (minDuration: 1.0, padding: 0.25)
  nonisolated static let idleDefaults = (rate: 4.0, minDuration: 3.0, padding: 0.3)
  nonisolated static let autoZoomDefaults = (maxZooms: 8, maxArea: 0.35, minActivity: 1.0)
  /// Spans `get_activity` lists before it keeps only the longest.
  static let maximumActivitySpans = 60

  private weak var state: VideoEditorState?
  let analyzer: VideoEditorAgentAnalyzer

  private var references: [Kind: (byID: [UUID: String], byRef: [String: UUID], next: Int)] = [
    .clip: ([:], [:], 1), .zoom: ([:], [:], 1), .speed: ([:], [:], 1), .caption: ([:], [:], 1), .hidden: ([:], [:], 1),
  ]

  private var isRunOpen = false
  private var changeCount = 0

  /// Every finished call (name, raw arguments, result), so the AI panel can list the edits.
  var onExecuted: ((VideoEditorAgentToolName, String, AgentToolResult) -> Void)?

  init(state: VideoEditorState, analyzer: VideoEditorAgentAnalyzer? = nil) {
    self.state = state
    self.analyzer = analyzer ?? VideoEditorAgentAnalyzer()
  }

  // MARK: - Run lifecycle

  /// Opens the run's undo group. Pair with `finishRun`, also when the run fails or is stopped.
  func beginRun() {
    guard !isRunOpen, let state else { return }
    isRunOpen = true
    changeCount = 0
    state.beginUndoGroup()
  }

  @discardableResult
  func finishRun() -> VideoEditorAgentRunSummary {
    guard isRunOpen else { return VideoEditorAgentRunSummary(changeCount: 0, undoEntry: nil) }
    isRunOpen = false
    let entry = state?.endUndoGroup()
    return VideoEditorAgentRunSummary(changeCount: changeCount, undoEntry: entry)
  }

  // MARK: - References

  enum Kind: String {
    case clip = "c"
    case zoom = "z"
    case speed = "s"
    case caption = "t"
    case hidden = "h"
  }

  func reference(_ kind: Kind, for id: UUID) -> String {
    if let existing = references[kind]?.byID[id] { return existing }
    var table = references[kind]!
    let reference = "\(kind.rawValue)\(table.next)"
    table.next += 1
    table.byID[id] = reference
    table.byRef[reference] = id
    references[kind] = table
    return reference
  }

  /// Point an existing reference at a new object (a split's first half keeps its clip's id).
  private func rebind(_ kind: Kind, from oldID: UUID, to newID: UUID) {
    guard var table = references[kind], let reference = table.byID.removeValue(forKey: oldID) else { return }
    table.byID[newID] = reference
    table.byRef[reference] = newID
    references[kind] = table
  }

  func lookup(_ kind: Kind, _ reference: String) -> UUID? {
    references[kind]?.byRef[reference.trimmingCharacters(in: .whitespaces).lowercased()]
  }

  func clipReference(for id: UUID) -> String { reference(.clip, for: id) }
  func zoomReference(for id: UUID) -> String { reference(.zoom, for: id) }
  func speedReference(for id: UUID) -> String { reference(.speed, for: id) }

  // MARK: - Scene

  func scene() -> VideoEditorAgentScene? {
    guard let state, !state.isGIF, !state.clips.isEmpty else { return nil }
    let structural = state.placements
    let clips = structural.map { placement -> VideoEditorAgentScene.Clip in
      let clip = placement.clip
      return VideoEditorAgentScene.Clip(
        id: reference(.clip, for: clip.id),
        start: Self.round(placement.start),
        end: Self.round(placement.end),
        playsFrom: Self.round(placement.activeStart),
        playsTo: Self.round(placement.activeEnd),
        source: clip.url?.lastPathComponent ?? "recording"
      )
    }
    let zooms = state.zoomSegments.sorted { $0.startTime < $1.startTime }.map { segment in
      VideoEditorAgentScene.Zoom(
        id: reference(.zoom, for: segment.id),
        start: Self.round(segment.startTime),
        end: Self.round(segment.endTime),
        level: Self.round(Double(segment.zoomLevel)),
        center: segment.zoomType == .auto ? nil : [Self.round(segment.zoomCenter.x), Self.round(segment.zoomCenter.y)],
        followMouse: segment.zoomType == .auto,
        enabled: segment.isEnabled
      )
    }
    let speeds = state.speedSegments.sorted { $0.startTime < $1.startTime }.map { segment in
      VideoEditorAgentScene.Speed(
        id: reference(.speed, for: segment.id),
        start: Self.round(segment.startTime),
        end: Self.round(segment.endTime),
        rate: Self.round(segment.rate),
        enabled: segment.isEnabled
      )
    }
    let settings = state.exportSettings
    let tracks = state.audioTrackRoles.map { role in
      VideoEditorAgentScene.AudioTrack(
        name: Self.trackName(role),
        volume: Int((settings.effectiveVolume(for: role) * 100).rounded())
      )
    }
    let selection = VideoEditorAgentScene.Selection(
      clip: state.selectedClipId.flatMap { id in state.clips.contains { $0.id == id } ? reference(.clip, for: id) : nil },
      zoom: state.selectedZoomId.flatMap { id in state.zoomSegments.contains { $0.id == id } ? reference(.zoom, for: id) : nil },
      speed: state.selectedSpeedId.flatMap { id in state.speedSegments.contains { $0.id == id } ? reference(.speed, for: id) : nil }
    )

    return VideoEditorAgentScene(
      duration: Self.round(CMTimeGetSeconds(state.timelineDuration)),
      playableDuration: Self.round(state.sequenceDuration),
      outputDuration: Self.round(CMTimeGetSeconds(state.effectiveOutputDuration)),
      size: [Int(state.naturalSize.width.rounded()), Int(state.naturalSize.height.rounded())],
      playhead: Self.round(CMTimeGetSeconds(state.currentTime)),
      clips: clips,
      zooms: zooms,
      speeds: speeds,
      background: .init(
        style: Self.describe(state.backgroundStyle),
        padding: Int(state.backgroundPadding.rounded()),
        shadow: Self.round(Double(state.backgroundShadowIntensity)),
        cornerRadius: Int(state.backgroundCornerRadius.rounded()),
        alignment: state.backgroundAlignment.rawValue,
        aspectRatio: Self.describe(state.backgroundAspectRatio)
      ),
      audio: .init(muted: settings.audioMode == .mute, tracks: tracks),
      selection: selection,
      hasMouseData: state.hasMouseTrackingData,
      studio: isStudioRecording(state),
      cursor: studioCursorScene(state),
      camera: studioCameraScene(state),
      captions: captionsScene(state),
      availableFonts: availableFontsList()
    )
  }

  // MARK: - Execute

  func execute(name: String, argumentsJSON: String) async -> AgentToolResult {
    let result = await performExecute(name: name, argumentsJSON: argumentsJSON)
    if let tool = VideoEditorAgentToolName(rawValue: name) {
      onExecuted?(tool, argumentsJSON, result)
    }
    return result
  }

  private func performExecute(name: String, argumentsJSON: String) async -> AgentToolResult {
    // Tools that read the recording wait for its analysis (cached after the first).
    if let tool = VideoEditorAgentToolName(rawValue: name), tool.needsAnalysis,
       let state, !state.isGIF, !state.clips.isEmpty {
      do {
        _ = try await analyzer.activity(for: state)
      } catch is CancellationError {
        return .failure(message: "Stopped.")
      } catch {
        return .failure(message: VideoEditorAgentToolError.unavailable(
          "The recording could not be analyzed (\(error.localizedDescription)). Work from the timeline instead."
        ).message)
      }
    }
    let arguments = argumentsJSON.isEmpty ? Data("{}".utf8) : Data(argumentsJSON.utf8)
    if let tool = VideoEditorAgentToolName(rawValue: name), tool.readsMedia || tool == .addZoom {
      do {
        if let result = try await performMedia(tool, arguments: arguments) {
          if !tool.isReadOnly { changeCount += 1 }
          return result
        }
      } catch {
        return Self.failure(for: error)
      }
    }
    return execute(name: name, arguments: arguments)
  }

  /// Runs one tool call. Never throws: failures come back as error results the model can read.
  func execute(name: String, arguments: Data) -> AgentToolResult {
    guard let tool = VideoEditorAgentToolName(rawValue: name) else {
      return .failure(message: VideoEditorAgentToolError.unknownTool(name).message)
    }
    do {
      let body = arguments.isEmpty ? Data("{}".utf8) : arguments
      let result = try perform(tool, arguments: body)
      // One-step tools count each edit they make themselves.
      if !tool.isReadOnly, !tool.isOneStep { changeCount += 1 }
      return result
    } catch {
      return Self.failure(for: error)
    }
  }

  private static func failure(for error: Error) -> AgentToolResult {
    switch error {
    case let error as VideoEditorAgentToolError:
      return .failure(message: error.message)
    case let error as DecodingError:
      return .failure(message: VideoEditorAgentToolError.invalidArguments(describe(error)).message)
    case let error as VideoEditorTranscriptError:
      return .failure(message: error.message)
    case VideoEditorVisionError.noFootage(let time):
      return .failure(message: "Nothing plays at \(clock(time)) (trimmed out or past the end). Pick a time inside a clip's playing part.")
    case is CancellationError:
      return .failure(message: "Stopped.")
    case is VideoEditorVisionError, is AVError:
      return .failure(message: "The video frames could not be read (\(error.localizedDescription)). Work from the timeline instead.")
    default:
      return .failure(message: VideoEditorAgentToolError.invalidArguments(error.localizedDescription).message)
    }
  }

  private func perform(_ tool: VideoEditorAgentToolName, arguments: Data) throws -> AgentToolResult {
    let state = try readyState()
    if !tool.isReadOnly, changeCount >= Self.maximumChangesPerRun {
      throw VideoEditorAgentToolError.limitReached(Self.maximumChangesPerRun)
    }

    switch tool {
    case .getTimeline:
      guard let scene = scene() else { throw VideoEditorAgentToolError.unavailable("The video is still loading.") }
      return .encoded(scene)
    case .seek:
      return try seek(decode(TimeArguments.self, arguments), state: state)
    case .cutRange:
      return try cutRange(decode(CutArguments.self, arguments), state: state)
    case .trimClip:
      return try trimClip(decode(TrimArguments.self, arguments), state: state)
    case .split:
      return try split(decode(TimeArguments.self, arguments), state: state)
    case .moveClip:
      return try moveClip(decode(MoveArguments.self, arguments), state: state)
    case .deleteClip:
      return try deleteClip(decode(ClipArguments.self, arguments), state: state)
    case .closeGaps:
      return try closeGaps(decode(VideoEditorAgentCloseGapsArguments.self, arguments), state: state)
    case .addZoom:
      return try addZoom(decode(AddZoomArguments.self, arguments), state: state)
    case .updateZoom:
      return try updateZoom(decode(UpdateZoomArguments.self, arguments), state: state)
    case .removeZoom:
      return try removeZooms(decode(IDsArguments.self, arguments), state: state)
    case .addSpeed:
      return try addSpeed(decode(AddSpeedArguments.self, arguments), state: state)
    case .updateSpeed:
      return try updateSpeed(decode(UpdateSpeedArguments.self, arguments), state: state)
    case .removeSpeed:
      return try removeSpeeds(decode(IDsArguments.self, arguments), state: state)
    case .setBackground:
      return try setBackground(decode(BackgroundArguments.self, arguments), state: state)
    case .setAudio:
      return try setAudio(decode(AudioArguments.self, arguments), state: state)
    case .getActivity:
      return try getActivity(decode(RangeArguments.self, arguments), state: state)
    case .removeSilences:
      return try removeSilences(decode(SilenceArguments.self, arguments), state: state)
    case .speedUpIdle:
      return try speedUpIdle(decode(IdleArguments.self, arguments), state: state)
    case .autoZoomActivity:
      return try autoZoomActivity(decode(AutoZoomArguments.self, arguments), state: state)
    case .setCursor:
      return try setCursor(decode(VideoEditorAgentCursorArguments.self, arguments), state: state)
    case .setCamera:
      return try setCamera(decode(VideoEditorAgentCameraArguments.self, arguments), state: state)
    case .editCaption:
      return try editCaption(decode(VideoEditorAgentCaptionEditArguments.self, arguments), state: state)
    case .getCaptions:
      return try getCaptions(decode(VideoEditorAgentCaptionRangeArguments.self, arguments), state: state)
    case .addCaption:
      return try addCaption(decode(VideoEditorAgentAddCaptionArguments.self, arguments), state: state)
    case .removeCaptions:
      return try removeCaptions(decode(VideoEditorAgentCaptionIDsArguments.self, arguments), state: state)
    case .replaceInCaptions:
      return try replaceInCaptions(decode(VideoEditorAgentReplaceCaptionArguments.self, arguments), state: state)
    case .getFrame, .findOnScreen, .getTranscript, .generateCaptions, .translateCaptions:
      // Only through `execute(name:argumentsJSON:)`, which can wait for frames and speech.
      throw VideoEditorAgentToolError.unavailable("This tool is still working; call it again.")
    }
  }

  func readyState() throws -> VideoEditorState {
    guard let state else { throw VideoEditorAgentToolError.unavailable("No video is open.") }
    guard !state.isGIF else {
      throw VideoEditorAgentToolError.unavailable("This is a GIF; it can only be resized, not edited. Stop and tell the user.")
    }
    guard !state.isExporting else {
      throw VideoEditorAgentToolError.unavailable("The video is exporting. Stop and tell the user to try again when it finishes.")
    }
    guard !state.clips.isEmpty else { throw VideoEditorAgentToolError.unavailable("The video is still loading.") }
    return state
  }

  func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(type, from: data)
  }

  // MARK: - Timeline

  private func duration(_ state: VideoEditorState) -> TimeInterval {
    CMTimeGetSeconds(state.timelineDuration)
  }

  /// A time inside the timeline, or an error that says what the timeline spans.
  func time(_ value: VideoEditorAgentTime, _ state: VideoEditorState, name: String) throws -> TimeInterval {
    let total = duration(state)
    guard value.seconds <= total + 0.05 else {
      throw VideoEditorAgentToolError.invalidArguments(
        "\(name) \(Self.clock(value.seconds)) is after the end of the video (\(Self.clock(total)))."
      )
    }
    return min(value.seconds, total)
  }

  private func seek(_ args: TimeArguments, state: VideoEditorState) throws -> AgentToolResult {
    let t = try time(args.time, state, name: "time")
    state.seek(to: CMTime(seconds: t, preferredTimescale: 600))
    return .success(["playhead": Self.round(CMTimeGetSeconds(state.currentTime))])
  }

  private func cutRange(_ args: CutArguments, state: VideoEditorState) throws -> AgentToolResult {
    let start = try time(args.start, state, name: "start")
    let end = try time(args.end, state, name: "end")
    guard end - start >= TimelineClip.minDuration else {
      throw VideoEditorAgentToolError.invalidArguments(
        "end must be at least \(TimelineClip.minDuration)s after start."
      )
    }
    guard start > 0.05 || end < duration(state) - 0.05 else {
      throw VideoEditorAgentToolError.invalidArguments("That would remove the whole video.")
    }
    guard let removed = state.cutTimeline(range: start ... end) else {
      throw VideoEditorAgentToolError.invalidArguments("That would remove the whole video.")
    }
    let removedSeconds = removed.reduce(0) { $0 + $1.upperBound - $1.lowerBound }

    var payload: [String: Any] = [
      "removed_seconds": Self.round(removedSeconds),
      "new_duration": Self.round(duration(state)),
    ]
    if args.shiftEffects ?? true {
      let moved = shiftEffects(after: removed, state: state)
      payload["zooms_moved"] = moved.zoomsMoved
      payload["zooms_removed"] = moved.zoomsRemoved
      payload["speeds_moved"] = moved.speedsMoved
      payload["speeds_removed"] = moved.speedsRemoved
    }
    return .success(payload)
  }

  /// Slide zoom and speed blocks so they stay on the footage they were on.
  private func shiftEffects(
    after removed: [ClosedRange<TimeInterval>],
    state: VideoEditorState
  ) -> (zoomsMoved: [String], zoomsRemoved: [String], speedsMoved: [String], speedsRemoved: [String]) {
    var zoomsMoved: [String] = [], zoomsRemoved: [String] = []
    var speedsMoved: [String] = [], speedsRemoved: [String] = []

    for segment in state.zoomSegments.sorted(by: { $0.startTime < $1.startTime }) {
      let ref = reference(.zoom, for: segment.id)
      guard let range = VideoEditorTimelineCut.shifted(
        start: segment.startTime, end: segment.endTime, removing: removed, minDuration: ZoomSegment.minDuration
      ) else {
        state.removeZoom(id: segment.id)
        zoomsRemoved.append(ref)
        continue
      }
      guard abs(range.lowerBound - segment.startTime) > 0.0001 || abs(range.upperBound - segment.endTime) > 0.0001 else { continue }
      state.updateZoom(id: segment.id, startTime: range.lowerBound, duration: range.upperBound - range.lowerBound)
      zoomsMoved.append(ref)
    }

    // Ascending order: each block moves left into room its predecessor already left.
    for segment in state.speedSegments.sorted(by: { $0.startTime < $1.startTime }) {
      let ref = reference(.speed, for: segment.id)
      guard let range = VideoEditorTimelineCut.shifted(
        start: segment.startTime, end: segment.endTime, removing: removed, minDuration: SpeedSegment.minDuration
      ) else {
        state.removeSpeed(id: segment.id)
        speedsRemoved.append(ref)
        continue
      }
      guard abs(range.lowerBound - segment.startTime) > 0.0001 || abs(range.upperBound - segment.endTime) > 0.0001 else { continue }
      state.updateSpeed(id: segment.id, startTime: range.lowerBound, duration: range.upperBound - range.lowerBound)
      speedsMoved.append(ref)
    }
    return (zoomsMoved, zoomsRemoved, speedsMoved, speedsRemoved)
  }

  private func clipPlacement(_ reference: String, _ state: VideoEditorState) throws -> TimelineSequence.Placement {
    guard let id = lookup(.clip, reference), let placement = state.placements.first(where: { $0.clip.id == id }) else {
      throw VideoEditorAgentToolError.notFound("clip '\(reference)'")
    }
    return placement
  }

  private func trimClip(_ args: TrimArguments, state: VideoEditorState) throws -> AgentToolResult {
    let placement = try clipPlacement(args.clip, state)
    guard args.start != nil || args.end != nil else {
      throw VideoEditorAgentToolError.invalidArguments("Give start, end or both.")
    }
    let span = "\(args.clip) spans \(Self.clock(placement.start))–\(Self.clock(placement.end))"
    func inside(_ value: VideoEditorAgentTime?, _ name: String) throws -> TimeInterval? {
      guard let value else { return nil }
      guard value.seconds >= placement.start - 0.05, value.seconds <= placement.end + 0.05 else {
        throw VideoEditorAgentToolError.invalidArguments("\(name) must be inside the clip: \(span).")
      }
      return placement.sourceTime(at: min(max(value.seconds, placement.start), placement.end))
    }
    let sourceStart = try inside(args.start, "start")
    let sourceEnd = try inside(args.end, "end")
    if let sourceStart, let sourceEnd, sourceEnd - sourceStart < TimelineClip.minDuration {
      throw VideoEditorAgentToolError.invalidArguments("end must be after start.")
    }
    state.updateClip(id: placement.clip.id, sourceStart: sourceStart, sourceEnd: sourceEnd)
    let updated = try clipPlacement(args.clip, state)
    return .success([
      "clip": args.clip,
      "plays_from": Self.round(updated.activeStart),
      "plays_to": Self.round(updated.activeEnd),
    ])
  }

  private func split(_ args: TimeArguments, state: VideoEditorState) throws -> AgentToolResult {
    let t = try time(args.time, state, name: "time")
    let original = TimelineSequence.activePlacement(at: t, in: state.placements)?.clip.id
    guard let (first, second) = state.splitClip(atTimeline: t) else {
      throw VideoEditorAgentToolError.invalidArguments(
        "Can't split at \(Self.clock(t)): it must be on playing footage and at least \(TimelineClip.minDuration)s from a clip edge."
      )
    }
    if let original { rebind(.clip, from: original, to: first) }
    return .success(["clips": [reference(.clip, for: first), reference(.clip, for: second)]])
  }

  private func moveClip(_ args: MoveArguments, state: VideoEditorState) throws -> AgentToolResult {
    let placement = try clipPlacement(args.clip, state)
    guard args.position >= 1, args.position <= state.clips.count else {
      throw VideoEditorAgentToolError.invalidArguments("position must be 1–\(state.clips.count).")
    }
    let zeroBased = VideoEditorAgentStudioTools.clampedZeroBasedIndex(args.position, maxCount: state.clips.count)
    state.moveClip(id: placement.clip.id, toIndex: zeroBased)
    return .success(["clip": args.clip, "position": args.position])
  }

  private func deleteClip(_ args: ClipArguments, state: VideoEditorState) throws -> AgentToolResult {
    let placement = try clipPlacement(args.clip, state)
    guard state.clips.count > 1 else {
      throw VideoEditorAgentToolError.invalidArguments("It is the only clip; use cut_range to remove part of it.")
    }
    state.removeClip(id: placement.clip.id)
    return .success(["new_duration": Self.round(duration(state))])
  }

  private func closeGaps(_ args: VideoEditorAgentCloseGapsArguments, state: VideoEditorState) throws -> AgentToolResult {
    let raw = (args.clip ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else {
      throw VideoEditorAgentToolError.invalidArguments(
        "clip is required (give a clip id like \"c2\", or \"all\")."
      )
    }
    let beforeDuration = duration(state)
    if raw.lowercased() == "all" {
      state.closeAllGaps()
    } else {
      let placement = try clipPlacement(raw, state)
      state.closeGap(beforeClipIndex: placement.index)
    }
    let afterDuration = duration(state)
    return .success([
      "closed_seconds": Self.round(max(0, beforeDuration - afterDuration)),
      "new_duration": Self.round(afterDuration),
    ])
  }

  // MARK: - Zoom

  private func zoomID(_ reference: String, _ state: VideoEditorState) throws -> UUID {
    guard let id = lookup(.zoom, reference), state.zoomSegments.contains(where: { $0.id == id }) else {
      throw VideoEditorAgentToolError.notFound("zoom '\(reference)'")
    }
    return id
  }

  private func zoomCenter(_ raw: [Double]?) throws -> CGPoint? {
    guard let raw else { return nil }
    guard raw.count == 2, raw.allSatisfy(\.isFinite) else {
      throw VideoEditorAgentToolError.invalidArguments("center must be [x, y] from 0 to 1.")
    }
    // Accept percentages from models that think in them.
    let scale = raw.contains(where: { $0 > 1 }) && raw.allSatisfy { $0 <= 100 } ? 100.0 : 1.0
    return CGPoint(x: min(max(raw[0] / scale, 0), 1), y: min(max(raw[1] / scale, 0), 1))
  }

  private func zoomType(followMouse: Bool?, center: CGPoint?, state: VideoEditorState, at time: TimeInterval) throws -> ZoomType? {
    if followMouse == true {
      guard state.hasMouseTrackingData, state.sourceContext(atSequence: time)?.clip.isPrimary == true else {
        throw VideoEditorAgentToolError.invalidArguments(
          "This part of the video has no recorded mouse movement; give a center instead."
        )
      }
      return .auto
    }
    if followMouse == false || center != nil { return .manual }
    return nil
  }

  private func clampedZoomDuration(_ value: Double?) throws -> TimeInterval? {
    guard let value else { return nil }
    guard value.isFinite, value > 0 else { throw VideoEditorAgentToolError.invalidArguments("duration must be positive.") }
    return min(max(value, ZoomSegment.minDuration), ZoomSegment.maxDuration)
  }

  private func addZoom(_ args: AddZoomArguments, state: VideoEditorState) throws -> AgentToolResult {
    guard args.text == nil else {
      throw VideoEditorAgentToolError.unavailable("Finding the text is still working; call add_zoom again.")
    }
    guard let startArgument = args.start else {
      throw VideoEditorAgentToolError.invalidArguments("missing 'start' (or give text to zoom on).")
    }
    let start = try time(startArgument, state, name: "start")
    let length = try clampedZoomDuration(args.duration) ?? ZoomSegment.defaultDuration
    guard start <= duration(state) - ZoomSegment.minDuration else {
      throw VideoEditorAgentToolError.invalidArguments(
        "start must leave \(ZoomSegment.minDuration)s before the end (\(Self.clock(duration(state))))."
      )
    }
    let center = try zoomCenter(args.center)
    let type = try zoomType(followMouse: args.followMouse, center: center, state: state, at: start + min(length, 0.1))

    let id = state.addZoom(at: start + length / 2)
    state.updateZoom(
      id: id,
      startTime: start,
      duration: length,
      zoomLevel: args.level.map { CGFloat($0) },
      zoomCenter: center,
      zoomType: type
    )
    return zoomResult(id, state)
  }

  private func updateZoom(_ args: UpdateZoomArguments, state: VideoEditorState) throws -> AgentToolResult {
    let id = try zoomID(args.id, state)
    let current = state.zoomSegments.first { $0.id == id }!
    let start = try args.start.map { try time($0, state, name: "start") }
    let length = try clampedZoomDuration(args.duration)
    let center = try zoomCenter(args.center)
    let type = try zoomType(followMouse: args.followMouse, center: center, state: state, at: start ?? current.startTime)
    guard start != nil || length != nil || args.level != nil || center != nil || type != nil || args.enabled != nil else {
      throw VideoEditorAgentToolError.invalidArguments("Give at least one thing to change.")
    }
    state.updateZoom(
      id: id,
      startTime: start,
      duration: length,
      zoomLevel: args.level.map { CGFloat($0) },
      zoomCenter: center,
      zoomType: type,
      isEnabled: args.enabled
    )
    return zoomResult(id, state)
  }

  private func zoomResult(_ id: UUID, _ state: VideoEditorState) -> AgentToolResult {
    .success(zoomPayload(id, state))
  }

  private func zoomPayload(_ id: UUID, _ state: VideoEditorState) -> [String: Any] {
    guard let segment = state.zoomSegments.first(where: { $0.id == id }) else { return [:] }
    var payload: [String: Any] = [
      "id": reference(.zoom, for: id),
      "start": Self.round(segment.startTime),
      "end": Self.round(segment.endTime),
      "level": Self.round(Double(segment.zoomLevel)),
      "follow_mouse": segment.zoomType == .auto,
    ]
    if segment.zoomType != .auto {
      payload["center"] = [Self.round(segment.zoomCenter.x), Self.round(segment.zoomCenter.y)]
    }
    if let note = zoomCameraNote(segment, state) { payload["note"] = note }
    return payload
  }

  private func removeZooms(_ args: IDsArguments, state: VideoEditorState) throws -> AgentToolResult {
    let cleaned = args.ids
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !cleaned.isEmpty else { throw VideoEditorAgentToolError.invalidArguments("ids is empty.") }
    let ids: [UUID]
    if cleaned.contains(where: { $0.lowercased() == "all" }) {
      ids = state.zoomSegments.map(\.id)
    } else {
      ids = try cleaned.map { try zoomID($0, state) }
    }
    let removed = ids.map { reference(.zoom, for: $0) }
    for id in ids { state.removeZoom(id: id) }
    return .success(["removed": removed])
  }

  // MARK: - Speed

  private func speedID(_ reference: String, _ state: VideoEditorState) throws -> UUID {
    guard let id = lookup(.speed, reference), state.speedSegments.contains(where: { $0.id == id }) else {
      throw VideoEditorAgentToolError.notFound("speed '\(reference)'")
    }
    return id
  }

  private func parseRate(_ value: Double?) throws -> Double? {
    guard let value else { return nil }
    guard value.isFinite, value > 0 else {
      throw VideoEditorAgentToolError.invalidArguments("rate must be \(SpeedSegment.minRate)–\(SpeedSegment.maxRate).")
    }
    return SpeedSegment.clampRate(value)
  }

  /// Free room between enabled speed blocks, so a rejected add can say where it fits.
  private func freeSpeedGaps(_ state: VideoEditorState) -> String {
    var gaps: [String] = []
    var cursor = 0.0
    for segment in state.speedSegments.filter(\.isEnabled).sorted(by: { $0.startTime < $1.startTime }) {
      if segment.startTime - cursor >= SpeedSegment.minDuration {
        gaps.append("\(Self.clock(cursor))–\(Self.clock(segment.startTime))")
      }
      cursor = max(cursor, segment.endTime)
    }
    if duration(state) - cursor >= SpeedSegment.minDuration {
      gaps.append("\(Self.clock(cursor))–\(Self.clock(duration(state)))")
    }
    return gaps.isEmpty ? "none" : gaps.joined(separator: ", ")
  }

  private func addSpeed(_ args: AddSpeedArguments, state: VideoEditorState) throws -> AgentToolResult {
    let start = try time(args.start, state, name: "start")
    let end = try time(args.end, state, name: "end")
    guard end - start >= SpeedSegment.minDuration else {
      throw VideoEditorAgentToolError.invalidArguments("end must be at least \(SpeedSegment.minDuration)s after start.")
    }
    let rate = try parseRate(args.rate) ?? SpeedSegment.defaultRate
    if let overlap = state.speedSegments.first(where: { $0.isEnabled && $0.startTime < end && $0.endTime > start }) {
      throw VideoEditorAgentToolError.invalidArguments(
        "It overlaps \(reference(.speed, for: overlap.id)); change that block with update_speed, or use free room: \(freeSpeedGaps(state))."
      )
    }
    guard let id = state.addSpeed(range: start ... end, rate: rate) else {
      throw VideoEditorAgentToolError.invalidArguments("No room there. Free room: \(freeSpeedGaps(state)).")
    }
    return speedResult(id, state)
  }

  private func updateSpeed(_ args: UpdateSpeedArguments, state: VideoEditorState) throws -> AgentToolResult {
    let id = try speedID(args.id, state)
    let current = state.speedSegments.first { $0.id == id }!
    let start = try args.start.map { try time($0, state, name: "start") } ?? current.startTime
    let end = try args.end.map { try time($0, state, name: "end") } ?? current.endTime
    let rate = try parseRate(args.rate)
    guard args.start != nil || args.end != nil || rate != nil || args.enabled != nil else {
      throw VideoEditorAgentToolError.invalidArguments("Give at least one thing to change.")
    }
    if args.start != nil || args.end != nil {
      guard end - start >= SpeedSegment.minDuration else {
        throw VideoEditorAgentToolError.invalidArguments("end must be at least \(SpeedSegment.minDuration)s after start.")
      }
      if let overlap = state.speedSegments.first(where: {
        $0.id != id && $0.isEnabled && $0.startTime < end && $0.endTime > start
      }) {
        throw VideoEditorAgentToolError.invalidArguments(
          "It would overlap \(reference(.speed, for: overlap.id)). Free room: \(freeSpeedGaps(state))."
        )
      }
    }
    if let enabled = args.enabled, enabled != current.isEnabled {
      if enabled, let overlap = state.speedSegments.first(where: {
        $0.id != id && $0.isEnabled && $0.startTime < end && $0.endTime > start
      }) {
        throw VideoEditorAgentToolError.invalidArguments(
          "Turning it on would overlap \(reference(.speed, for: overlap.id)); move one of them first."
        )
      }
      state.toggleSpeedEnabled(id: id)
    }
    state.updateSpeed(
      id: id,
      rate: rate,
      startTime: args.start != nil || args.end != nil ? start : nil,
      duration: args.start != nil || args.end != nil ? end - start : nil
    )
    return speedResult(id, state)
  }

  private func speedResult(_ id: UUID, _ state: VideoEditorState) -> AgentToolResult {
    guard let segment = state.speedSegments.first(where: { $0.id == id }) else { return .success([:]) }
    return .success([
      "id": reference(.speed, for: id),
      "start": Self.round(segment.startTime),
      "end": Self.round(segment.endTime),
      "rate": Self.round(segment.rate),
      "output_duration": Self.round(CMTimeGetSeconds(state.effectiveOutputDuration)),
    ])
  }

  private func removeSpeeds(_ args: IDsArguments, state: VideoEditorState) throws -> AgentToolResult {
    let cleaned = args.ids
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !cleaned.isEmpty else { throw VideoEditorAgentToolError.invalidArguments("ids is empty.") }
    let ids: [UUID]
    if cleaned.contains(where: { $0.lowercased() == "all" }) {
      ids = state.speedSegments.map(\.id)
    } else {
      ids = try cleaned.map { try speedID($0, state) }
    }
    let removed = ids.map { reference(.speed, for: $0) }
    for id in ids { state.removeSpeed(id: id) }
    return .success(["removed": removed])
  }

  // MARK: - Frame & audio

  private func setBackground(_ args: BackgroundArguments, state: VideoEditorState) throws -> AgentToolResult {
    let style = try args.style.map(Self.parseBackground)
    let alignment: ImageAlignment? = try args.alignment.map {
      guard let parsed = ImageAlignment(rawValue: $0) else {
        throw VideoEditorAgentToolError.invalidArguments(
          "alignment must be one of \(VideoEditorAgentToolCatalog.alignments.joined(separator: ", "))."
        )
      }
      return parsed
    }
    let aspect = try args.aspectRatio.map(Self.parseAspectRatio)
    guard style != nil || args.padding != nil || args.shadow != nil || args.cornerRadius != nil
      || alignment != nil || aspect != nil else {
      throw VideoEditorAgentToolError.invalidArguments("Give at least one setting to change.")
    }

    var settings = state.frameSettings
    if let style {
      settings.style = style
      // Same as picking a background in the panel: a framed video needs room to show it.
      if style != .none, args.padding == nil, settings.padding <= 0 { settings.padding = 24 }
    }
    if let padding = args.padding { settings.padding = CGFloat(min(max(padding, 0), 300)) }
    if let shadow = args.shadow { settings.shadowIntensity = CGFloat(min(max(shadow, 0), 1)) }
    if let radius = args.cornerRadius { settings.cornerRadius = CGFloat(min(max(radius, 0), 60)) }
    if let alignment { settings.alignment = alignment }
    if let aspect { settings.aspectRatio = aspect }
    state.setFrameSettings(settings)
    return .success([:])
  }

  private func setAudio(_ args: AudioArguments, state: VideoEditorState) throws -> AgentToolResult {
    guard args.muted != nil || args.volume != nil else {
      throw VideoEditorAgentToolError.invalidArguments("Give muted, volume or both.")
    }
    guard !state.audioTrackRoles.isEmpty else {
      throw VideoEditorAgentToolError.unavailable("This video has no audio.")
    }
    var settings = state.exportSettings
    if args.muted == true {
      settings.audioMode = .mute
    } else {
      if args.muted == false, settings.audioMode == .mute { settings.audioMode = .keep }
      if let volume = args.volume {
        guard volume.isFinite, volume >= 0 else {
          throw VideoEditorAgentToolError.invalidArguments("volume is a percent, 0–200.")
        }
        let roles = try targetRoles(args.track ?? "all", state)
        // Custom volume: start from what the user hears now, then change the chosen tracks.
        if settings.audioMode != .custom {
          for role in state.audioTrackRoles {
            settings.setAudioVolume(settings.effectiveVolume(for: role), for: role)
          }
          settings.audioMode = .custom
        }
        for role in roles {
          settings.setAudioVolume(Float(min(volume, 200) / 100), for: role)
        }
      }
    }
    state.updateExportSettingsRecordingUndo(settings)
    let tracks = state.audioTrackRoles.map {
      ["track": Self.trackName($0), "volume": Int((state.exportSettings.effectiveVolume(for: $0) * 100).rounded())] as [String: Any]
    }
    return .success(["muted": state.exportSettings.audioMode == .mute, "tracks": tracks])
  }

  private func targetRoles(_ raw: String, _ state: VideoEditorState) throws -> [VideoEditorAudioTrackRole] {
    switch raw.lowercased() {
    case "all":
      return state.audioTrackRoles
    case "system":
      guard state.audioTrackRoles.contains(.systemAudio) else {
        throw VideoEditorAgentToolError.invalidArguments("This video has no separate system audio; use track all.")
      }
      return [.systemAudio]
    case "microphone", "mic":
      guard state.audioTrackRoles.contains(.microphone) else {
        throw VideoEditorAgentToolError.invalidArguments("This video has no separate microphone audio; use track all.")
      }
      return [.microphone]
    default:
      throw VideoEditorAgentToolError.invalidArguments("track must be all, system or microphone.")
    }
  }

  // MARK: - Activity

  private func activity(_ state: VideoEditorState) throws -> VideoEditorActivity {
    guard let activity = analyzer.cachedActivity(for: state) else {
      throw VideoEditorAgentToolError.unavailable("The recording is still being analyzed. Call the tool again.")
    }
    return activity
  }

  /// The part of the timeline a tool looks at: start…end, or all of it.
  private func window(
    _ start: VideoEditorAgentTime?,
    _ end: VideoEditorAgentTime?,
    _ state: VideoEditorState
  ) throws -> ClosedRange<TimeInterval> {
    let lower = try start.map { try time($0, state, name: "start") } ?? 0
    let upper = try end.map { try time($0, state, name: "end") } ?? duration(state)
    guard upper > lower else { throw VideoEditorAgentToolError.invalidArguments("end must be after start.") }
    return lower ... upper
  }

  private func timeline(_ ranges: [ClosedRange<TimeInterval>], _ state: VideoEditorState) -> [ClosedRange<TimeInterval>] {
    VideoEditorAgentAnalyzer.timelineSpans(ranges, placements: state.placements)
  }

  private func clipped(
    _ ranges: [ClosedRange<TimeInterval>],
    to window: ClosedRange<TimeInterval>,
    minDuration: TimeInterval = VideoEditorAgentAnalyzer.minimumSpan
  ) -> [ClosedRange<TimeInterval>] {
    VideoEditorAgentAnalyzer.intersect(ranges, [window], minDuration: minDuration)
  }

  private func getActivity(_ args: RangeArguments, state: VideoEditorState) throws -> AgentToolResult {
    let activity = try activity(state)
    let window = try window(args.start, args.end, state)

    var spans: [(kind: String, range: ClosedRange<TimeInterval>, area: CGRect?)] = []
    if activity.audio != .none {
      let silences = clipped(timeline(activity.silences, state), to: window)
      let playing = clipped(VideoEditorAgentAnalyzer.playingSpans(state.placements), to: window)
      let speech = VideoEditorAgentAnalyzer.subtract(playing, silences)
        .filter { $0.upperBound - $0.lowerBound >= VideoEditorAgentAnalyzer.minimumSpan }
      spans += silences.map { ("silence", $0, nil) } + speech.map { ("speech", $0, nil) }
    }
    if activity.hasMouseData {
      spans += clipped(idleWithoutClicks(timeline(activity.idle, state), state), to: window).map { ("idle", $0, nil) }
      for motion in activity.motion {
        for range in clipped(timeline([motion.range], state), to: window) {
          spans.append(("motion", range, motion.bounds))
        }
      }
    }
    // Long recordings: keep the longest spans so the answer stays short.
    var omitted = 0
    if spans.count > Self.maximumActivitySpans {
      omitted = spans.count - Self.maximumActivitySpans
      spans = Array(spans.sorted { $0.range.upperBound - $0.range.lowerBound > $1.range.upperBound - $1.range.lowerBound }
        .prefix(Self.maximumActivitySpans))
    }
    spans.sort { $0.range.lowerBound < $1.range.lowerBound }

    var payload: [String: Any] = [
      "audio": activity.audio.rawValue,
      "mouse": activity.hasMouseData,
      "spans": spans.map { span -> [String: Any] in
        var item: [String: Any] = [
          "kind": span.kind, "start": Self.round(span.range.lowerBound), "end": Self.round(span.range.upperBound),
        ]
        if let area = span.area {
          item["area"] = [area.minX, area.minY, area.width, area.height].map { Self.round($0) }
        }
        return item
      },
    ]
    if omitted > 0 { payload["omitted_short_spans"] = omitted }
    if let clicks = clickActivityPayload(state, window: window) { payload.merge(clicks) { current, _ in current } }
    if state.hasInsertedClips { payload["note"] = "Inserted videos are not analyzed." }
    if activity.audio == .none, !activity.hasMouseData {
      payload["note"] = "This video has no audio and no recorded cursor, so there is no activity to report."
    }
    return .success(payload)
  }

  /// How many more edits this run may make.
  private var remainingChanges: Int { max(0, Self.maximumChangesPerRun - changeCount) }

  private func removeSilences(_ args: SilenceArguments, state: VideoEditorState) throws -> AgentToolResult {
    let activity = try activity(state)
    guard activity.audio != .none else {
      throw VideoEditorAgentToolError.unavailable("This video has no audio, so there are no silences to find.")
    }
    let window = try window(args.start, args.end, state)
    let minDuration = min(max(args.minDuration ?? Self.silenceDefaults.minDuration, VideoEditorAgentAnalyzer.minimumSpan), 600)
    let padding = min(max(args.padding ?? Self.silenceDefaults.padding, 0), 2)
    let total = duration(state)

    let silences = clipped(timeline(activity.silences, state), to: window)
      .filter { $0.upperBound - $0.lowerBound >= minDuration - 1e-9 }
    // Keep a little pause next to speech; none at the very start or end of the video.
    var cuts = silences.compactMap { range -> ClosedRange<TimeInterval>? in
      let start = range.lowerBound <= 0.05 ? 0 : range.lowerBound + padding
      let end = range.upperBound >= total - 0.05 ? total : range.upperBound - padding
      return end - start >= TimelineClip.minDuration ? start ... end : nil
    }
    let playing = VideoEditorAgentAnalyzer.playingSpans(state.placements).reduce(0) { $0 + $1.upperBound - $1.lowerBound }
    let cutLength = cuts.reduce(0) { $0 + $1.upperBound - $1.lowerBound }
    guard cutLength < playing - TimelineClip.minDuration else {
      throw VideoEditorAgentToolError.unavailable("The audio is silent throughout; cutting the silences would leave nothing.")
    }
    var skipped = 0
    if cuts.count > remainingChanges {
      guard remainingChanges > 0 else { throw VideoEditorAgentToolError.limitReached(Self.maximumChangesPerRun) }
      skipped = cuts.count - remainingChanges
      cuts = Array(cuts.sorted { $0.upperBound - $0.lowerBound > $1.upperBound - $1.lowerBound }.prefix(remainingChanges))
    }

    // Latest first: the times of the pauses still to cut don't move.
    var removedSeconds = 0.0
    var made: [ClosedRange<TimeInterval>] = []
    for cut in cuts.sorted(by: { $0.lowerBound > $1.lowerBound }) {
      guard let removed = state.cutTimeline(range: cut) else { continue }
      _ = shiftEffects(after: removed, state: state)
      removedSeconds += removed.reduce(0) { $0 + $1.upperBound - $1.lowerBound }
      made.append(cut)
      changeCount += 1
    }
    var payload: [String: Any] = [
      "cuts": made.count,
      "removed_seconds": Self.round(removedSeconds),
      "new_duration": Self.round(duration(state)),
      "removed": made.reversed().prefix(30).map { [Self.round($0.lowerBound), Self.round($0.upperBound)] },
    ]
    if made.isEmpty { payload["note"] = "No pauses of at least \(Self.round(minDuration))s." }
    if skipped > 0 { payload["skipped"] = skipped }
    return .success(payload)
  }

  private func speedUpIdle(_ args: IdleArguments, state: VideoEditorState) throws -> AgentToolResult {
    let activity = try activity(state)
    guard activity.hasMouseData else {
      throw VideoEditorAgentToolError.unavailable(
        "This video has no recorded cursor (only Snapzy screen recordings do), so idle parts can't be found. "
          + "Use get_activity for silences, or ask the user which parts to speed up."
      )
    }
    let window = try window(args.start, args.end, state)
    let rate = try parseRate(args.rate) ?? Self.idleDefaults.rate
    let minDuration = max(args.minDuration ?? Self.idleDefaults.minDuration, SpeedSegment.minDuration)
    let padding = Self.idleDefaults.padding

    let idle = clipped(idleWithoutClicks(timeline(activity.idle, state), state), to: window)
      .filter { $0.upperBound - $0.lowerBound >= minDuration - 1e-9 }
      .map { ($0.lowerBound + padding) ... max($0.lowerBound + padding, $0.upperBound - padding) }
    let taken = state.speedSegments.filter(\.isEnabled).map { $0.startTime ... $0.endTime }
    var spans = VideoEditorAgentAnalyzer.subtract(idle, taken)
      .filter { $0.upperBound - $0.lowerBound >= SpeedSegment.minDuration }
    var skipped = 0
    if spans.count > remainingChanges {
      guard remainingChanges > 0 else { throw VideoEditorAgentToolError.limitReached(Self.maximumChangesPerRun) }
      skipped = spans.count - remainingChanges
      spans = Array(spans.sorted { $0.upperBound - $0.lowerBound > $1.upperBound - $1.lowerBound }.prefix(remainingChanges))
        .sorted { $0.lowerBound < $1.lowerBound }
    }

    var added: [[String: Any]] = []
    for span in spans {
      guard let id = state.addSpeed(range: span, rate: rate),
            let segment = state.speedSegments.first(where: { $0.id == id }) else { continue }
      changeCount += 1
      added.append([
        "id": reference(.speed, for: id),
        "start": Self.round(segment.startTime),
        "end": Self.round(segment.endTime),
      ])
    }
    var payload: [String: Any] = [
      "added": added,
      "rate": Self.round(rate),
      "output_duration": Self.round(CMTimeGetSeconds(state.effectiveOutputDuration)),
    ]
    if added.isEmpty { payload["note"] = "No idle stretches of at least \(Self.round(minDuration))s outside existing speed blocks." }
    if skipped > 0 { payload["skipped"] = skipped }
    return .success(payload)
  }

  private func autoZoomActivity(_ args: AutoZoomArguments, state: VideoEditorState) throws -> AgentToolResult {
    let activity = try activity(state)
    let source = (args.source ?? "motion").lowercased()
    guard source == "motion" || source == "clicks" else {
      throw VideoEditorAgentToolError.invalidArguments("source must be motion or clicks.")
    }
    let window = try window(args.start, args.end, state)
    let level = min(max(args.level ?? Double(ZoomSegment.defaultZoomLevel), Double(ZoomSegment.minZoomLevel)), Double(ZoomSegment.maxZoomLevel))
    let maxZooms = min(max(args.maxZooms ?? Self.autoZoomDefaults.maxZooms, 1), 30)
    let total = duration(state)

    var merged: [(range: ClosedRange<TimeInterval>, weight: TimeInterval, center: CGPoint?)] = []
    if source == "clicks" {
      guard !recordedClickDowns(state).isEmpty else {
        throw VideoEditorAgentToolError.unavailable(
          "This video has no recorded clicks (only Studio recordings record them). Use source motion, or add_zoom with a center."
        )
      }
      // Each burst of clicks → one zoom held on where they land; bursts already sit apart.
      merged = clickZoomCandidates(state, window: window, total: total)
    } else {
      guard activity.hasMouseData else {
        throw VideoEditorAgentToolError.unavailable(
          "This video has no recorded cursor (only Snapzy screen recordings do). Add zooms with add_zoom and a center instead."
        )
      }
      // Work in a small area for a while → one zoom, with a short lead-in and hold.
      var candidates: [(range: ClosedRange<TimeInterval>, weight: TimeInterval)] = []
      for motion in activity.motion
      where motion.bounds.width <= Self.autoZoomDefaults.maxArea && motion.bounds.height <= Self.autoZoomDefaults.maxArea {
        for range in clipped(timeline([motion.range], state), to: window)
        where range.upperBound - range.lowerBound >= Self.autoZoomDefaults.minActivity {
          let start = max(0, range.lowerBound - 0.3)
          let end = min(total, range.upperBound + 0.5)
          candidates.append((start ... end, range.upperBound - range.lowerBound))
        }
      }
      // Close bursts become one zoom rather than a zoom pumping in and out.
      candidates.sort { $0.range.lowerBound < $1.range.lowerBound }
      for candidate in candidates {
        if let last = merged.last, candidate.range.lowerBound - last.range.upperBound < 1.0,
           candidate.range.upperBound - last.range.lowerBound <= ZoomSegment.maxDuration {
          merged[merged.count - 1] = (
            last.range.lowerBound ... max(last.range.upperBound, candidate.range.upperBound), last.weight + candidate.weight, nil
          )
        } else {
          merged.append((candidate.range, candidate.weight, nil))
        }
      }
    }
    let existing = state.zoomSegments.map { $0.startTime ... $0.endTime }
    var chosen = merged.filter { candidate in
      !existing.contains { $0.lowerBound < candidate.range.upperBound && $0.upperBound > candidate.range.lowerBound }
    }
    // Click zooms are held a moment after the last click; never let two of them overlap.
    if source == "clicks" {
      var kept: [(range: ClosedRange<TimeInterval>, weight: TimeInterval, center: CGPoint?)] = []
      for candidate in chosen {
        if let last = kept.last, candidate.range.lowerBound < last.range.upperBound {
          kept[kept.count - 1].range = last.range.lowerBound ... max(last.range.lowerBound + ZoomSegment.minDuration, candidate.range.lowerBound)
        }
        kept.append(candidate)
      }
      chosen = kept
    }
    let limit = min(maxZooms, remainingChanges)
    guard limit > 0 || chosen.isEmpty else { throw VideoEditorAgentToolError.limitReached(Self.maximumChangesPerRun) }
    if chosen.count > limit {
      chosen = Array(chosen.sorted { $0.weight > $1.weight }.prefix(limit)).sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    var added: [[String: Any]] = []
    for candidate in chosen {
      let length = min(max(candidate.range.upperBound - candidate.range.lowerBound, ZoomSegment.minDuration), ZoomSegment.maxDuration)
      let start = min(candidate.range.lowerBound, max(0, total - length))
      let id = state.addZoom(at: start + length / 2)
      state.updateZoom(
        id: id, startTime: start, duration: length, zoomLevel: CGFloat(level),
        zoomCenter: candidate.center, zoomType: candidate.center == nil ? .auto : .manual
      )
      guard let segment = state.zoomSegments.first(where: { $0.id == id }) else { continue }
      changeCount += 1
      var item: [String: Any] = [
        "id": reference(.zoom, for: id),
        "start": Self.round(segment.startTime),
        "end": Self.round(segment.endTime),
      ]
      if candidate.center != nil { item["center"] = [Self.round(segment.zoomCenter.x), Self.round(segment.zoomCenter.y)] }
      if let note = zoomCameraNote(segment, state) { item["note"] = note }
      added.append(item)
    }
    var payload: [String: Any] = ["added": added, "level": Self.round(level), "source": source]
    if added.isEmpty {
      payload["note"] = source == "clicks" ? "No clicks outside existing zooms." : "No focused cursor work outside existing zooms."
    }
    return .success(payload)
  }

  // MARK: - Frames, on-screen text & speech

  static let maximumFrameLines = 40
  static let maximumAppearances = 10
  /// Characters of transcript one call returns; the rest is offered through `next_start`.
  static let maximumTranscriptCharacters = 6_000

  /// Tools that wait on frames or speech. nil = run the synchronous path (add_zoom without text).
  private func performMedia(_ tool: VideoEditorAgentToolName, arguments: Data) async throws -> AgentToolResult? {
    switch tool {
    case .getFrame:
      let state = try readyState()
      return try await getFrame(decode(TimeArguments.self, arguments), state: state)
    case .findOnScreen:
      let state = try readyState()
      return try await findOnScreen(decode(FindArguments.self, arguments), state: state)
    case .getTranscript:
      let state = try readyState()
      return try await getTranscript(decode(TranscriptArguments.self, arguments), state: state)
    case .generateCaptions:
      let state = try readyState()
      guard changeCount < Self.maximumChangesPerRun else {
        throw VideoEditorAgentToolError.limitReached(Self.maximumChangesPerRun)
      }
      return try await generateCaptions(decode(VideoEditorAgentCaptionArguments.self, arguments), state: state)
    case .translateCaptions:
      let state = try readyState()
      guard changeCount < Self.maximumChangesPerRun else {
        throw VideoEditorAgentToolError.limitReached(Self.maximumChangesPerRun)
      }
      return try await translateCaptions(decode(VideoEditorAgentTranslateCaptionArguments.self, arguments), state: state)
    case .addZoom:
      let args = try decode(AddZoomArguments.self, arguments)
      guard let raw = args.text else { return nil }
      let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { throw VideoEditorAgentToolError.invalidArguments("text is empty.") }
      let state = try readyState()
      guard changeCount < Self.maximumChangesPerRun else {
        throw VideoEditorAgentToolError.limitReached(Self.maximumChangesPerRun)
      }
      return try await addZoom(onText: text, args, state: state)
    default:
      return nil
    }
  }

  private func getFrame(_ args: TimeArguments, state: VideoEditorState) async throws -> AgentToolResult {
    let t = try time(args.time, state, name: "time")
    let frame = try await analyzer.vision.frame(at: t, in: state)
    try Task.checkCancellation()
    // Same OCR size and cache as find_on_screen, so the two agree.
    let lines = (try? await analyzer.vision.text(at: t, in: state)) ?? []
    let image = await AgentToolImage.jpeg(from: frame)
    try Task.checkCancellation()

    // Top to bottom, left to right: the order people read a screen in.
    let sorted = lines.sorted { abs($0.box.minY - $1.box.minY) > 0.01 ? $0.box.minY < $1.box.minY : $0.box.minX < $1.box.minX }
    var payload: [String: Any] = [
      "time": Self.round(t),
      "size": [Int(state.naturalSize.width.rounded()), Int(state.naturalSize.height.rounded())],
      "text": sorted.prefix(Self.maximumFrameLines).map { ["text": $0.text, "box": Self.box($0.box)] as [String: Any] },
    ]
    if let clip = state.sourceContext(atSequence: t)?.clip { payload["clip"] = reference(.clip, for: clip.id) }
    if sorted.count > Self.maximumFrameLines { payload["more_text_lines"] = sorted.count - Self.maximumFrameLines }
    if lines.isEmpty { payload["note"] = "No text found on this frame." }
    if image == nil { payload["image"] = "omitted (too large to send); use the text." }
    return AgentToolResult.success(payload).with(image: image)
  }

  private func findOnScreen(_ args: FindArguments, state: VideoEditorState) async throws -> AgentToolResult {
    let text = args.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw VideoEditorAgentToolError.invalidArguments("text is empty.") }
    let window = try window(args.start, args.end, state)
    let search = try await analyzer.vision.find(text, in: window, state: state)
    try Task.checkCancellation()

    var payload: [String: Any] = [
      "text": text,
      "matches": search.appearances.prefix(Self.maximumAppearances).map(Self.appearancePayload),
      "frames_read": search.samples,
      "seconds_between_frames": Self.round(search.step),
    ]
    if search.appearances.count > Self.maximumAppearances {
      payload["more_matches"] = search.appearances.count - Self.maximumAppearances
    }
    if search.appearances.isEmpty {
      payload["note"] = "Not found on screen. Text that is on screen often: "
        + search.commonLines.prefix(12).map { "\"\($0)\"" }.joined(separator: ", ")
    }
    return .success(payload)
  }

  private static func appearancePayload(_ appearance: VideoEditorTextAppearance) -> [String: Any] {
    [
      "start": round(appearance.start),
      "end": round(appearance.end),
      "line": appearance.line,
      "box": box(appearance.box),
      "center": [round(appearance.box.midX), round(appearance.box.midY)],
    ]
  }

  private func addZoom(onText text: String, _ args: AddZoomArguments, state: VideoEditorState) async throws -> AgentToolResult {
    let from = try args.start.map { try time($0, state, name: "start") } ?? 0
    guard from < duration(state) - ZoomSegment.minDuration else {
      throw VideoEditorAgentToolError.invalidArguments(
        "start must leave \(ZoomSegment.minDuration)s before the end (\(Self.clock(duration(state))))."
      )
    }
    let search = try await analyzer.vision.find(text, in: from ... duration(state), state: state)
    try Task.checkCancellation()
    guard let appearance = search.appearances.first else {
      let seen = search.commonLines.prefix(12).map { "\"\($0)\"" }.joined(separator: ", ")
      throw VideoEditorAgentToolError.notFound(
        "'\(text)' on screen after \(Self.clock(from)). Text that is on screen often: \(seen.isEmpty ? "none" : seen). "
          + "Try other words, or give start and center"
      )
    }
    var resolved = args
    resolved.text = nil
    resolved.start = VideoEditorAgentTime(seconds: max(from, appearance.start))
    resolved.center = [Double(appearance.box.midX), Double(appearance.box.midY)]
    resolved.followMouse = false
    let added = try addZoom(resolved, state: state)
    guard !added.isError, let data = added.text.data(using: .utf8),
          var payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return added }
    payload.removeValue(forKey: "ok")
    payload["found"] = Self.appearancePayload(appearance)
    if search.appearances.count > 1 { payload["other_matches"] = search.appearances.count - 1 }
    return .success(payload)
  }

  private func getTranscript(_ args: TranscriptArguments, state: VideoEditorState) async throws -> AgentToolResult {
    let window = try window(args.start, args.end, state)
    let locale = Self.speechLocale(args.language)
    let phrases = try await analyzer.transcriber.phrases(for: state, locale: locale)
    try Task.checkCancellation()

    // Through the clips: cut speech is gone, reordered speech moves with its clip.
    var mapped: [(range: ClosedRange<TimeInterval>, text: String)] = []
    for phrase in phrases {
      let pieces = VideoEditorAgentAnalyzer.timelineSpans([phrase.range], placements: state.placements)
      guard let first = pieces.first, let last = pieces.last,
            first.lowerBound < window.upperBound, last.upperBound > window.lowerBound else { continue }
      mapped.append((first.lowerBound ... last.upperBound, phrase.text))
    }
    // Timeline order before truncating, so next_start never skips a phrase.
    mapped.sort { $0.range.lowerBound < $1.range.lowerBound }
    var items: [[String: Any]] = []
    var characters = 0
    var nextStart: TimeInterval?
    for phrase in mapped {
      if characters + phrase.text.count > Self.maximumTranscriptCharacters, !items.isEmpty {
        nextStart = phrase.range.lowerBound
        break
      }
      characters += phrase.text.count
      items.append(["start": Self.round(phrase.range.lowerBound), "end": Self.round(phrase.range.upperBound), "text": phrase.text])
    }

    var payload: [String: Any] = ["language": locale.identifier, "phrases": items]
    if let nextStart {
      payload["truncated"] = true
      payload["next_start"] = Self.round(nextStart)
    }
    if items.isEmpty { payload["note"] = "No speech recognized here." }
    if state.hasInsertedClips { payload["inserted_videos"] = "Inserted videos are not transcribed." }
    return .success(payload)
  }

  /// "vi_VN", "vi-VN" or nothing (the Mac's language, without extensions like @rg=…).
  nonisolated static func speechLocale(_ raw: String?) -> Locale {
    if let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty {
      return Locale(identifier: raw.replacingOccurrences(of: "_", with: "-"))
    }
    let current = Locale.current
    guard let language = current.language.languageCode?.identifier else { return current }
    return Locale(identifier: current.region.map { "\(language)-\($0.identifier)" } ?? language)
  }

  private static func box(_ rect: CGRect) -> [Double] {
    [rect.minX, rect.minY, rect.width, rect.height].map { round($0) }
  }

  // MARK: - Parsing & description

  nonisolated static func parseBackground(_ raw: String) throws -> BackgroundStyle {
    do {
      return try AnnotateAgentToolbox.parseBackground(raw)
    } catch {
      throw VideoEditorAgentToolError.invalidArguments(
        "style '\(raw)' — use none, a gradient (\(GradientPreset.allCases.map(\.rawValue).joined(separator: ", "))) or a color."
      )
    }
  }

  nonisolated static func parseAspectRatio(_ raw: String) throws -> AspectRatioOption {
    let key = raw.lowercased().trimmingCharacters(in: .whitespaces)
    switch key {
    case "original", "auto": return .auto
    case "free": return .free
    default:
      if let option = AspectRatioOption.allCases.first(where: { $0.rawValue == key.replacingOccurrences(of: "x", with: ":") }) {
        return option
      }
      throw VideoEditorAgentToolError.invalidArguments(
        "aspect_ratio must be one of \(VideoEditorAgentToolCatalog.aspectRatios.joined(separator: ", "))."
      )
    }
  }

  private static func describe(_ style: BackgroundStyle) -> String {
    switch style {
    case .none: "none"
    case .gradient(let preset): preset.rawValue
    case .solidColor(let color): AnnotateAgentColor.describe(color)
    case .wallpaper: "wallpaper"
    case .blurred: "blurred wallpaper"
    }
  }

  private static func describe(_ ratio: AspectRatioOption) -> String {
    switch ratio {
    case .auto: "original"
    case .free: "free"
    default: ratio.rawValue
    }
  }

  private static func trackName(_ role: VideoEditorAudioTrackRole) -> String {
    switch role {
    case .mixed: "all"
    case .systemAudio: "system"
    case .microphone: "microphone"
    case .additional(let index): "track \(index)"
    }
  }

  /// Two decimals: enough for frame-level edits, short for the model.
  nonisolated static func round(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return (value * 100).rounded() / 100
  }

  nonisolated static func round(_ value: CGFloat) -> Double {
    round(Double(value))
  }

  /// `m:ss.s` for messages.
  nonisolated static func clock(_ seconds: TimeInterval) -> String {
    let value = max(0, seconds.isFinite ? seconds : 0)
    let minutes = Int(value / 60)
    let rest = value - Double(minutes * 60)
    return String(format: "%d:%04.1f", minutes, rest)
  }

  nonisolated private static func describe(_ error: DecodingError) -> String {
    switch error {
    case .keyNotFound(let key, _):
      return "missing '\(key.stringValue)'."
    case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
      let path = context.codingPath.map(\.stringValue).joined(separator: ".")
      return path.isEmpty ? context.debugDescription : "'\(path)': \(context.debugDescription)"
    @unknown default:
      return "could not read the arguments."
    }
  }
}


// MARK: - Arguments

/// Seconds on the timeline, from a number or "m:ss.s" / "h:mm:ss" / "12s" text.
nonisolated struct VideoEditorAgentTime: Decodable, Equatable {
  let seconds: TimeInterval

  init(seconds: TimeInterval) {
    self.seconds = seconds
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value: Double?
    if let number = try? container.decode(Double.self) {
      value = number
    } else if let text = try? container.decode(String.self) {
      value = Self.parse(text)
    } else {
      value = nil
    }
    guard let value, value.isFinite, value >= 0 else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "use seconds (like 12.5) or \"m:ss.s\" (like \"1:05.5\")."
      )
    }
    self.seconds = value
  }

  static func parse(_ raw: String) -> Double? {
    var text = raw.trimmingCharacters(in: .whitespaces).lowercased()
    if text.hasSuffix("s") { text.removeLast() }
    let parts = text.split(separator: ":", omittingEmptySubsequences: false)
    guard (1 ... 3).contains(parts.count) else { return nil }
    var total = 0.0
    for (index, part) in parts.enumerated() {
      guard let value = Double(part.trimmingCharacters(in: .whitespaces)), value >= 0 else { return nil }
      // Minutes and seconds after the first field stay below 60.
      if index > 0, value >= 60 { return nil }
      total = total * 60 + value
    }
    return total
  }
}

private struct TimeArguments: Decodable {
  let time: VideoEditorAgentTime
}

private struct CutArguments: Decodable {
  let start: VideoEditorAgentTime
  let end: VideoEditorAgentTime
  let shiftEffects: Bool?
}

private struct TrimArguments: Decodable {
  let clip: String
  let start: VideoEditorAgentTime?
  let end: VideoEditorAgentTime?
}

private struct ClipArguments: Decodable {
  let clip: String
}

private struct MoveArguments: Decodable {
  let clip: String
  let position: Int
}

private struct AddZoomArguments: Decodable {
  var start: VideoEditorAgentTime?
  var duration: Double?
  var level: Double?
  var center: [Double]?
  var followMouse: Bool?
  /// Words on screen to zoom on; resolved to start + center before the zoom is added.
  var text: String?
}

private struct FindArguments: Decodable {
  let text: String
  let start: VideoEditorAgentTime?
  let end: VideoEditorAgentTime?
}

private struct TranscriptArguments: Decodable {
  let start: VideoEditorAgentTime?
  let end: VideoEditorAgentTime?
  let language: String?
}

private struct UpdateZoomArguments: Decodable {
  let id: String
  let start: VideoEditorAgentTime?
  let duration: Double?
  let level: Double?
  let center: [Double]?
  let followMouse: Bool?
  let enabled: Bool?
}

private struct IDsArguments: Decodable {
  let ids: [String]
}

private struct AddSpeedArguments: Decodable {
  let start: VideoEditorAgentTime
  let end: VideoEditorAgentTime
  let rate: Double
}

private struct UpdateSpeedArguments: Decodable {
  let id: String
  let start: VideoEditorAgentTime?
  let end: VideoEditorAgentTime?
  let rate: Double?
  let enabled: Bool?
}

private struct BackgroundArguments: Decodable {
  let style: String?
  let padding: Double?
  let shadow: Double?
  let cornerRadius: Double?
  let alignment: String?
  let aspectRatio: String?
}

private struct RangeArguments: Decodable {
  let start: VideoEditorAgentTime?
  let end: VideoEditorAgentTime?
}

private struct SilenceArguments: Decodable {
  let minDuration: Double?
  let padding: Double?
  let start: VideoEditorAgentTime?
  let end: VideoEditorAgentTime?
}

private struct IdleArguments: Decodable {
  let rate: Double?
  let minDuration: Double?
  let start: VideoEditorAgentTime?
  let end: VideoEditorAgentTime?
}

private struct AutoZoomArguments: Decodable {
  let source: String?
  let level: Double?
  let maxZooms: Int?
  let start: VideoEditorAgentTime?
  let end: VideoEditorAgentTime?
}

private struct AudioArguments: Decodable {
  let muted: Bool?
  let volume: Double?
  let track: String?
}
