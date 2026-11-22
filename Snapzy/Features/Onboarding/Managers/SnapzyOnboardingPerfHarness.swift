//
//  SnapzyOnboardingPerfHarness.swift
//  Snapzy
//
//  DEBUG-only, opt-in autopilot that drives the onboarding step transitions on a fixed script and
//  records display-link frame pacing for each one, so before/after measurements are repeatable.
//
//  Enable with `SNAPZY_ONBOARDING_PERF=1` (resume onto a saved step so Welcome is skipped).
//  Optional: `SNAPZY_ONBOARDING_PERF_OUT=/path/report.json` (also writes `report.json.txt`) and
//  `SNAPZY_ONBOARDING_PERF_ROUNDS=<n>` (default 2). The app exits when the script completes.
//
//  Frame intervals are measured on the main run loop, so they capture main-thread stalls and
//  render-server back-pressure that delays the main thread; pair with Instruments for GPU time.
//

#if DEBUG
import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class SnapzyOnboardingPerfHarness: NSObject {
  static var isRequested: Bool {
    ProcessInfo.processInfo.environment["SNAPZY_ONBOARDING_PERF"] == "1"
  }

  private static var current: SnapzyOnboardingPerfHarness?

  static func startIfRequested(state: SnapzyOnboardingState) {
    guard isRequested, current == nil else { return }
    let harness = SnapzyOnboardingPerfHarness(state: state)
    current = harness
    harness.run()
  }

  private struct Segment: Codable {
    var name: String
    var frames: Int
    var durationMs: Double
    var expectedIntervalMs: Double
    var avgFps: Double
    var worstFrameMs: Double
    var p95FrameMs: Double
    var hitches: Int
    var hitchTimeMs: Double
  }

  private let state: SnapzyOnboardingState
  private var link: AnyObject?
  private var lastTimestamp: CFTimeInterval?
  private var intervals: [Double] = []
  private var expectedIntervals: [Double] = []
  private var segments: [Segment] = []

  private init(state: SnapzyOnboardingState) {
    self.state = state
  }

  private func run() {
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(2.5))
      startLink()

      // Each step change is measured over a window that covers its longest animation tail.
      let window = 1.4
      let rounds = Int(ProcessInfo.processInfo.environment["SNAPZY_ONBOARDING_PERF_ROUNDS"] ?? "") ?? 2
      for _ in 0..<rounds {
        await measure("1→2", window) { self.state.transition(to: .quickAccess) }
        // Leave step 2 in its richest stage (video editor playing) so the departing Space is busy.
        self.state.simulateStartPrerecord()
        self.state.openVideoEditorFromQuickAccess()
        try? await Task.sleep(for: .seconds(1.0))
        await measure("2→3", window) { self.state.transition(to: .shortcuts) }
        await measure("idle@3", 2.0) {}
        await measure("3→4", window) { self.state.transition(to: .permissions) }
        await measure("4→3", window) { self.state.transition(to: .shortcuts) }
        await measure("3→2", window) { self.state.transition(to: .quickAccess) }
        await measure("2→1", window) { self.state.transition(to: .meetSnapzy) }
        await measure("1→3 (jump)", window) { self.state.transition(to: .shortcuts) }
        await measure("3→1 (jump)", window) { self.state.transition(to: .meetSnapzy) }
      }

      finish()
    }
  }

  private func measure(_ name: String, _ seconds: Double, _ action: () -> Void) async {
    intervals.removeAll(keepingCapacity: true)
    expectedIntervals.removeAll(keepingCapacity: true)
    lastTimestamp = nil
    action()
    try? await Task.sleep(for: .seconds(seconds))
    segments.append(summarize(name))
    // Let everything settle before the next step so segments do not bleed into each other.
    try? await Task.sleep(for: .seconds(0.6))
  }

  private func summarize(_ name: String) -> Segment {
    let sortedExpected = expectedIntervals.sorted()
    let expected = sortedExpected.isEmpty ? (1.0 / 120.0) : sortedExpected[sortedExpected.count / 2]
    let sorted = intervals.sorted()
    let total = intervals.reduce(0, +)
    // A hitch is any frame interval that ran past 1.5× the display's refresh interval.
    let late = intervals.filter { $0 > expected * 1.5 }
    let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
    return Segment(
      name: name,
      frames: intervals.count,
      durationMs: total * 1000,
      expectedIntervalMs: expected * 1000,
      avgFps: total > 0 ? Double(intervals.count) / total : 0,
      worstFrameMs: (sorted.last ?? 0) * 1000,
      p95FrameMs: p95 * 1000,
      hitches: late.count,
      hitchTimeMs: late.reduce(0) { $0 + ($1 - expected) } * 1000
    )
  }

  private func startLink() {
    guard #available(macOS 14.0, *), let screen = NSScreen.main else { return }
    let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  @available(macOS 14.0, *)
  @objc private func tick(_ link: CADisplayLink) {
    if let lastTimestamp {
      intervals.append(link.timestamp - lastTimestamp)
      expectedIntervals.append(link.targetTimestamp - link.timestamp)
    }
    lastTimestamp = link.timestamp
  }

  private func finish() {
    if #available(macOS 14.0, *) { (link as? CADisplayLink)?.invalidate() }
    link = nil

    var lines = ["segment            frames  avgFps  p95ms  worstms  hitches  hitchms"]
    for s in segments {
      lines.append(
        s.name.padding(toLength: 18, withPad: " ", startingAt: 0)
          + String(
            format: "%7d  %6.1f  %5.1f  %7.1f  %7d  %7.1f",
            s.frames, s.avgFps, s.p95FrameMs, s.worstFrameMs, s.hitches, s.hitchTimeMs
          )
      )
    }
    let table = lines.joined(separator: "\n")
    print("[OnboardingPerf]\n" + table)

    if let path = ProcessInfo.processInfo.environment["SNAPZY_ONBOARDING_PERF_OUT"] {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted]
      if let data = try? encoder.encode(segments) {
        try? data.write(to: URL(fileURLWithPath: path))
      }
      try? table.write(to: URL(fileURLWithPath: path + ".txt"), atomically: true, encoding: .utf8)
    }

    exit(0)
  }
}
#endif
