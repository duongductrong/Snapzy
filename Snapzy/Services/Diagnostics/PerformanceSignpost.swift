//
//  PerformanceSignpost.swift
//  Snapzy
//
//  Helper for performance measurements using OSSignposter.
//

import Foundation
import os

@available(macOS 12.0, *)
nonisolated private let poster = OSSignposter(subsystem: "com.snapzy.perf", category: "annotate-return")

@available(macOS 12.0, *)
nonisolated private let capturePassthroughPoster = OSSignposter(
  subsystem: Bundle.main.bundleIdentifier ?? "com.snapzy.perf",
  category: "CapturePassthrough"
)

@available(macOS 12.0, *)
nonisolated private let videoEditorPoster = OSSignposter(
  subsystem: Bundle.main.bundleIdentifier ?? "com.snapzy.perf",
  category: "VideoEditor"
)

/// Read once per process: signposts are a DEBUG profiling aid, so a relaunch is an
/// acceptable cost for toggling — and the event-tap callback must not hit UserDefaults
/// on every mouse event.
nonisolated private let signpostsEnabled = UserDefaults.standard.bool(forKey: "perf.signposts")

enum PerfSignpost {
  /// Intervals only: avoid formatting/logging text in high-frequency input paths.
  enum VideoEditor {
    #if DEBUG
    @available(macOS 12.0, *)
    struct Interval {
      let name: StaticString
      let state: OSSignpostIntervalState
    }
    #endif

    nonisolated static func beginInterval(_ name: StaticString) -> Any? {
      #if DEBUG
      if #available(macOS 12.0, *), signpostsEnabled {
        return Interval(name: name, state: videoEditorPoster.beginInterval(name))
      }
      #endif
      return nil
    }

    nonisolated static func endInterval(_ interval: Any?) {
      #if DEBUG
      if #available(macOS 12.0, *), let interval = interval as? Interval {
        videoEditorPoster.endInterval(interval.name, interval.state)
      }
      #endif
    }

    nonisolated static func event(_ name: StaticString) {
      #if DEBUG
      if #available(macOS 12.0, *), signpostsEnabled {
        videoEditorPoster.emitEvent(name)
      }
      #endif
    }
  }

  #if DEBUG
  @available(macOS 12.0, *)
  struct Interval {
    let name: StaticString
    let state: OSSignpostIntervalState
  }
  #endif

  nonisolated static func beginInterval(_ name: StaticString) -> Any? {
    #if DEBUG
    if #available(macOS 12.0, *) {
      if signpostsEnabled {
        let state = poster.beginInterval(name)
        return Interval(name: name, state: state)
      }
    }
    #endif
    return nil
  }

  nonisolated static func endInterval(_ interval: Any?) {
    #if DEBUG
    if #available(macOS 12.0, *) {
      if let iv = interval as? Interval {
        poster.endInterval(iv.name, iv.state)
      }
    }
    #endif
  }

  nonisolated static func event(_ name: StaticString) {
    #if DEBUG
    if #available(macOS 12.0, *) {
      if signpostsEnabled {
        poster.emitEvent(name)
      }
    }
    #endif
  }

  @discardableResult
  nonisolated static func measure<T>(_ name: StaticString, _ body: () -> T) -> T {
    #if DEBUG
    if #available(macOS 12.0, *) {
      if signpostsEnabled {
        let start = CFAbsoluteTimeGetCurrent()
        let state = poster.beginInterval(name)
        defer {
          poster.endInterval(name, state)
          let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
          DiagnosticLogger.shared.log(.debug, .ui, "Performance [\(name)]: \(String(format: "%.2f", elapsed))ms")
        }
        return body()
      }
    }
    #endif
    return body()
  }

  /// Signposts for the live-capture passthrough input path (event tap → overlay update).
  /// Same DEBUG-only `perf.signposts` gate as the annotate poster above; point Instruments
  /// at subsystem = bundle id, category "CapturePassthrough".
  enum CapturePassthrough {
    #if DEBUG
    @available(macOS 12.0, *)
    struct Interval {
      let name: StaticString
      let state: OSSignpostIntervalState
    }
    #endif

    nonisolated static func beginInterval(_ name: StaticString) -> Any? {
      #if DEBUG
      if #available(macOS 12.0, *) {
        if signpostsEnabled {
          let state = capturePassthroughPoster.beginInterval(name)
          return Interval(name: name, state: state)
        }
      }
      #endif
      return nil
    }

    nonisolated static func endInterval(_ interval: Any?) {
      #if DEBUG
      if #available(macOS 12.0, *) {
        if let iv = interval as? Interval {
          capturePassthroughPoster.endInterval(iv.name, iv.state)
        }
      }
      #endif
    }

    nonisolated static func event(_ name: StaticString) {
      #if DEBUG
      if #available(macOS 12.0, *) {
        if signpostsEnabled {
          capturePassthroughPoster.emitEvent(name)
        }
      }
      #endif
    }
  }
}
