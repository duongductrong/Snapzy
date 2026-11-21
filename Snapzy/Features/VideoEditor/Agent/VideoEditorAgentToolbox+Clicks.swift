//
//  VideoEditorAgentToolbox+Clicks.swift
//  Snapzy
//
//  Clicks a Studio recording captured (`RecordingCursorCapture.clicks`), for the agent:
//  get_activity lists them, auto_zoom_activity(source: clicks) zooms on bursts of them,
//  and speed_up_idle never speeds up a moment where the user clicks without moving.
//  Clicks are recording time with a top-left normalized point, the zoom-center space.
//

import CoreGraphics
import Foundation

/// A click placed on the structural timeline.
nonisolated struct VideoEditorTimelineClick: Equatable {
  let time: TimeInterval
  let point: CGPoint
}

/// Clicks close in time and place: one zoom's worth of work.
nonisolated struct VideoEditorClickBurst: Equatable {
  let start: TimeInterval
  let end: TimeInterval
  let bounds: CGRect
  let count: Int
}

extension VideoEditorAgentToolbox {
  nonisolated static let clickZoomDefaults = (lead: 0.6, hold: 1.2, gap: 1.5)
  /// A click keeps the moment around it out of idle stretches.
  nonisolated static let clickIdleMargin: TimeInterval = 0.5

  /// Mouse-down clicks on the playing recording footage, in timeline order.
  func timelineClicks(_ state: VideoEditorState) -> [VideoEditorTimelineClick] {
    Self.timelineClicks(recordedClickDowns(state), placements: state.placements)
  }

  nonisolated static func timelineClicks(
    _ clicks: [RecordedClick],
    placements: [TimelineSequence.Placement]
  ) -> [VideoEditorTimelineClick] {
    var result: [VideoEditorTimelineClick] = []
    for placement in placements where placement.clip.isPrimary {
      let low = max(placement.sourceAxisStart, placement.clip.sourceStart)
      let high = min(placement.sourceAxisEnd, placement.clip.sourceEnd)
      for click in clicks where click.time >= low && click.time < high {
        result.append(.init(time: placement.sequenceTime(atSource: click.time), point: click.normalizedPoint))
      }
    }
    return result.sorted { $0.time < $1.time }
  }

  /// Groups clicks less than `gap` apart whose points stay inside a `maxArea` square.
  nonisolated static func clickBursts(
    _ clicks: [VideoEditorTimelineClick],
    gap: TimeInterval = clickZoomDefaults.gap,
    maxArea: CGFloat = CGFloat(autoZoomDefaults.maxArea)
  ) -> [VideoEditorClickBurst] {
    var bursts: [VideoEditorClickBurst] = []
    var current: (start: TimeInterval, end: TimeInterval, bounds: CGRect, count: Int)?
    for click in clicks {
      let spot = CGRect(origin: click.point, size: .zero)
      if var open = current, click.time - open.end <= gap {
        let grown = open.bounds.union(spot)
        if grown.width <= maxArea, grown.height <= maxArea {
          open.end = click.time
          open.bounds = grown
          open.count += 1
          current = open
          continue
        }
      }
      if let open = current { bursts.append(.init(start: open.start, end: open.end, bounds: open.bounds, count: open.count)) }
      current = (click.time, click.time, spot, 1)
    }
    if let open = current { bursts.append(.init(start: open.start, end: open.end, bounds: open.bounds, count: open.count)) }
    return bursts
  }

  /// Zoom candidates around each burst: a short lead-in, a hold after the last click,
  /// centered on where the clicks land. Weight = clicks, so busy bursts win a limit.
  func clickZoomCandidates(
    _ state: VideoEditorState,
    window: ClosedRange<TimeInterval>,
    total: TimeInterval
  ) -> [(range: ClosedRange<TimeInterval>, weight: TimeInterval, center: CGPoint?)] {
    let clicks = timelineClicks(state).filter { window.contains($0.time) }
    return Self.clickBursts(clicks).map { burst in
      let start = max(0, burst.start - Self.clickZoomDefaults.lead)
      let end = min(total, max(burst.end + Self.clickZoomDefaults.hold, start + ZoomSegment.minDuration))
      return (start ... end, TimeInterval(burst.count), CGPoint(x: burst.bounds.midX, y: burst.bounds.midY))
    }
  }

  /// Idle timeline stretches minus a margin around every click (a click is activity).
  func idleWithoutClicks(_ idle: [ClosedRange<TimeInterval>], _ state: VideoEditorState) -> [ClosedRange<TimeInterval>] {
    let clicks = timelineClicks(state)
    guard !clicks.isEmpty else { return idle }
    let busy = clicks.map { max(0, $0.time - Self.clickIdleMargin) ... ($0.time + Self.clickIdleMargin) }
    return VideoEditorAgentAnalyzer.subtract(idle, busy)
      .filter { $0.upperBound - $0.lowerBound >= VideoEditorAgentAnalyzer.minimumSpan }
  }

  /// get_activity's click list, capped; nil when the recording has no click data.
  func clickActivityPayload(_ state: VideoEditorState, window: ClosedRange<TimeInterval>) -> [String: Any]? {
    guard state.recordingMetadata?.cursorCapture != nil else { return nil }
    let clicks = timelineClicks(state).filter { window.contains($0.time) }
    let listed = clicks.prefix(VideoEditorAgentStudioTools.maximumListedClicks)
    var payload: [String: Any] = [
      "clicks": listed.map { click -> [String: Any] in
        ["time": Self.round(click.time), "at": [Self.round(click.point.x), Self.round(click.point.y)]]
      },
    ]
    if clicks.count > listed.count { payload["omitted_clicks"] = clicks.count - listed.count }
    return payload
  }
}
