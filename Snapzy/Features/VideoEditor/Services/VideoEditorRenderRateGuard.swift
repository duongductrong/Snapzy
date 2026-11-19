//
//  VideoEditorRenderRateGuard.swift
//  Snapzy
//
//  DEBUG-only tripwire for editor-wide re-render storms during playback.
//

import Foundation

/// Counts `body` evaluations of editor-wide views and logs once per window when they run
/// at playback rate. Views that observe the whole `VideoEditorState` should re-render only
/// on real edits; if one starts running ~30×/s while playing, some hot path (tick, scrub,
/// seek) is publishing state it didn't change. Release builds compile this to nothing.
@MainActor
enum VideoEditorRenderRateGuard {
  /// Above this many evaluations per second while playing, something is publishing per tick.
  static let maxBodiesPerSecond = 5

  #if DEBUG
  private struct Window {
    var start: TimeInterval
    var count: Int
    var reported: Bool
  }

  private static var windows: [String: Window] = [:]
  #endif

  @inline(__always)
  static func record(_ view: StaticString, isPlaying: Bool) {
    #if DEBUG
    let key = "\(view)"
    let now = ProcessInfo.processInfo.systemUptime
    var window = windows[key] ?? Window(start: now, count: 0, reported: false)
    if now - window.start >= 1 {
      window = Window(start: now, count: 0, reported: false)
    }
    window.count += 1
    if isPlaying, window.count > maxBodiesPerSecond, !window.reported {
      window.reported = true
      DiagnosticLogger.shared.log(
        .warning,
        .editor,
        "Editor-wide view re-rendering at playback rate",
        context: ["view": key, "bodiesPerSecond": "\(window.count)+"]
      )
    }
    windows[key] = window
    #endif
  }
}
