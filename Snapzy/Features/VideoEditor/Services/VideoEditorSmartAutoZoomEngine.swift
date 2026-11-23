//
//  VideoEditorSmartAutoZoomEngine.swift
//  Snapzy
//
//  Action- and outcome-aware Smart Auto-Zoom v2 planner for Studio screen recordings.
//  Combines high-frequency mouse kinematics, click/drag/typing semantics, cursor
//  follow-through inference, 32×18 RGB connected-component visual outcome isolation,
//  and autonomous keyboard-triggered UI event detection.
//

import AVFoundation
import CoreGraphics
import Foundation

nonisolated enum SmartAutoZoomStyle: String, Codable, CaseIterable, Equatable, Sendable {
  case subtle
  case balanced
  case dynamic

  var baseZoom: CGFloat {
    switch self {
    case .subtle: 1.65
    case .balanced: 2.05
    case .dynamic: 2.45
    }
  }

  var detailZoom: CGFloat {
    switch self {
    case .subtle: 1.85
    case .balanced: 2.30
    case .dynamic: 2.75
    }
  }

  var contextZoom: CGFloat {
    switch self {
    case .subtle: 1.45
    case .balanced: 1.75
    case .dynamic: 2.05
    }
  }

  var minOutcomeZoom: CGFloat {
    switch self {
    case .subtle: 1.30
    case .balanced: 1.38
    case .dynamic: 1.52
    }
  }

  var readingBeat: TimeInterval {
    switch self {
    case .subtle: 1.10
    case .balanced: 0.92
    case .dynamic: 0.78
    }
  }

  var mergeGapThreshold: TimeInterval {
    switch self {
    case .subtle: 1.20
    case .balanced: 1.45
    case .dynamic: 1.65
    }
  }

  var maxChapterDuration: TimeInterval {
    26.0
  }
}

nonisolated enum VideoEditorSmartAutoZoomEngine {
  // MARK: - Domain Types

  enum ActionKind: Equatable, Sendable {
    case click
    case doubleClick
    case rightClick
    case drag
    case longPress
    case dwellFocus
    /// Localized UI appearance (e.g. command palette, dialog, sheet) triggered without a click (shortcut).
    case visualEvent
  }

  struct DetectedAction: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: ActionKind
    let startTime: TimeInterval
    let endTime: TimeInterval
    let focusPoint: CGPoint
    let endPoint: CGPoint
    let bounds: CGRect
    let waypoints: [(time: TimeInterval, point: CGPoint)]
    let anticipationLead: TimeInterval
    let cursorChangedBeforeClick: Bool
    /// Non-nil when cursor disappeared or stayed parked in active text entry after this action.
    let typingEndTime: TimeInterval?
    /// Non-nil when cursor hovered/explored nearby interactive targets immediately after click.
    let postActionExploreEndTime: TimeInterval?
    /// Inferred bounding box of nearby post-click cursor exploration (e.g. scanning a newly opened menu).
    let followThroughBounds: CGRect?
    /// True when cursor immediately zipped away after a single click without lingering (stray focus-click heuristic).
    let departedImmediately: Bool

    init(
      id: UUID,
      kind: ActionKind,
      startTime: TimeInterval,
      endTime: TimeInterval,
      focusPoint: CGPoint,
      endPoint: CGPoint,
      bounds: CGRect,
      waypoints: [(time: TimeInterval, point: CGPoint)],
      anticipationLead: TimeInterval,
      cursorChangedBeforeClick: Bool,
      typingEndTime: TimeInterval?,
      postActionExploreEndTime: TimeInterval?,
      followThroughBounds: CGRect? = nil,
      departedImmediately: Bool = false
    ) {
      self.id = id
      self.kind = kind
      self.startTime = startTime
      self.endTime = endTime
      self.focusPoint = focusPoint
      self.endPoint = endPoint
      self.bounds = bounds
      self.waypoints = waypoints
      self.anticipationLead = anticipationLead
      self.cursorChangedBeforeClick = cursorChangedBeforeClick
      self.typingEndTime = typingEndTime
      self.postActionExploreEndTime = postActionExploreEndTime
      self.followThroughBounds = followThroughBounds
      self.departedImmediately = departedImmediately
    }

    static func == (lhs: DetectedAction, rhs: DetectedAction) -> Bool {
      lhs.id == rhs.id
        && lhs.kind == rhs.kind
        && lhs.startTime == rhs.startTime
        && lhs.endTime == rhs.endTime
        && lhs.focusPoint == rhs.focusPoint
        && lhs.endPoint == rhs.endPoint
        && lhs.bounds == rhs.bounds
        && lhs.anticipationLead == rhs.anticipationLead
        && lhs.cursorChangedBeforeClick == rhs.cursorChangedBeforeClick
        && lhs.typingEndTime == rhs.typingEndTime
        && lhs.postActionExploreEndTime == rhs.postActionExploreEndTime
        && lhs.followThroughBounds == rhs.followThroughBounds
        && lhs.departedImmediately == rhs.departedImmediately
    }
  }

  enum VisualOutcomeKind: Equatable, Sendable {
    case none
    case localNearClick
    case localRemoteResult
    case fullScreenTransition
  }

  struct VisualOutcome: Equatable, Sendable {
    let kind: VisualOutcomeKind
    let settleTime: TimeInterval
    let changedCoverage: CGFloat
    let outcomeCentroid: CGPoint
    let outcomeBounds: CGRect
    /// True when post-action frames keep changing continuously (e.g. clicking Play on a video).
    let isSustainedMotion: Bool

    init(
      kind: VisualOutcomeKind,
      settleTime: TimeInterval,
      changedCoverage: CGFloat,
      outcomeCentroid: CGPoint,
      outcomeBounds: CGRect,
      isSustainedMotion: Bool = false
    ) {
      self.kind = kind
      self.settleTime = settleTime
      self.changedCoverage = changedCoverage
      self.outcomeCentroid = outcomeCentroid
      self.outcomeBounds = outcomeBounds
      self.isSustainedMotion = isSustainedMotion
    }

    static func none(at time: TimeInterval, point: CGPoint) -> VisualOutcome {
      VisualOutcome(
        kind: .none,
        settleTime: time,
        changedCoverage: 0,
        outcomeCentroid: point,
        outcomeBounds: CGRect(origin: point, size: .zero),
        isSustainedMotion: false
      )
    }
  }

  struct Plan: Equatable, Sendable {
    let segments: [ZoomSegment]
    let actionCount: Int
    let analyzedVisualOutcomes: Int

    static let empty = Plan(segments: [], actionCount: 0, analyzedVisualOutcomes: 0)
  }

  struct CanonicalSample: Equatable, Sendable {
    let time: TimeInterval
    let point: CGPoint
    let isInsideCapture: Bool
  }

  // MARK: - Public Entry Points

  /// Full async pipeline: extracts actions from metadata, inspects 32×18 RGB video grids for
  /// connected-component UI outcomes + unclicked shortcut events, and produces silky spring-ready
  /// non-overlapping Smart Auto-Zoom segments.
  static func generatePlan(
    from metadata: RecordingMetadata,
    asset: AVAsset? = nil,
    duration: TimeInterval? = nil,
    style: SmartAutoZoomStyle = .balanced,
    transitionDuration: TimeInterval = ZoomCalculator.defaultTransitionDuration
  ) async -> Plan {
    let resolvedDuration: TimeInterval
    if let duration, duration.isFinite, duration > 0 {
      resolvedDuration = duration
    } else if let asset, let loaded = try? await asset.load(.duration) {
      let seconds = CMTimeGetSeconds(loaded)
      resolvedDuration = seconds.isFinite && seconds > 0 ? seconds : inferredDuration(from: metadata)
    } else {
      resolvedDuration = inferredDuration(from: metadata)
    }

    guard resolvedDuration >= ZoomSegment.minDuration else { return .empty }
    var actions = detectActions(from: metadata, duration: resolvedDuration)

    var outcomes: [UUID: VisualOutcome] = [:]
    if let asset {
      if !actions.isEmpty {
        outcomes = await analyzeVisualOutcomes(
          actions: actions,
          asset: asset,
          duration: resolvedDuration
        )
      }
      // Also spot keyboard-triggered localized UI events (command palettes, dialogs, sheets) in idle stretches.
      let visualEvents = await detectAutonomousVisualEvents(
        existingActions: actions,
        outcomes: outcomes,
        asset: asset,
        duration: resolvedDuration
      )
      if !visualEvents.isEmpty {
        for (eventAction, eventOutcome) in visualEvents {
          actions.append(eventAction)
          outcomes[eventAction.id] = eventOutcome
        }
        actions.sort { $0.startTime < $1.startTime }
      }
    }

    guard !actions.isEmpty else { return .empty }

    return buildPlan(
      actions: actions,
      metadata: metadata,
      duration: resolvedDuration,
      style: style,
      visualOutcomes: outcomes,
      transitionDuration: transitionDuration
    )
  }

  /// Synchronous deterministic planner (useful for pure telemetry mode and unit tests).
  static func generatePlan(
    from metadata: RecordingMetadata,
    duration: TimeInterval,
    style: SmartAutoZoomStyle = .balanced,
    visualOutcomes: [UUID: VisualOutcome] = [:],
    transitionDuration: TimeInterval = ZoomCalculator.defaultTransitionDuration
  ) -> Plan {
    guard duration >= ZoomSegment.minDuration else { return .empty }
    let actions = detectActions(from: metadata, duration: duration)
    guard !actions.isEmpty else { return .empty }
    return buildPlan(
      actions: actions,
      metadata: metadata,
      duration: duration,
      style: style,
      visualOutcomes: visualOutcomes,
      transitionDuration: transitionDuration
    )
  }

  // MARK: - Stage 1: Action Extraction & Classification

  static func detectActions(
    from metadata: RecordingMetadata,
    duration: TimeInterval
  ) -> [DetectedAction] {
    let samples = canonicalSamples(from: metadata)
    let capture = metadata.cursorCapture

    if let clicks = capture?.clicks, !clicks.isEmpty {
      let rawClicks = extractClickActions(
        clicks: clicks,
        samples: samples,
        appearance: capture?.appearance ?? [],
        duration: duration
      )
      if !rawClicks.isEmpty {
        return rawClicks
      }
    }

    // Fallback for recordings without click events (non-Studio recordings): detect deliberate dwell pauses.
    return extractDwellActions(samples: samples, duration: duration)
  }

  private struct RawInteraction {
    let button: RecordedClickButton
    let startTime: TimeInterval
    let endTime: TimeInterval
    let startPoint: CGPoint
    let endPoint: CGPoint
    let waypoints: [(time: TimeInterval, point: CGPoint)]
    let bounds: CGRect
    let displacement: CGFloat
  }

  private static func extractClickActions(
    clicks: [RecordedClick],
    samples: [CanonicalSample],
    appearance: [RecordedCursorChange],
    duration: TimeInterval
  ) -> [DetectedAction] {
    let sortedClicks = clicks
      .filter { $0.time >= 0 && $0.time <= duration }
      .sorted { $0.time < $1.time }

    var openDowns: [RecordedClickButton: RecordedClick] = [:]
    var interactions: [RawInteraction] = []

    for click in sortedClicks {
      switch click.phase {
      case .down:
        if let stale = openDowns[click.button] {
          interactions.append(makeRawInteraction(down: stale, up: nil, samples: samples, duration: duration))
        }
        openDowns[click.button] = click
      case .up:
        if let down = openDowns.removeValue(forKey: click.button) {
          interactions.append(makeRawInteraction(down: down, up: click, samples: samples, duration: duration))
        }
      }
    }
    for stale in openDowns.values.sorted(by: { $0.time < $1.time }) {
      interactions.append(makeRawInteraction(down: stale, up: nil, samples: samples, duration: duration))
    }

    interactions.sort { $0.startTime < $1.startTime }
    guard !interactions.isEmpty else { return [] }

    // Collapse double / triple left clicks into a single detail-focused action.
    var actions: [DetectedAction] = []
    var index = 0
    while index < interactions.count {
      let current = interactions[index]
      let holdDuration = current.endTime - current.startTime

      var kind: ActionKind
      var endTime = current.endTime
      var endPoint = current.endPoint
      var bounds = current.bounds
      var waypoints = current.waypoints

      if current.displacement >= 0.025 {
        kind = .drag
      } else if current.button == .right {
        kind = .rightClick
      } else if holdDuration >= 0.35 {
        kind = .longPress
      } else {
        kind = .click
        // Look ahead for rapid double/triple clicks near the same target.
        var lookahead = index + 1
        while lookahead < interactions.count {
          let next = interactions[lookahead]
          let gap = next.startTime - endTime
          let dist = hypot(next.startPoint.x - current.startPoint.x, next.startPoint.y - current.startPoint.y)
          if next.button == current.button,
             next.displacement < 0.025,
             gap >= 0,
             gap <= 0.42,
             dist <= 0.028 {
            kind = .doubleClick
            endTime = max(endTime, next.endTime)
            endPoint = next.endPoint
            bounds = bounds.union(next.bounds)
            waypoints.append(contentsOf: next.waypoints)
            lookahead += 1
          } else {
            break
          }
        }
        index = lookahead - 1
      }

      let nextActionStart: TimeInterval = (index + 1 < interactions.count)
        ? interactions[index + 1].startTime
        : duration

      let anticipationLead = computeAnticipationLead(
        before: current.startTime,
        target: current.startPoint,
        samples: samples
      )
      let cursorChangedBeforeClick = appearance.contains { change in
        !change.isHidden && change.time >= current.startTime - 0.50 && change.time <= current.startTime + 0.03
      }
      let typingEnd = detectTypingEnd(
        after: endTime,
        actionPoint: endPoint,
        until: min(duration, nextActionStart),
        samples: samples,
        appearance: appearance
      )
      let exploreInfo = detectPostActionExplore(
        after: endTime,
        actionPoint: endPoint,
        until: min(duration, nextActionStart),
        samples: samples,
        appearance: appearance
      )
      let departedImmediately = didDepartImmediately(
        after: endTime,
        actionPoint: endPoint,
        until: min(duration, nextActionStart),
        samples: samples
      )

      let focusPoint = kind == .drag
        ? current.startPoint
        : CGPoint(x: bounds.midX, y: bounds.midY)

      actions.append(
        DetectedAction(
          id: UUID(),
          kind: kind,
          startTime: current.startTime,
          endTime: endTime,
          focusPoint: focusPoint.clampedToUnit,
          endPoint: endPoint.clampedToUnit,
          bounds: bounds,
          waypoints: waypoints,
          anticipationLead: anticipationLead,
          cursorChangedBeforeClick: cursorChangedBeforeClick,
          typingEndTime: typingEnd,
          postActionExploreEndTime: exploreInfo.endTime,
          followThroughBounds: exploreInfo.bounds,
          departedImmediately: departedImmediately
        )
      )

      index += 1
    }

    return actions
  }

  private static func makeRawInteraction(
    down: RecordedClick,
    up: RecordedClick?,
    samples: [CanonicalSample],
    duration: TimeInterval
  ) -> RawInteraction {
    let startPoint = down.normalizedPoint.clampedToUnit
    let rawEndTime = up?.time ?? min(duration, down.time + 0.12)
    let endTime = max(down.time, min(rawEndTime, duration))
    let endPoint = (up?.normalizedPoint ?? samplePoint(at: endTime, in: samples) ?? startPoint).clampedToUnit

    var waypoints: [(time: TimeInterval, point: CGPoint)] = [(down.time, startPoint)]
    var minX = min(startPoint.x, endPoint.x)
    var maxX = max(startPoint.x, endPoint.x)
    var minY = min(startPoint.y, endPoint.y)
    var maxY = max(startPoint.y, endPoint.y)

    let holdDuration = endTime - down.time
    let directDisplacement = hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)

    // Only sample intermediate drag trajectory when the button is actually held long enough
    // to be a real drag (>= 0.12s) or down→up coordinates themselves moved significantly.
    if holdDuration >= 0.12 || directDisplacement >= 0.025 {
      let inRange = samples.filter { $0.time > down.time && $0.time < endTime }
      let strideStep = max(1, inRange.count / 14)
      for idx in stride(from: 0, to: inRange.count, by: strideStep) {
        let s = inRange[idx]
        waypoints.append((s.time, s.point))
        minX = min(minX, s.point.x)
        maxX = max(maxX, s.point.x)
        minY = min(minY, s.point.y)
        maxY = max(maxY, s.point.y)
      }
    }
    if endTime > down.time + 0.005 {
      waypoints.append((endTime, endPoint))
    }

    let bounds = CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    let displacement = (holdDuration >= 0.12 || directDisplacement >= 0.025)
      ? max(directDisplacement, hypot(bounds.width, bounds.height))
      : directDisplacement

    return RawInteraction(
      button: down.button,
      startTime: down.time,
      endTime: endTime,
      startPoint: startPoint,
      endPoint: endPoint,
      waypoints: waypoints,
      bounds: bounds,
      displacement: displacement
    )
  }

  /// Finds natural anticipation lead time before a click by spotting cursor deceleration onto the target.
  private static func computeAnticipationLead(
    before clickTime: TimeInterval,
    target: CGPoint,
    samples: [CanonicalSample]
  ) -> TimeInterval {
    let defaultLead: TimeInterval = 0.38
    guard samples.count >= 3 else { return defaultLead }

    let windowStart = max(0, clickTime - 0.65)
    let approaching = samples.filter { $0.time >= windowStart && $0.time <= clickTime }
    guard approaching.count >= 3 else { return defaultLead }

    for idx in stride(from: approaching.count - 1, through: 1, by: -1) {
      let prev = approaching[idx - 1]
      let curr = approaching[idx]
      let dt = max(curr.time - prev.time, 0.001)
      let speed = hypot(curr.point.x - prev.point.x, curr.point.y - prev.point.y) / CGFloat(dt)
      let distToTarget = hypot(curr.point.x - target.x, curr.point.y - target.y)
      if speed > 0.58 && distToTarget > 0.04 {
        let lead = clickTime - curr.time
        return min(max(lead, 0.28), 0.52)
      }
    }
    return defaultLead
  }

  /// macOS automatically hides the cursor while the user types in a text field.
  private static func detectTypingEnd(
    after actionEnd: TimeInterval,
    actionPoint: CGPoint,
    until limitTime: TimeInterval,
    samples: [CanonicalSample],
    appearance: [RecordedCursorChange]
  ) -> TimeInterval? {
    guard !appearance.isEmpty, limitTime > actionEnd + 0.2 else { return nil }
    let searchEnd = min(limitTime, actionEnd + 1.8)
    guard let hideIndex = appearance.firstIndex(where: { $0.isHidden && $0.time >= actionEnd - 0.05 && $0.time <= searchEnd }) else {
      return nil
    }

    let hideTime = appearance[hideIndex].time
    if let posAtHide = samplePoint(at: hideTime, in: samples),
       hypot(posAtHide.x - actionPoint.x, posAtHide.y - actionPoint.y) > 0.24 {
      return nil
    }

    let reappearTime = appearance[(hideIndex + 1)...]
      .first(where: { !$0.isHidden && $0.time <= limitTime })?.time
      ?? min(limitTime, hideTime + 6.0)
    guard reappearTime > actionEnd + 0.15 else { return nil }
    return min(reappearTime, actionEnd + 12.0)
  }

  /// Detects local post-click exploration (e.g. clicking a menu then scanning dropdown items below it).
  private static func detectPostActionExplore(
    after actionEnd: TimeInterval,
    actionPoint: CGPoint,
    until limitTime: TimeInterval,
    samples: [CanonicalSample],
    appearance: [RecordedCursorChange]
  ) -> (endTime: TimeInterval?, bounds: CGRect?) {
    let windowEnd = min(limitTime, actionEnd + 2.2)
    guard windowEnd > actionEnd + 0.2 else { return (nil, nil) }

    var exploreEnd: TimeInterval?
    var minX = actionPoint.x
    var maxX = actionPoint.x
    var minY = actionPoint.y
    var maxY = actionPoint.y
    var foundLocalHover = false

    for change in appearance where !change.isHidden && change.time > actionEnd + 0.08 && change.time <= windowEnd {
      if let pos = samplePoint(at: change.time, in: samples),
         hypot(pos.x - actionPoint.x, pos.y - actionPoint.y) <= 0.30 {
        exploreEnd = change.time
        minX = min(minX, pos.x)
        maxX = max(maxX, pos.x)
        minY = min(minY, pos.y)
        maxY = max(maxY, pos.y)
        foundLocalHover = true
      }
    }

    // Also inspect slow local reading/scanning movement within 0.28 of click.
    let localSamples = samples.filter { $0.time >= actionEnd + 0.14 && $0.time <= min(windowEnd, actionEnd + 1.4) && $0.isInsideCapture }
    var slowCount = 0
    if localSamples.count >= 2 {
      for idx in 1 ..< localSamples.count {
        let a = localSamples[idx - 1]
        let b = localSamples[idx]
        let distFromClick = hypot(b.point.x - actionPoint.x, b.point.y - actionPoint.y)
        let dt = max(b.time - a.time, 0.001)
        let speed = hypot(b.point.x - a.point.x, b.point.y - a.point.y) / CGFloat(dt)
        if distFromClick > 0.03 && distFromClick <= 0.28 && speed < 0.55 {
          slowCount += 1
          minX = min(minX, b.point.x)
          maxX = max(maxX, b.point.x)
          minY = min(minY, b.point.y)
          maxY = max(maxY, b.point.y)
          if slowCount >= 5 {
            foundLocalHover = true
            exploreEnd = max(exploreEnd ?? 0, b.time)
          }
        }
      }
    }

    let bounds: CGRect? = foundLocalHover
      ? CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
      : nil
    return (exploreEnd, bounds)
  }

  /// True when cursor immediately zips far away within 0.26s of clicking (classic stray window-focus click).
  private static func didDepartImmediately(
    after actionEnd: TimeInterval,
    actionPoint: CGPoint,
    until limitTime: TimeInterval,
    samples: [CanonicalSample]
  ) -> Bool {
    let checkTime = min(limitTime, actionEnd + 0.26)
    guard checkTime > actionEnd + 0.12,
          let laterPos = samplePoint(at: checkTime, in: samples)
    else { return false }
    return hypot(laterPos.x - actionPoint.x, laterPos.y - actionPoint.y) > 0.16
  }

  /// Fallback action detector when click telemetry is unavailable (older / non-Studio recordings).
  private static func extractDwellActions(
    samples: [CanonicalSample],
    duration: TimeInterval
  ) -> [DetectedAction] {
    guard samples.count >= 6 else { return [] }

    var actions: [DetectedAction] = []
    let dwellRadius: CGFloat = 0.022
    let minDwellDuration: TimeInterval = 0.45
    let minApproachDistance: CGFloat = 0.07

    var anchorIndex = 0
    var lastActionPoint: CGPoint?

    while anchorIndex < samples.count {
      let anchor = samples[anchorIndex]
      guard anchor.isInsideCapture else {
        anchorIndex += 1
        continue
      }

      var endIndex = anchorIndex + 1
      var sumX = anchor.point.x
      var sumY = anchor.point.y
      var count: CGFloat = 1

      while endIndex < samples.count {
        let candidate = samples[endIndex]
        guard candidate.isInsideCapture else { break }
        let dist = hypot(candidate.point.x - anchor.point.x, candidate.point.y - anchor.point.y)
        if dist <= dwellRadius {
          sumX += candidate.point.x
          sumY += candidate.point.y
          count += 1
          endIndex += 1
        } else {
          break
        }
      }

      let dwellEnd = samples[endIndex - 1].time
      let dwellDuration = dwellEnd - anchor.time
      if dwellDuration >= minDwellDuration {
        let centroid = CGPoint(x: sumX / count, y: sumY / count).clampedToUnit
        let movedEnough: Bool
        if let lastPoint = lastActionPoint {
          movedEnough = hypot(centroid.x - lastPoint.x, centroid.y - lastPoint.y) >= minApproachDistance
        } else {
          movedEnough = true
        }

        if movedEnough {
          let activeEnd = min(duration, anchor.time + min(dwellDuration, 2.5))
          actions.append(
            DetectedAction(
              id: UUID(),
              kind: .dwellFocus,
              startTime: anchor.time,
              endTime: activeEnd,
              focusPoint: centroid,
              endPoint: centroid,
              bounds: CGRect(origin: centroid, size: .zero),
              waypoints: [(anchor.time, centroid)],
              anticipationLead: 0.36,
              cursorChangedBeforeClick: false,
              typingEndTime: nil,
              postActionExploreEndTime: nil
            )
          )
          lastActionPoint = centroid
        }
      }

      anchorIndex = max(endIndex, anchorIndex + 1)
    }

    return actions
  }

  // MARK: - Stage 2: 32×18 RGB Connected-Component Visual Outcome Analysis

  static let visualGridWidth = 16
  static let visualGridHeight = 9
  static let rgbGridWidth = 32
  static let rgbGridHeight = 18

  /// Grayscale grid analyzer (kept for unit tests & lightweight inputs); internally runs connected-component isolation.
  static func analyzeGridSequence(
    preGrid: [Float],
    postSamples: [(time: TimeInterval, grid: [Float])],
    gridWidth: Int = visualGridWidth,
    gridHeight: Int = visualGridHeight,
    actionPoint: CGPoint,
    actionEndTime: TimeInterval
  ) -> VisualOutcome {
    let cellCount = gridWidth * gridHeight
    guard preGrid.count == cellCount, !postSamples.isEmpty else {
      return .none(at: actionEndTime, point: actionPoint)
    }
    // Expand grayscale scalar grid to RGB triplets to reuse the exact connected-component analyzer.
    func toRGB(_ g: [Float]) -> [Float] {
      var out = [Float](repeating: 0, count: g.count * 3)
      for i in 0 ..< g.count {
        out[i * 3] = g[i]
        out[i * 3 + 1] = g[i]
        out[i * 3 + 2] = g[i]
      }
      return out
    }
    return analyzeRGBGridSequence(
      preGrid: toRGB(preGrid),
      postSamples: postSamples.map { ($0.time, toRGB($0.grid)) },
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      actionPoint: actionPoint,
      actionEndTime: actionEndTime
    )
  }

  /// High-sensitivity RGB max-channel spatial-temporal visual outcome analyzer with
  /// 4-connected cluster flood fill so menu bar clock ticks or stray status pulses
  /// NEVER pollute the framing of the real popover, modal, or updated UI panel.
  static func analyzeRGBGridSequence(
    preGrid: [Float],
    postSamples: [(time: TimeInterval, grid: [Float])],
    gridWidth: Int = rgbGridWidth,
    gridHeight: Int = rgbGridHeight,
    actionPoint: CGPoint,
    actionEndTime: TimeInterval
  ) -> VisualOutcome {
    let cellCount = gridWidth * gridHeight
    guard preGrid.count == cellCount * 3, !postSamples.isEmpty else {
      return .none(at: actionEndTime, point: actionPoint)
    }

    let frameDeltaThreshold: Float = 0.042
    let baselineDeltaThreshold: Float = 0.048

    @inline(__always)
    func maxRGBDiff(_ a: [Float], _ b: [Float], cell: Int) -> Float {
      let i = cell * 3
      return max(abs(a[i] - b[i]), max(abs(a[i + 1] - b[i + 1]), abs(a[i + 2] - b[i + 2])))
    }

    var settleTime = actionEndTime
    var previousGrid = preGrid
    var settledGrid = preGrid
    var settledTimestamp = actionEndTime
    var validPostCount = 0
    var movingFrameCount = 0

    for sample in postSamples where sample.grid.count == cellCount * 3 {
      validPostCount += 1
      var movingCells = 0
      for cell in 0 ..< cellCount {
        if maxRGBDiff(sample.grid, previousGrid, cell: cell) >= frameDeltaThreshold {
          movingCells += 1
        }
      }
      let movingRatio = Float(movingCells) / Float(cellCount)
      if movingRatio >= 0.014 {
        settleTime = sample.time
        movingFrameCount += 1
      }
      settledGrid = sample.grid
      settledTimestamp = sample.time
      previousGrid = sample.grid
    }

    let isSustainedMotion = validPostCount >= 4 && Float(movingFrameCount) / Float(validPostCount) >= 0.72

    // Build per-cell diff map against pre-action baseline.
    var diffs = [Float](repeating: 0, count: cellCount)
    var totalChangedCells = 0
    for cell in 0 ..< cellCount {
      let d = maxRGBDiff(settledGrid, preGrid, cell: cell)
      if d >= baselineDeltaThreshold {
        diffs[cell] = d
        totalChangedCells += 1
      }
    }

    let totalCoverage = CGFloat(totalChangedCells) / CGFloat(cellCount)
    guard totalChangedCells > 0 else {
      return VisualOutcome(
        kind: .none,
        settleTime: max(actionEndTime, settleTime),
        changedCoverage: 0,
        outcomeCentroid: actionPoint,
        outcomeBounds: CGRect(origin: actionPoint, size: .zero),
        isSustainedMotion: false
      )
    }

    // Major context switch (new app window opened, window closed, document loaded, or video playback started):
    // reveal the full screen smoothly instead of staying trapped zoomed in on the old button!
    if totalCoverage >= 0.34 || (isSustainedMotion && totalCoverage >= 0.14) {
      return VisualOutcome(
        kind: .fullScreenTransition,
        settleTime: max(actionEndTime, min(settleTime, settledTimestamp)),
        changedCoverage: totalCoverage,
        outcomeCentroid: CGPoint(x: 0.5, y: 0.5),
        outcomeBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
        isSustainedMotion: isSustainedMotion
      )
    }

    // Connected-component flood fill (8-neighbor so thin borders stay unified) to isolate real UI panels from clock noise.
    var visited = [Bool](repeating: false, count: cellCount)
    struct Cluster {
      let cellCount: Int
      let weightSum: CGFloat
      let centroid: CGPoint
      let bounds: CGRect
      let score: CGFloat
    }
    var clusters: [Cluster] = []
    var queue: [Int] = []
    queue.reserveCapacity(64)

    for startCell in 0 ..< cellCount where diffs[startCell] > 0 && !visited[startCell] {
      visited[startCell] = true
      queue.removeAll(keepingCapacity: true)
      queue.append(startCell)

      var head = 0
      var count = 0
      var weightSum: CGFloat = 0
      var wx: CGFloat = 0
      var wy: CGFloat = 0
      var minCol = gridWidth
      var maxCol = 0
      var minRow = gridHeight
      var maxRow = 0

      while head < queue.count {
        let curr = queue[head]
        head += 1
        let r = curr / gridWidth
        let c = curr % gridWidth
        let w = CGFloat(diffs[curr])

        count += 1
        weightSum += w
        wx += ((CGFloat(c) + 0.5) / CGFloat(gridWidth)) * w
        wy += ((CGFloat(r) + 0.5) / CGFloat(gridHeight)) * w
        minCol = min(minCol, c)
        maxCol = max(maxCol, c)
        minRow = min(minRow, r)
        maxRow = max(maxRow, r)

        for dr in -1 ... 1 {
          let nr = r + dr
          guard nr >= 0 && nr < gridHeight else { continue }
          for dc in -1 ... 1 {
            if dr == 0 && dc == 0 { continue }
            let nc = c + dc
            guard nc >= 0 && nc < gridWidth else { continue }
            let next = nr * gridWidth + nc
            if diffs[next] > 0 && !visited[next] {
              visited[next] = true
              queue.append(next)
            }
          }
        }
      }

      // Filter out 1-cell noise (e.g. menu bar clock digit or cursor artifact).
      let minClusterCells = gridWidth >= 24 ? 3 : 2
      guard count >= minClusterCells, weightSum > 0.0001 else { continue }

      let centroid = CGPoint(x: wx / weightSum, y: wy / weightSum).clampedToUnit
      let bounds = CGRect(
        x: CGFloat(minCol) / CGFloat(gridWidth),
        y: CGFloat(minRow) / CGFloat(gridHeight),
        width: CGFloat(maxCol - minCol + 1) / CGFloat(gridWidth),
        height: CGFloat(maxRow - minRow + 1) / CGFloat(gridHeight)
      )

      // Down-weight tiny top-edge menu bar ticker noise unless the user actually clicked the menu bar.
      let isMenuBarNoise = bounds.maxY < 0.08 && actionPoint.y > 0.12 && count < 8
      let dist = hypot(centroid.x - actionPoint.x, centroid.y - actionPoint.y)
      let proximityBonus = 1.0 + max(0, (0.45 - dist) * 1.4)
      let score = weightSum * proximityBonus * (isMenuBarNoise ? 0.1 : 1.0)

      clusters.append(
        Cluster(
          cellCount: count,
          weightSum: weightSum,
          centroid: centroid,
          bounds: bounds,
          score: score
        )
      )
    }

    guard let primary = clusters.max(by: { $0.score < $1.score }) else {
      return VisualOutcome(
        kind: .none,
        settleTime: max(actionEndTime, settleTime),
        changedCoverage: 0,
        outcomeCentroid: actionPoint,
        outcomeBounds: CGRect(origin: actionPoint, size: .zero)
      )
    }

    // Merge any strong sibling cluster directly adjacent to the primary cluster (e.g. popover + shadow/badge).
    var mergedBounds = primary.bounds
    var mergedCells = primary.cellCount
    var mergedWX = primary.centroid.x * primary.weightSum
    var mergedWY = primary.centroid.y * primary.weightSum
    var mergedWeight = primary.weightSum

    for other in clusters where other.bounds != primary.bounds {
      if mergedBounds.insetBy(dx: -0.08, dy: -0.08).intersects(other.bounds),
         other.score >= primary.score * 0.25 {
        mergedBounds = mergedBounds.union(other.bounds)
        mergedCells += other.cellCount
        mergedWX += other.centroid.x * other.weightSum
        mergedWY += other.centroid.y * other.weightSum
        mergedWeight += other.weightSum
      }
    }

    let finalCentroid = CGPoint(x: mergedWX / mergedWeight, y: mergedWY / mergedWeight).clampedToUnit
    let clusterCoverage = CGFloat(mergedCells) / CGFloat(cellCount)
    let distFromClick = hypot(finalCentroid.x - actionPoint.x, finalCentroid.y - actionPoint.y)

    let kind: VisualOutcomeKind
    if clusterCoverage < 0.008 {
      kind = .none
    } else if distFromClick >= 0.26 {
      kind = .localRemoteResult
    } else {
      kind = .localNearClick
    }

    return VisualOutcome(
      kind: kind,
      settleTime: max(actionEndTime, min(settleTime, settledTimestamp)),
      changedCoverage: clusterCoverage,
      outcomeCentroid: finalCentroid,
      outcomeBounds: mergedBounds
    )
  }

  /// Samples tiny 160×90 RGB thumbnails around post-action windows to detect connected UI outcomes.
  private static func analyzeVisualOutcomes(
    actions: [DetectedAction],
    asset: AVAsset,
    duration: TimeInterval
  ) async -> [UUID: VisualOutcome] {
    guard !actions.isEmpty else { return [:] }

    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 160, height: 90)
    generator.requestedTimeToleranceBefore = CMTime(seconds: 0.12, preferredTimescale: 600)
    generator.requestedTimeToleranceAfter = CMTime(seconds: 0.12, preferredTimescale: 600)

    let maxBudgetFrames = 96
    let maxActionsToInspect = min(actions.count, 24)
    let strideActions = max(1, Int(ceil(Double(actions.count) / Double(maxActionsToInspect))))

    var results: [UUID: VisualOutcome] = [:]
    var framesUsed = 0
    let postOffsets: [TimeInterval] = [0.16, 0.42, 0.74, 1.12, 1.58]

    for idx in stride(from: 0, to: actions.count, by: strideActions) {
      if Task.isCancelled || framesUsed >= maxBudgetFrames { break }
      let action = actions[idx]
      let nextStart = (idx + 1 < actions.count) ? actions[idx + 1].startTime : duration
      let observationEnd = min(duration, min(action.endTime + 2.2, max(action.endTime + 0.55, nextStart - 0.12)))
      guard observationEnd > action.endTime + 0.12 else { continue }

      let preTime = max(0, action.startTime - 0.12)
      guard let preGrid = sampleRGBGrid(at: preTime, generator: generator) else { continue }
      framesUsed += 1

      var postSamples: [(time: TimeInterval, grid: [Float])] = []
      var quietCount = 0
      var prevGrid = preGrid

      for offset in postOffsets {
        let t = action.endTime + offset
        guard t <= observationEnd, framesUsed < maxBudgetFrames else { break }
        if Task.isCancelled { break }
        if let grid = sampleRGBGrid(at: t, generator: generator) {
          framesUsed += 1
          postSamples.append((t, grid))

          var moving = 0
          let cellCount = rgbGridWidth * rgbGridHeight
          for cell in 0 ..< cellCount {
            let i = cell * 3
            let diff = max(abs(grid[i] - prevGrid[i]), max(abs(grid[i + 1] - prevGrid[i + 1]), abs(grid[i + 2] - prevGrid[i + 2])))
            if diff >= 0.042 { moving += 1 }
          }
          if Float(moving) / Float(cellCount) < 0.012 {
            quietCount += 1
            if quietCount >= 2 && postSamples.count >= 3 {
              break
            }
          } else {
            quietCount = 0
          }
          prevGrid = grid
        }
      }

      if !postSamples.isEmpty {
        results[action.id] = analyzeRGBGridSequence(
          preGrid: preGrid,
          postSamples: postSamples,
          actionPoint: action.endPoint,
          actionEndTime: action.endTime
        )
      }
    }

    return results
  }

  /// Coarse visual scanner for keyboard-triggered UI popups/modals occurring in idle gaps without clicks.
  private static func detectAutonomousVisualEvents(
    existingActions: [DetectedAction],
    outcomes: [UUID: VisualOutcome],
    asset: AVAsset,
    duration: TimeInterval
  ) async -> [(DetectedAction, VisualOutcome)] {
    guard duration >= 3.0 else { return [] }

    // Identify idle gaps > 2.6s where no clicks happened, skipping gaps that immediately follow
    // sustained motion (e.g. clicking Play to watch video playback).
    var idleGaps: [(TimeInterval, TimeInterval)] = []
    var cursor: TimeInterval = 0.4
    var precedingWasSustainedMotion = false
    for action in existingActions.sorted(by: { $0.startTime < $1.startTime }) {
      if action.startTime - cursor >= 2.6, !precedingWasSustainedMotion {
        idleGaps.append((cursor, action.startTime - 0.5))
      }
      cursor = max(cursor, action.endTime + 1.1)
      precedingWasSustainedMotion = outcomes[action.id]?.isSustainedMotion == true
    }
    if duration - cursor >= 2.6, !precedingWasSustainedMotion {
      idleGaps.append((cursor, duration - 0.4))
    }
    guard !idleGaps.isEmpty else { return [] }

    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 160, height: 90)
    generator.requestedTimeToleranceBefore = CMTime(seconds: 0.15, preferredTimescale: 600)
    generator.requestedTimeToleranceAfter = CMTime(seconds: 0.15, preferredTimescale: 600)

    var events: [(DetectedAction, VisualOutcome)] = []
    var framesUsed = 0
    let maxScanFrames = 24
    let scanStep: TimeInterval = 1.2

    func isStaticBetween(_ a: [Float], _ b: [Float]) -> Bool {
      let cellCount = rgbGridWidth * rgbGridHeight
      var stillMovingCells = 0
      for cell in 0 ..< cellCount {
        let i = cell * 3
        let diff = max(
          abs(b[i] - a[i]),
          max(abs(b[i + 1] - a[i + 1]), abs(b[i + 2] - a[i + 2]))
        )
        if diff >= 0.045 { stillMovingCells += 1 }
      }
      return Float(stillMovingCells) / Float(cellCount) < 0.020
    }

    for (gapStart, gapEnd) in idleGaps {
      if Task.isCancelled || framesUsed >= maxScanFrames { break }
      guard var prevGrid = sampleRGBGrid(at: gapStart, generator: generator) else { continue }
      framesUsed += 1

      var t = gapStart + scanStep
      while t <= gapEnd, framesUsed < maxScanFrames {
        if Task.isCancelled { break }
        guard let currGrid = sampleRGBGrid(at: t, generator: generator) else {
          t += scanStep
          continue
        }
        framesUsed += 1

        let outcome = analyzeRGBGridSequence(
          preGrid: prevGrid,
          postSamples: [(t, currGrid)],
          actionPoint: CGPoint(x: 0.5, y: 0.5),
          actionEndTime: t
        )

        // Only promote unmistakable STATIC localized UI appearances (e.g. Spotlight, Command Palette, modal).
        // Verify stability at BOTH +0.55s and +1.15s so playing video or scrolling NEVER triggers false zooms.
        if (outcome.kind == .localNearClick || outcome.kind == .localRemoteResult),
           outcome.changedCoverage >= 0.04,
           outcome.changedCoverage <= 0.30,
           t + 1.15 <= gapEnd,
           framesUsed + 2 <= maxScanFrames,
           let confirm1 = sampleRGBGrid(at: t + 0.55, generator: generator),
           let confirm2 = sampleRGBGrid(at: t + 1.15, generator: generator) {
          framesUsed += 2
          if isStaticBetween(currGrid, confirm1) && isStaticBetween(confirm1, confirm2) {
            let action = DetectedAction(
              id: UUID(),
              kind: .visualEvent,
              startTime: max(gapStart, t - 0.25),
              endTime: t + 0.1,
              focusPoint: outcome.outcomeCentroid,
              endPoint: outcome.outcomeCentroid,
              bounds: outcome.outcomeBounds,
              waypoints: [(t, outcome.outcomeCentroid)],
              anticipationLead: 0.30,
              cursorChangedBeforeClick: false,
              typingEndTime: nil,
              postActionExploreEndTime: nil
            )
            events.append((action, outcome))
            t += 2.6
            if t <= gapEnd, framesUsed < maxScanFrames, let refreshed = sampleRGBGrid(at: t, generator: generator) {
              framesUsed += 1
              prevGrid = refreshed
            }
            t += scanStep
            continue
          }
        }

        prevGrid = currGrid
        t += scanStep
      }
    }

    return events
  }

  private static func sampleRGBGrid(
    at time: TimeInterval,
    generator: AVAssetImageGenerator
  ) -> [Float]? {
    let cmTime = CMTime(seconds: max(0, time), preferredTimescale: 600)
    guard let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil) else {
      return nil
    }
    return downsampleToRGBGrid(cgImage: cgImage, width: rgbGridWidth, height: rgbGridHeight)
  }

  private static func downsampleToRGBGrid(
    cgImage: CGImage,
    width: Int,
    height: Int
  ) -> [Float]? {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
      data: &bytes,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return nil
    }
    context.interpolationQuality = .low
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    var rgb = [Float](repeating: 0, count: width * height * 3)
    for cell in 0 ..< (width * height) {
      let src = cell * 4
      let dst = cell * 3
      rgb[dst] = Float(bytes[src]) / 255.0
      rgb[dst + 1] = Float(bytes[src + 1]) / 255.0
      rgb[dst + 2] = Float(bytes[src + 2]) / 255.0
    }
    return rgb
  }

  // MARK: - Stage 3: Importance Filtering, Intelligent Clustering & Spring Keyframe Synthesis

  private struct ActionPlanItem {
    let action: DetectedAction
    let outcome: VisualOutcome
    let desiredZoom: CGFloat
    let outcomeHoldEnd: TimeInterval
    let triggersZoomOut: Bool
  }

  /// Synchronous deterministic planner from pre-extracted actions and optional visual outcomes.
  static func buildPlan(
    actions: [DetectedAction],
    metadata: RecordingMetadata,
    duration: TimeInterval,
    style: SmartAutoZoomStyle = .balanced,
    visualOutcomes: [UUID: VisualOutcome] = [:],
    transitionDuration: TimeInterval = ZoomCalculator.defaultTransitionDuration
  ) -> Plan {
    let samples = canonicalSamples(from: metadata)
    let clampedTransition = ZoomCalculator.clampTransitionDuration(transitionDuration)
    let hasVisualTelemetry = !visualOutcomes.isEmpty

    // 1a. Drop isolated trailing stop-recording clicks in the final 0.55s of a recording so the
    //     video never ends with an abrupt, half-finished zoom blip.
    let withoutTrailingStopClicks = actions.filter { action in
      if duration > 2.0,
         action.kind != .drag,
         action.startTime > duration - 0.55 {
        return false
      }
      return true
    }

    // 1b. Score & filter out meaningless stray background focus clicks when visual telemetry confirms zero impact.
    let meaningfulActions = withoutTrailingStopClicks.filter { action in
      guard action.kind == .click else { return true }
      if hasVisualTelemetry,
         let outcome = visualOutcomes[action.id],
         outcome.kind == .none,
         action.departedImmediately,
         !action.cursorChangedBeforeClick,
         action.typingEndTime == nil,
         action.postActionExploreEndTime == nil {
        return false
      }
      return true
    }

    let activeActions = meaningfulActions.isEmpty ? withoutTrailingStopClicks : meaningfulActions

    // 2. Score every action with its optimal zoom level & outcome hold duration.
    let items: [ActionPlanItem] = activeActions.map { action in
      let outcome = visualOutcomes[action.id] ?? .none(at: action.endTime, point: action.endPoint)
      return planItem(for: action, outcome: outcome, style: style, duration: duration)
    }

    // 3. Group consecutive actions into cohesive Zoom Chapters (merge workflows, split on page switches/idle).
    var chapters: [[ActionPlanItem]] = []
    for item in items {
      guard var lastChapter = chapters.last, let prev = lastChapter.last else {
        chapters.append([item])
        continue
      }

      let nextLeadStart = max(0, item.action.startTime - item.action.anticipationLead)
      let gapAfterOutcome = nextLeadStart - prev.outcomeHoldEnd
      let chapterStart = max(0, lastChapter[0].action.startTime - lastChapter[0].action.anticipationLead)
      let projectedDuration = (item.outcomeHoldEnd + clampedTransition) - chapterStart
      let cursorLeftCapture = didCursorLeaveCapture(
        from: prev.action.endTime,
        to: item.action.startTime,
        samples: samples
      )

      let actionGap = item.action.startTime - prev.action.endTime
      // Only honor a zoom-out split when there is genuine breathing room (>= 0.95s) before the next click;
      // otherwise slamming out to 1.0x for 0.22s and immediately slamming back in feels jarring.
      let effectiveZoomOutSplit = prev.triggersZoomOut && actionGap >= 0.95

      let shouldMerge = !effectiveZoomOutSplit
        && !cursorLeftCapture
        && gapAfterOutcome <= style.mergeGapThreshold
        && projectedDuration <= style.maxChapterDuration

      if shouldMerge {
        lastChapter.append(item)
        chapters[chapters.count - 1] = lastChapter
      } else {
        chapters.append([item])
      }
    }

    // 4. Synthesize clean spring-ready keyframes for each chapter.
    var rawSegments: [ZoomSegment] = []
    for chapter in chapters {
      if let segment = buildSegment(
        from: chapter,
        duration: duration,
        style: style,
        transitionDuration: clampedTransition
      ) {
        rawSegments.append(segment)
      }
    }

    // 5. Enforce strict non-overlap and clean breathing gaps.
    let finalSegments = resolveNonOverlappingSegments(rawSegments, duration: duration)

    return Plan(
      segments: finalSegments,
      actionCount: activeActions.count,
      analyzedVisualOutcomes: visualOutcomes.count
    )
  }

  private static func planItem(
    for action: DetectedAction,
    outcome: VisualOutcome,
    style: SmartAutoZoomStyle,
    duration: TimeInterval
  ) -> ActionPlanItem {
    // Choose optimal zoom level adapted to both action semantics and real UI outcome size.
    var desiredZoom: CGFloat
    switch action.kind {
    case .doubleClick:
      desiredZoom = style.detailZoom
    case .rightClick:
      desiredZoom = style.contextZoom
    case .drag:
      let span = max(action.bounds.width, action.bounds.height)
      if span > 0.55 {
        desiredZoom = max(style.minOutcomeZoom, style.contextZoom - 0.15)
      } else if span > 0.25 {
        desiredZoom = style.contextZoom
      } else {
        desiredZoom = style.baseZoom
      }
    case .longPress:
      desiredZoom = style.baseZoom
    case .click:
      desiredZoom = action.cursorChangedBeforeClick ? min(style.detailZoom, style.baseZoom + 0.14) : style.baseZoom
    case .dwellFocus:
      desiredZoom = style.contextZoom
    case .visualEvent:
      desiredZoom = fitZoom(for: outcome.outcomeBounds, maxZoom: style.baseZoom, minZoom: style.minOutcomeZoom)
    }

    // Never over-zoom when the immediate UI result is a large dialog/card.
    if outcome.kind == .localNearClick, outcome.changedCoverage > 0.18 {
      let comfy = fitZoom(for: outcome.outcomeBounds, maxZoom: desiredZoom, minZoom: style.minOutcomeZoom)
      desiredZoom = min(desiredZoom, comfy + 0.15)
    }

    let triggersZoomOut: Bool
    var holdEnd: TimeInterval

    switch outcome.kind {
    case .fullScreenTransition:
      // Show the click land + transition start, then spring zoom-out cleanly to reveal the full screen / playback.
      triggersZoomOut = true
      holdEnd = action.endTime + (outcome.isSustainedMotion ? 0.24 : 0.34)

    case .localNearClick:
      triggersZoomOut = false
      // Larger UI outcomes (popovers/panels with more to read) earn a slightly longer comprehension beat.
      let complexityBonus = Double(min(outcome.changedCoverage, 0.30)) * 1.4
      holdEnd = max(action.endTime + 0.90, outcome.settleTime + style.readingBeat + complexityBonus)

    case .localRemoteResult:
      triggersZoomOut = false
      let complexityBonus = Double(min(outcome.changedCoverage, 0.30)) * 1.6
      holdEnd = max(action.endTime + 1.25, outcome.settleTime + style.readingBeat + 0.28 + complexityBonus)

    case .none:
      triggersZoomOut = false
      let baseHold: TimeInterval = switch action.kind {
      case .rightClick: 1.40
      case .drag: 1.05
      case .doubleClick: 1.10
      case .longPress: 1.00
      case .click: 0.90
      case .dwellFocus: 0.65
      case .visualEvent: 1.15
      }
      holdEnd = max(action.endTime + baseHold, outcome.settleTime + 0.60)
    }

    if let typingEnd = action.typingEndTime, !triggersZoomOut {
      holdEnd = max(holdEnd, typingEnd + style.readingBeat)
    }
    if let exploreEnd = action.postActionExploreEndTime, !triggersZoomOut {
      holdEnd = max(holdEnd, exploreEnd + 0.72)
    }

    holdEnd = min(duration, holdEnd)

    return ActionPlanItem(
      action: action,
      outcome: outcome,
      desiredZoom: desiredZoom.clamped(to: ZoomSegment.minZoomLevel ... ZoomSegment.maxZoomLevel),
      outcomeHoldEnd: holdEnd,
      triggersZoomOut: triggersZoomOut
    )
  }

  private static func buildSegment(
    from chapter: [ActionPlanItem],
    duration: TimeInterval,
    style: SmartAutoZoomStyle,
    transitionDuration: TimeInterval
  ) -> ZoomSegment? {
    guard let first = chapter.first, let last = chapter.last else { return nil }

    let leadIn = max(first.action.anticipationLead, transitionDuration * 0.78)
    let startTime = max(0, first.action.startTime - leadIn)
    let exitTail = transitionDuration * 0.96
    let rawEndTime = min(duration, last.outcomeHoldEnd + exitTail)
    let segmentDuration = min(ZoomSegment.maxDuration, rawEndTime - startTime)
    let minSegmentDuration: TimeInterval = duration >= 1.5 ? 1.15 : ZoomSegment.minDuration
    guard segmentDuration >= minSegmentDuration else { return nil }
    let endTime = startTime + segmentDuration

    // Use a coherent chapter zoom (median for multi-action chapters so one outlier never forces
    // every other action to pump down and up, while single actions keep their exact target zoom).
    let chapterZoom: CGFloat
    if chapter.count == 1 {
      chapterZoom = first.desiredZoom
    } else {
      let sortedZooms = chapter.map(\.desiredZoom).sorted()
      chapterZoom = sortedZooms[sortedZooms.count / 2]
    }
    let zoomDelta = max(chapterZoom - 1.0, 0.05)

    // Zero-pump discipline: keep intra-chapter zoom multipliers within a calm 0.78...1.00 band.
    // Whenever a result genuinely needs full-screen visibility, Stage 2 promotes it to
    // `.fullScreenTransition` so the camera zooms all the way out to 1.0x cleanly instead of
    // awkwardly oscillating mid-chapter.
    func multiplier(for targetZoom: CGFloat) -> CGFloat {
      let upperZoom = max(style.minOutcomeZoom, chapterZoom)
      let clamped = targetZoom.clamped(to: style.minOutcomeZoom ... upperZoom)
      return ((clamped - 1.0) / zoomDelta).clamped(to: 0.78 ... 1.0)
    }

    var keyframes: [AutoFocusCameraSample] = []

    func appendKeyframe(time: TimeInterval, center: CGPoint, zoom: CGFloat) {
      let clampedTime = min(max(time, startTime), endTime)
      let mult = multiplier(for: zoom)
      let safeCenter = clampedCameraCenter(center, for: zoom)
      if let lastKey = keyframes.last, clampedTime <= lastKey.time + 0.015 {
        keyframes[keyframes.count - 1] = AutoFocusCameraSample(
          time: lastKey.time,
          center: safeCenter,
          zoomMultiplier: mult
        )
        return
      }
      keyframes.append(AutoFocusCameraSample(time: clampedTime, center: safeCenter, zoomMultiplier: mult))
    }

    let firstTarget = actionFraming(for: first.action, desiredZoom: first.desiredZoom, style: style)
    appendKeyframe(time: startTime, center: firstTarget.center, zoom: firstTarget.zoom)

    for (index, item) in chapter.enumerated() {
      let action = item.action
      let framing = actionFraming(for: action, desiredZoom: item.desiredZoom, style: style)

      // Smooth cross-screen glide with subtle cinematic mid-pan arc breath ONLY on long spans.
      if index > 0, let prevKey = keyframes.last {
        let travel = hypot(framing.center.x - prevKey.center.x, framing.center.y - prevKey.center.y)
        let arrivalTime = max(prevKey.time + 0.08, action.startTime - min(action.anticipationLead * 0.42, 0.16))
        let panSpan = arrivalTime - prevKey.time

        if travel > 0.34 && panSpan >= 0.44 {
          let midTime = prevKey.time + panSpan * 0.5
          let midCenter = CGPoint(
            x: (prevKey.center.x + framing.center.x) * 0.5,
            y: (prevKey.center.y + framing.center.y) * 0.5
          )
          // Gentle spatial breath (~85% of chapter zoom -> ~0.78-0.85 multiplier) with zero jarring dip.
          let arcZoom = max(style.minOutcomeZoom, min(framing.zoom, chapterZoom) * 0.85)
          appendKeyframe(time: midTime, center: midCenter, zoom: arcZoom)
        }

        appendKeyframe(time: arrivalTime, center: framing.center, zoom: framing.zoom)
      } else {
        appendKeyframe(time: action.startTime, center: framing.center, zoom: framing.zoom)
      }

      // Track drags intelligently:
      // - Small UI control drags (sliders, switches, scrollbars <= 14% of screen) stay rock-steady!
      // - Large spatial drags (moving files/windows across screen) glide along <= 4 smooth waypoints.
      let dragSpan = hypot(action.bounds.width, action.bounds.height)
      if action.kind == .drag, action.waypoints.count >= 2 {
        if dragSpan <= 0.14 {
          if action.endTime > action.startTime + 0.06 {
            appendKeyframe(time: action.endTime, center: framing.center, zoom: framing.zoom)
          }
        } else {
          let dragZoom = fitZoom(for: action.bounds, maxZoom: framing.zoom, minZoom: style.minOutcomeZoom)
          let smoothWaypoints = downsampleWaypoints(Array(action.waypoints.dropFirst()), maxCount: 4)
          for waypoint in smoothWaypoints {
            appendKeyframe(time: waypoint.time, center: waypoint.point, zoom: dragZoom)
          }
        }
      } else if action.endTime > action.startTime + 0.08 {
        appendKeyframe(time: action.endTime, center: framing.center, zoom: framing.zoom)
      }

      // Look-ahead Cause -> Effect linking: inspect the next action in the chapter before deciding
      // whether to emit an intermediate outcome reframe or glide directly in one unbroken curve.
      let nextItem: ActionPlanItem? = (index + 1 < chapter.count) ? chapter[index + 1] : nil
      let nextFraming: (center: CGPoint, zoom: CGFloat)? = nextItem.map {
        actionFraming(for: $0.action, desiredZoom: $0.desiredZoom, style: style)
      }

      let outcomeCeiling: TimeInterval
      if let nextItem, let nextFraming {
        let nextTravel = hypot(nextFraming.center.x - framing.center.x, nextFraming.center.y - framing.center.y)
        let reservedPanTime = nextTravel > 0.24
          ? min(0.72, 0.38 + Double(nextTravel) * 0.42)
          : 0.30
        let latestHoldBeforePan = nextItem.action.startTime - reservedPanTime
        outcomeCeiling = min(item.outcomeHoldEnd, max(action.endTime + 0.16, latestHoldBeforePan))
      } else {
        outcomeCeiling = min(item.outcomeHoldEnd, endTime)
      }

      let shouldLinkDirectlyToNext: Bool
      if let nextItem, let nextFraming {
        let timeToNext = nextItem.action.startTime - action.endTime
        let outcomeToNextDist = hypot(
          nextItem.action.focusPoint.x - item.outcome.outcomeCentroid.x,
          nextItem.action.focusPoint.y - item.outcome.outcomeCentroid.y
        )
        let nextInsideOutcome = item.outcome.outcomeBounds
          .insetBy(dx: -0.10, dy: -0.10)
          .contains(nextItem.action.focusPoint)
        let nextInSameNeighborhood = hypot(
          nextFraming.center.x - framing.center.x,
          nextFraming.center.y - framing.center.y
        ) <= 0.18

        // Direct link when:
        // 1. The user's next click directly acts on this outcome (e.g. click Close -> click "Don't Save"), OR
        // 2. The user immediately clicks another control in the same neighborhood (e.g. sidebar buttons),
        //    so we never yank away to a remote preview refresh for 200ms only to yank right back.
        shouldLinkDirectlyToNext = nextInsideOutcome
          || outcomeToNextDist <= 0.24
          || (timeToNext <= 1.65 && nextInSameNeighborhood)
      } else {
        shouldLinkDirectlyToNext = false
      }

      switch item.outcome.kind {
      case .localNearClick:
        if shouldLinkDirectlyToNext {
          let causeHold = min(outcomeCeiling, action.endTime + 0.24)
          if causeHold > (keyframes.last?.time ?? startTime) + 0.06 {
            appendKeyframe(time: causeHold, center: framing.center, zoom: framing.zoom)
          }
        } else {
          var combinedBounds = item.outcome.outcomeBounds.union(CGRect(origin: action.endPoint, size: .zero))
          if let followBounds = action.followThroughBounds {
            combinedBounds = combinedBounds.union(followBounds)
          }
          let outcomeCenter = CGPoint(
            x: action.endPoint.x * 0.30 + item.outcome.outcomeCentroid.x * 0.70,
            y: action.endPoint.y * 0.30 + item.outcome.outcomeCentroid.y * 0.70
          )
          let outcomeZoom = fitZoom(for: combinedBounds, maxZoom: framing.zoom, minZoom: style.minOutcomeZoom)
          let reframeTime = min(outcomeCeiling, action.endTime + 0.42)
          let hasEnoughDwell = nextItem == nil || outcomeCeiling >= reframeTime + 0.55
          if hasEnoughDwell {
            appendKeyframe(time: reframeTime, center: outcomeCenter, zoom: outcomeZoom)
            if outcomeCeiling > reframeTime + 0.12 {
              appendKeyframe(time: outcomeCeiling, center: outcomeCenter, zoom: outcomeZoom)
            }
          } else if outcomeCeiling > (keyframes.last?.time ?? startTime) + 0.08 {
            appendKeyframe(time: outcomeCeiling, center: framing.center, zoom: framing.zoom)
          }
        }

      case .localRemoteResult:
        if shouldLinkDirectlyToNext {
          // Hold briefly on the trigger click so cause is clear, then let the next iteration glide
          // in ONE unbroken monotonic curve directly onto the next action.
          let causeHold = min(outcomeCeiling, action.endTime + 0.24)
          if causeHold > (keyframes.last?.time ?? startTime) + 0.06 {
            appendKeyframe(time: causeHold, center: framing.center, zoom: framing.zoom)
          }
        } else {
          let causeHoldTime = min(outcomeCeiling, action.endTime + 0.32)
          let outcomeZoom = fitZoom(for: item.outcome.outcomeBounds, maxZoom: framing.zoom, minZoom: style.minOutcomeZoom)
          let panArriveTime = min(outcomeCeiling, causeHoldTime + 0.46)
          let hasEnoughDwell = nextItem == nil || outcomeCeiling >= panArriveTime + 0.55
          if hasEnoughDwell && panArriveTime > causeHoldTime + 0.08 {
            appendKeyframe(time: causeHoldTime, center: framing.center, zoom: framing.zoom)
            appendKeyframe(time: panArriveTime, center: item.outcome.outcomeCentroid, zoom: outcomeZoom)
            if outcomeCeiling > panArriveTime + 0.12 {
              appendKeyframe(time: outcomeCeiling, center: item.outcome.outcomeCentroid, zoom: outcomeZoom)
            }
          } else if outcomeCeiling > (keyframes.last?.time ?? startTime) + 0.08 {
            appendKeyframe(time: outcomeCeiling, center: framing.center, zoom: framing.zoom)
          }
        }

      case .fullScreenTransition:
        if outcomeCeiling > (keyframes.last?.time ?? startTime) + 0.08 {
          appendKeyframe(time: outcomeCeiling, center: framing.center, zoom: framing.zoom)
        }

      case .none:
        // Even without video-frame visual delta, follow-through menu scanning lets us reframe smoothly
        // when there is real dwell time (never a head-fake right before the next click).
        if !shouldLinkDirectlyToNext,
           let followBounds = action.followThroughBounds,
           max(followBounds.width, followBounds.height) > 0.05 {
          let followCenter = CGPoint(x: followBounds.midX, y: followBounds.midY)
          let followZoom = fitZoom(for: followBounds, maxZoom: framing.zoom, minZoom: style.minOutcomeZoom)
          let reframeTime = min(outcomeCeiling, action.endTime + 0.45)
          let hasEnoughDwell = nextItem == nil || outcomeCeiling >= reframeTime + 0.55
          if hasEnoughDwell {
            appendKeyframe(time: reframeTime, center: followCenter, zoom: followZoom)
            if outcomeCeiling > reframeTime + 0.10 {
              appendKeyframe(time: outcomeCeiling, center: followCenter, zoom: followZoom)
            }
          } else if outcomeCeiling > (keyframes.last?.time ?? startTime) + 0.08 {
            appendKeyframe(time: outcomeCeiling, center: framing.center, zoom: framing.zoom)
          }
        } else {
          let isLargeDrag = action.kind == .drag && dragSpan > 0.14
          let holdCenter = isLargeDrag ? action.endPoint : framing.center
          let holdZoom = isLargeDrag
            ? fitZoom(for: action.bounds, maxZoom: framing.zoom, minZoom: style.minOutcomeZoom)
            : framing.zoom
          if outcomeCeiling > (keyframes.last?.time ?? startTime) + 0.10 {
            appendKeyframe(time: outcomeCeiling, center: holdCenter, zoom: holdZoom)
          }
        }
      }
    }

    // Hold final pose smoothly through zoom-out tail so exit is pure straight-ray optical reveal.
    if let lastKey = keyframes.last, endTime > lastKey.time + 0.02 {
      keyframes.append(
        AutoFocusCameraSample(
          time: endTime,
          center: lastKey.center,
          zoomMultiplier: lastKey.zoomMultiplier
        )
      )
    }

    return ZoomSegment(
      startTime: startTime,
      duration: segmentDuration,
      zoomLevel: chapterZoom,
      zoomCenter: firstTarget.center,
      zoomType: .auto,
      followSpeed: AutoFocusSettings.defaultFollowSpeed,
      focusMargin: AutoFocusSettings.defaultFocusMargin,
      isEnabled: true,
      smartKeyframes: keyframes
    )
  }

  private static func downsampleWaypoints(
    _ waypoints: [(time: TimeInterval, point: CGPoint)],
    maxCount: Int
  ) -> [(time: TimeInterval, point: CGPoint)] {
    guard waypoints.count > maxCount, maxCount >= 2 else { return waypoints }
    var result: [(time: TimeInterval, point: CGPoint)] = []
    result.reserveCapacity(maxCount)
    let lastIndex = waypoints.count - 1
    for step in 0 ..< maxCount {
      let idx = Int((Double(step) * Double(lastIndex) / Double(maxCount - 1)).rounded())
      result.append(waypoints[idx])
    }
    return result
  }

  private static func actionFraming(
    for action: DetectedAction,
    desiredZoom: CGFloat,
    style: SmartAutoZoomStyle
  ) -> (center: CGPoint, zoom: CGFloat) {
    // Small slider/control drags frame the control's midpoint directly so the camera stays rock-steady.
    let rawCenter: CGPoint
    if action.kind == .drag, hypot(action.bounds.width, action.bounds.height) <= 0.14 {
      rawCenter = CGPoint(x: action.bounds.midX, y: action.bounds.midY)
    } else {
      rawCenter = action.focusPoint
    }
    // Gentle 14% comfort pull toward screen center gives edge/toolbar controls natural breathing room.
    let contextBiased = CGPoint(
      x: rawCenter.x * 0.86 + 0.5 * 0.14,
      y: rawCenter.y * 0.86 + 0.5 * 0.14
    )
    let clamped = clampedCameraCenter(contextBiased, for: desiredZoom)
    return (clamped, desiredZoom.clamped(to: style.minOutcomeZoom ... ZoomSegment.maxZoomLevel))
  }

  /// Computes the tightest zoom level that frames `rect` comfortably with 22% breathing margin.
  static func fitZoom(
    for rect: CGRect,
    maxZoom: CGFloat,
    minZoom: CGFloat
  ) -> CGFloat {
    guard rect.width > 0.01 || rect.height > 0.01 else { return maxZoom }
    let marginFactor: CGFloat = 0.76
    let zoomX = rect.width > 0.01 ? (marginFactor / rect.width) : maxZoom
    let zoomY = rect.height > 0.01 ? (marginFactor / rect.height) : maxZoom
    return min(zoomX, zoomY).clamped(to: minZoom ... max(minZoom, maxZoom))
  }

  private static func clampedCameraCenter(_ center: CGPoint, for zoomLevel: CGFloat) -> CGPoint {
    let half = 0.5 / max(zoomLevel, 1.0)
    return CGPoint(
      x: center.x.clamped(to: half ... (1.0 - half)),
      y: center.y.clamped(to: half ... (1.0 - half))
    )
  }

  private static func resolveNonOverlappingSegments(
    _ segments: [ZoomSegment],
    duration: TimeInterval
  ) -> [ZoomSegment] {
    let sorted = segments.sorted { $0.startTime < $1.startTime }
    var resolved: [ZoomSegment] = []
    let minGap: TimeInterval = 0.22
    let minDuration: TimeInterval = duration >= 1.5 ? 1.15 : ZoomSegment.minDuration

    for var segment in sorted {
      segment = segment.clamped(to: duration)
      if let previous = resolved.last {
        let minStart = previous.endTime + minGap
        if segment.startTime < minStart {
          let shift = minStart - segment.startTime
          if segment.duration - shift >= minDuration {
            segment.startTime = minStart
            segment.duration -= shift
          } else {
            var trimmedPrev = previous
            let availableEnd = segment.startTime - minGap
            if availableEnd - trimmedPrev.startTime >= minDuration {
              trimmedPrev.duration = availableEnd - trimmedPrev.startTime
              resolved[resolved.count - 1] = trimmedPrev
            } else {
              continue
            }
          }
        }
      }
      if segment.duration >= minDuration && segment.startTime < duration {
        resolved.append(segment)
      }
    }

    return resolved
  }

  // MARK: - Telemetry Helpers

  private static func canonicalSamples(from metadata: RecordingMetadata) -> [CanonicalSample] {
    metadata.mouseSamples
      .sorted { $0.time < $1.time }
      .map { sample in
        let y: CGFloat = switch metadata.coordinateSpace {
        case .topLeftNormalized: sample.normalizedY
        case .bottomLeftNormalized: 1.0 - sample.normalizedY
        }
        return CanonicalSample(
          time: sample.time,
          point: CGPoint(x: sample.normalizedX, y: y).clampedToUnit,
          isInsideCapture: sample.isInsideCapture
        )
      }
  }

  private static func samplePoint(at time: TimeInterval, in samples: [CanonicalSample]) -> CGPoint? {
    guard let first = samples.first, let last = samples.last else { return nil }
    if time <= first.time { return first.point }
    if time >= last.time { return last.point }
    var low = 0
    var high = samples.count - 1
    while high - low > 1 {
      let mid = (low + high) / 2
      if samples[mid].time <= time { low = mid } else { high = mid }
    }
    let a = samples[low]
    let b = samples[high]
    let span = max(b.time - a.time, 0.0001)
    let t = CGFloat(((time - a.time) / span).clamped(to: 0 ... 1))
    return CGPoint(
      x: a.point.x + (b.point.x - a.point.x) * t,
      y: a.point.y + (b.point.y - a.point.y) * t
    )
  }

  private static func didCursorLeaveCapture(
    from start: TimeInterval,
    to end: TimeInterval,
    samples: [CanonicalSample]
  ) -> Bool {
    guard end > start + 0.5 else { return false }
    var outsideStart: TimeInterval?
    for sample in samples where sample.time >= start && sample.time <= end {
      if !sample.isInsideCapture {
        if let s = outsideStart {
          if sample.time - s >= 0.85 { return true }
        } else {
          outsideStart = sample.time
        }
      } else {
        outsideStart = nil
      }
    }
    return false
  }

  private static func inferredDuration(from metadata: RecordingMetadata) -> TimeInterval {
    let mouseMax = metadata.mouseSamples.map(\.time).max() ?? 0
    let clickMax = metadata.cursorCapture?.clicks.map(\.time).max() ?? 0
    return max(mouseMax, clickMax)
  }
}

private nonisolated extension CGPoint {
  var clampedToUnit: CGPoint {
    CGPoint(
      x: x.clamped(to: 0 ... 1),
      y: y.clamped(to: 0 ... 1)
    )
  }
}

private nonisolated extension CGFloat {
  func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}

private nonisolated extension Double {
  func clamped(to range: ClosedRange<Double>) -> Double {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}
