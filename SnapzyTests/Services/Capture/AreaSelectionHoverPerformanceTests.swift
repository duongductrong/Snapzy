//
//  AreaSelectionHoverPerformanceTests.swift
//  SnapzyTests
//
//  Main-thread cost harness for the capture-mode hover hot path (crosshair /
//  coordinate indicator). Drives the production per-tick code — a real session
//  via the shared `AreaSelectionController`, the pooled overlay window, and the
//  same view entry points the event tap / window events use — and reports
//  per-tick wall time. Local-only: presents real overlay windows, so it is
//  skipped on CI like the other session tests.
//
//  Two samples are reported per scenario:
//  - `sync`: work done inline inside the event delivery call itself.
//  - `tick`: `sync` + work the tick enqueues on the main queue for the next
//    run-loop pass (e.g. the presentation watchdog's WindowServer check),
//    drained via a non-blocking run-loop pass — the full per-tick main-thread
//    footprint a fast mouse can produce.
//

import CoreGraphics
@testable import Snapzy
import XCTest

final class AreaSelectionHoverPerformanceTests: XCTestCase {
  private let iterations = 240

  override func tearDown() {
    AreaSelectionController.shared.cancelSelection()
    restoreHostAppActivation()
    super.tearDown()
  }

  /// Legacy window-event input: `mouseMoved` on the pooled overlay view, the path
  /// used when the capture event tap is unavailable (no Accessibility trust).
  func testHoverTickCost_windowEventPath() throws {
    try skipIfRunningInCI(
      "Presents real overlay windows via the shared AreaSelectionController, which is flaky on headless CI runners"
    )
    let (window, overlay) = try makeLiveSession(forcePassthrough: false)
    overlay.testMouseLocationOverride = CGPoint(x: window.frame.midX, y: window.frame.midY)

    var sync: [Double] = []
    var tick: [Double] = []
    for index in 0 ..< iterations {
      let point = walkPoint(index: index, in: overlay.bounds)
      guard let event = NSEvent.mouseEvent(
        with: .mouseMoved,
        location: point,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: index,
        clickCount: 0,
        pressure: 0
      ) else {
        XCTFail("Failed to synthesize mouse-moved event")
        return
      }
      measureTick(sync: &sync, tick: &tick) {
        overlay.mouseMoved(with: event)
      }
    }
    report(label: "windowEventPath", sync: sync, tick: tick)
  }

  /// Live-passthrough input: the event-tap-driven path used by default for area
  /// screenshots. The view-level entry point is the same one
  /// `processLivePassthroughHover` calls after the display-rate gate.
  func testHoverTickCost_livePassthroughPath() throws {
    emit("[PERF] starting livePassthroughPath")
    do {
      try skipIfRunningInCI(
        "Presents real overlay windows via the shared AreaSelectionController, which is flaky on headless CI runners"
      )
      let (window, overlay) = try makeLiveSession(forcePassthrough: true)

      var sync: [Double] = []
      var tick: [Double] = []
      for index in 0 ..< iterations {
        let local = walkPoint(index: index, in: overlay.bounds)
        let screenPoint = CGPoint(x: window.frame.minX + local.x, y: window.frame.minY + local.y)
        measureTick(sync: &sync, tick: &tick) {
          overlay.handleLivePassthroughMouseMoved(atScreenPoint: screenPoint)
        }
      }
      report(label: "livePassthroughPath", sync: sync, tick: tick)
    } catch {
      emit("[PERF] livePassthroughPath aborted: \(error)")
      throw error
    }
  }

  /// Drag hot path. Unlike hover — which only touches the overlay under the pointer —
  /// `renderManualSelectionIfNeeded()` fans every pointer event out to *all* pooled windows, so
  /// this cost scales with attached display count. Reports the display count alongside the timing
  /// so a single-display run and a multi-display run are comparable.
  func testDragTickCost_multiDisplayFanOut() throws {
    try skipIfRunningInCI(
      "Presents real overlay windows via the shared AreaSelectionController, which is flaky on headless CI runners"
    )
    let (window, overlay) = try makeLiveSession(forcePassthrough: true)

    // Begin a real manual selection so the drag path (not the hover path) is what gets measured.
    overlay.handleLivePassthroughMouseDown(
      atScreenPoint: CGPoint(x: window.frame.midX, y: window.frame.midY)
    )

    var sync: [Double] = []
    var tick: [Double] = []
    for index in 0 ..< iterations {
      let local = walkPoint(index: index, in: overlay.bounds)
      let screenPoint = CGPoint(x: window.frame.minX + local.x, y: window.frame.minY + local.y)
      measureTick(sync: &sync, tick: &tick) {
        overlay.handleLivePassthroughMouseDragged(atScreenPoint: screenPoint)
      }
    }
    report(label: "dragFanOut(displays=\(NSScreen.screens.count))", sync: sync, tick: tick)
  }

  /// Attribution probe: the presentation watchdog runs this WindowServer query
  /// whenever it is (re-)armed; the hover path re-arms it per tick while the app
  /// is inactive, so its standalone cost is reported for comparison against the
  /// per-tick totals above.
  func testWindowServerOnScreenWindowListQueryCost() throws {
    try skipIfRunningInCI("WindowServer query timing is meaningless on headless CI runners")
    var samples: [Double] = []
    for _ in 0 ..< 100 {
      let start = CFAbsoluteTimeGetCurrent()
      _ = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
      samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
    emit("[PERF] windowServerOnScreenWindowListQuery: \(describe(samples))")
  }

  // MARK: - Harness

  /// Start a real live (backdrop-less) screenshot session and return a pooled
  /// window with its overlay, settled so session-start async work (lazy backdrop
  /// capture, initial watchdog pass) does not pollute the measured loop.
  ///
  /// Production live sessions run with Snapzy INACTIVE (a menu-bar agent that
  /// deliberately never activates mid-capture), and the hover path behaves
  /// differently in that state — so the harness hands activation to another app
  /// (windows stay visible, matching production) instead of measuring the cheap
  /// active-app path the test host happens to boot into.
  private func makeLiveSession(
    forcePassthrough: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws -> (AreaSelectionWindow, AreaSelectionOverlayView) {
    // Deactivate BEFORE starting the session: production live sessions both start
    // and run with Snapzy inactive (a menu-bar agent triggered via global shortcut),
    // and the hover path behaves differently in that state. Starting the session
    // first would also fight the freshly-launched host's sticky launch activation.
    try makeHostAppInactive(file: file, line: line)

    let controller = AreaSelectionController.shared
    controller.startSelection(mode: .screenshot, backdrops: [:]) { _ in }

    guard let window = pooledWindow() else {
      controller.cancelSelection()
      throw XCTSkip("no pooled AreaSelectionWindow (headless host with no screens)", file: file, line: line)
    }
    window.setLivePassthroughInputEnabled(forcePassthrough)

    // Settle: drain session-start async work, then warm the measured path so
    // first-touch costs (font caches, cursor realization, layer realization)
    // land outside the measured samples.
    let settleDeadline = Date().addingTimeInterval(0.9)
    while Date() < settleDeadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    for index in 0 ..< 10 {
      let local = walkPoint(index: index, in: window.overlayView.bounds)
      if forcePassthrough {
        let screenPoint = CGPoint(x: window.frame.minX + local.x, y: window.frame.minY + local.y)
        window.overlayView.handleLivePassthroughMouseMoved(atScreenPoint: screenPoint)
      } else if let event = NSEvent.mouseEvent(
        with: .mouseMoved,
        location: local,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: index,
        clickCount: 0,
        pressure: 0
      ) {
        window.overlayView.mouseMoved(with: event)
      }
      RunLoop.current.run(until: Date())
    }
    emit("[PERF] host: NSApp.isActive=\(NSApp.isActive) screens=\(NSScreen.screens.count)")
    return (window, window.overlayView)
  }

  /// Hand activation to another app so `NSApp.isActive` flips false while our
  /// windows stay visible — the exact state production live-capture sessions run
  /// in. Skips the test when no other app accepts activation (unlikely locally).
  private func makeHostAppInactive(
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    guard NSApp.isActive else { return }
    // Finder reliably accepts and keeps activation; a generic "first regular app"
    // scan can land on background-only apps whose activation immediately bounces
    // back, making the harness flaky.
    let ownPID = ProcessInfo.processInfo.processIdentifier
    let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
    let other = finder ?? NSWorkspace.shared.runningApplications.first {
      $0.processIdentifier != ownPID
        && $0.activationPolicy == .regular
        && !$0.isTerminated
    }
    guard let other else {
      throw XCTSkip("no other regular app available to take activation", file: file, line: line)
    }
    // Retry the handoff: right after the test host launches, the first activation
    // request can be ignored while the system settles the just-activated app.
    let deadline = Date().addingTimeInterval(8)
    while NSApp.isActive, Date() < deadline {
      other.activate()
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    if NSApp.isActive {
      // Bounce: re-assert our own activation, then hand off again. A freshly
      // launched host reliably ignores foreign activations until it has gone
      // through one explicit re-activation (mirrors the teardown→setup sequence
      // that later tests in the process benefit from).
      NSApp.activate(ignoringOtherApps: true)
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
      let retryDeadline = Date().addingTimeInterval(6)
      while NSApp.isActive, Date() < retryDeadline {
        other.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
      }
    }
    try XCTSkipIf(NSApp.isActive, "host app did not become inactive", file: file, line: line)
  }

  private func restoreHostAppActivation() {
    NSApp.activate(ignoringOtherApps: true)
    let deadline = Date().addingTimeInterval(2)
    while !NSApp.isActive, Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
  }

  /// A diagonal sweep across the view — one full crossing every 200 ticks,
  /// i.e. fast, continuous mouse movement.
  private func walkPoint(index: Int, in bounds: CGRect) -> CGPoint {
    let step = CGFloat(index % 200) / 200.0
    return CGPoint(
      x: bounds.width * step,
      y: bounds.height * step
    )
  }

  /// Time `body` (sync sample), then run one non-blocking main run-loop pass to
  /// execute blocks the tick enqueued (tick sample = sync + queued work).
  private func measureTick(sync: inout [Double], tick: inout [Double], body: () -> Void) {
    let t0 = CFAbsoluteTimeGetCurrent()
    body()
    let t1 = CFAbsoluteTimeGetCurrent()
    RunLoop.current.run(until: Date())
    let t2 = CFAbsoluteTimeGetCurrent()
    sync.append((t1 - t0) * 1000)
    tick.append((t2 - t0) * 1000)
  }

  private func report(label: String, sync: [Double], tick: [Double]) {
    emit("[PERF] \(label): sync \(describe(sync)) | tick \(describe(tick))")
  }

  /// Results sink: `print` output is swallowed inside the xcresult bundle when
  /// running under `xcodebuild test`, so every line is also appended to a plain
  /// file in the host's temporary directory for reliable extraction.
  private func emit(_ line: String) {
    print(line)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("snapzy-hover-perf.log")
    let data = (line + "\n").data(using: .utf8)!
    if let handle = try? FileHandle(forWritingTo: url) {
      handle.seekToEndOfFile()
      handle.write(data)
      try? handle.close()
    } else {
      try? data.write(to: url)
    }
  }

  private func describe(_ samples: [Double]) -> String {
    guard !samples.isEmpty else { return "n=0" }
    let sorted = samples.sorted()
    let mean = samples.reduce(0, +) / Double(samples.count)
    let median = sorted[sorted.count / 2]
    let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
    let maxValue = sorted.last ?? 0
    return String(
      format: "n=%d mean=%.2fms median=%.2fms p95=%.2fms max=%.2fms",
      samples.count, mean, median, p95, maxValue
    )
  }

  private func pooledWindow() -> AreaSelectionWindow? {
    let mirror = Mirror(reflecting: AreaSelectionController.shared)
    if let pool = mirror.children.first(where: { $0.label == "windowPool" })?.value
      as? [CGDirectDisplayID: AreaSelectionWindow] {
      return pool.values.first
    }
    return nil
  }
}
