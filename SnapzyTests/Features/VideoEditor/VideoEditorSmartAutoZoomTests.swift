//
//  VideoEditorSmartAutoZoomTests.swift
//  SnapzyTests
//
//  Unit tests for action- and outcome-aware Smart Auto-Zoom planning and visual outcome grid analysis.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class VideoEditorSmartAutoZoomTests: XCTestCase {
  private func makeMouseSamples(
    waypoints: [(TimeInterval, CGFloat, CGFloat)],
    fps: Int = 30
  ) -> [RecordedMouseSample] {
    guard waypoints.count >= 2 else { return [] }
    var result: [RecordedMouseSample] = []
    let dt = 1.0 / Double(fps)
    for i in 0 ..< (waypoints.count - 1) {
      let a = waypoints[i]
      let b = waypoints[i + 1]
      let span = max(b.0 - a.0, dt)
      let steps = max(1, Int((span / dt).rounded()))
      for s in 0 ..< steps {
        let frac = CGFloat(s) / CGFloat(steps)
        result.append(
          RecordedMouseSample(
            time: a.0 + span * Double(frac),
            normalizedX: a.1 + (b.1 - a.1) * frac,
            normalizedY: a.2 + (b.2 - a.2) * frac,
            isInsideCapture: true
          )
        )
      }
    }
    if let last = waypoints.last {
      result.append(
        RecordedMouseSample(time: last.0, normalizedX: last.1, normalizedY: last.2, isInsideCapture: true)
      )
    }
    return result
  }

  func testSingleClick_anticipatesBeforeClickAndHoldsAfter() throws {
    let samples = makeMouseSamples(waypoints: [
      (0.0, 0.1, 0.1),
      (2.0, 0.25, 0.30),
      (6.0, 0.25, 0.30),
    ])
    let capture = RecordingCursorCapture(clicks: [
      RecordedClick(time: 2.0, button: .left, phase: .down, normalizedX: 0.25, normalizedY: 0.30),
      RecordedClick(time: 2.08, button: .left, phase: .up, normalizedX: 0.25, normalizedY: 0.30),
    ])
    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 1920, height: 1080),
      samplesPerSecond: 30,
      mouseSamples: samples,
      cursorCapture: capture,
      isCursorBaked: false
    )

    let plan = VideoEditorSmartAutoZoomEngine.generatePlan(from: metadata, duration: 6.0)
    XCTAssertEqual(plan.segments.count, 1)

    let segment = try XCTUnwrap(plan.segments.first)
    XCTAssertTrue(segment.isAutoMode)
    XCTAssertTrue(segment.isSmartAutoZoom)
    XCTAssertLessThan(segment.startTime, 2.0, "Zoom should anticipate slightly before click lands")
    XCTAssertGreaterThan(segment.endTime, 2.8, "Zoom should hold through post-click outcome before zooming out")
  }

  func testDoubleClick_collapsesIntoSingleTighterFocusSegment() throws {
    let samples = makeMouseSamples(waypoints: [(0, 0.5, 0.5), (5, 0.5, 0.5)])
    let capture = RecordingCursorCapture(clicks: [
      RecordedClick(time: 1.50, button: .left, phase: .down, normalizedX: 0.4, normalizedY: 0.4),
      RecordedClick(time: 1.56, button: .left, phase: .up, normalizedX: 0.4, normalizedY: 0.4),
      RecordedClick(time: 1.72, button: .left, phase: .down, normalizedX: 0.402, normalizedY: 0.401),
      RecordedClick(time: 1.78, button: .left, phase: .up, normalizedX: 0.402, normalizedY: 0.401),
    ])
    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 1920, height: 1080),
      samplesPerSecond: 30,
      mouseSamples: samples,
      cursorCapture: capture,
      isCursorBaked: false
    )

    let actions = VideoEditorSmartAutoZoomEngine.detectActions(from: metadata, duration: 5.0)
    XCTAssertEqual(actions.count, 1)
    XCTAssertEqual(actions.first?.kind, .doubleClick)

    let plan = VideoEditorSmartAutoZoomEngine.generatePlan(from: metadata, duration: 5.0, style: .balanced)
    XCTAssertEqual(plan.segments.count, 1)
    XCTAssertEqual(Double(plan.segments[0].zoomLevel), Double(SmartAutoZoomStyle.balanced.detailZoom), accuracy: 0.05)
  }

  func testMultiActionChain_mergesCloseClicksWithCinematicPanArc() throws {
    let samples = makeMouseSamples(waypoints: [
      (0.0, 0.15, 0.25),
      (1.5, 0.15, 0.25),
      (2.4, 0.85, 0.75),
      (6.0, 0.85, 0.75),
    ])
    let capture = RecordingCursorCapture(clicks: [
      RecordedClick(time: 1.5, button: .left, phase: .down, normalizedX: 0.15, normalizedY: 0.25),
      RecordedClick(time: 1.56, button: .left, phase: .up, normalizedX: 0.15, normalizedY: 0.25),
      RecordedClick(time: 2.5, button: .left, phase: .down, normalizedX: 0.85, normalizedY: 0.75),
      RecordedClick(time: 2.56, button: .left, phase: .up, normalizedX: 0.85, normalizedY: 0.75),
    ])
    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 1920, height: 1080),
      samplesPerSecond: 30,
      mouseSamples: samples,
      cursorCapture: capture,
      isCursorBaked: false
    )

    let plan = VideoEditorSmartAutoZoomEngine.generatePlan(from: metadata, duration: 6.0)
    XCTAssertEqual(plan.segments.count, 1, "Close consecutive actions should merge into one smooth segment")

    let keyframes = try XCTUnwrap(plan.segments.first?.smartKeyframes)
    let hasArcDip = keyframes.contains { $0.zoomMultiplier < 0.92 }
    XCTAssertTrue(hasArcDip, "Long cross-screen pan between actions should insert a cinematic arc pullback")
  }

  func testTypingDetection_holdsZoomUntilCursorReappears() throws {
    let samples = makeMouseSamples(waypoints: [(0, 0.4, 0.4), (9, 0.4, 0.4)])
    let capture = RecordingCursorCapture(
      appearance: [
        RecordedCursorChange(time: 0.0, imageID: 0, isHidden: false),
        RecordedCursorChange(time: 1.4, imageID: nil, isHidden: true),  // started typing
        RecordedCursorChange(time: 4.8, imageID: 0, isHidden: false),   // finished typing
      ],
      clicks: [
        RecordedClick(time: 1.2, button: .left, phase: .down, normalizedX: 0.4, normalizedY: 0.4),
        RecordedClick(time: 1.26, button: .left, phase: .up, normalizedX: 0.4, normalizedY: 0.4),
      ]
    )
    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 1920, height: 1080),
      samplesPerSecond: 30,
      mouseSamples: samples,
      cursorCapture: capture,
      isCursorBaked: false
    )

    let plan = VideoEditorSmartAutoZoomEngine.generatePlan(from: metadata, duration: 9.0)
    let segment = try XCTUnwrap(plan.segments.first)
    XCTAssertGreaterThan(segment.endTime, 5.5, "Zoom must stay locked throughout typing and settle beat")
  }

  func testVisualOutcomeGridAnalyzer_classifiesLocalRemoteAndFullScreenTransitions() {
    let width = VideoEditorSmartAutoZoomEngine.visualGridWidth
    let height = VideoEditorSmartAutoZoomEngine.visualGridHeight
    let count = width * height
    let baseline = [Float](repeating: 0.2, count: count)

    // 1. Localized popup near top-left click (0.2, 0.2)
    var localPopup = baseline
    for r in 1 ... 3 {
      for c in 2 ... 5 {
        localPopup[r * width + c] = 0.85
      }
    }
    let localResult = VideoEditorSmartAutoZoomEngine.analyzeGridSequence(
      preGrid: baseline,
      postSamples: [(2.2, localPopup), (2.4, localPopup)],
      actionPoint: CGPoint(x: 0.2, y: 0.2),
      actionEndTime: 2.0
    )
    XCTAssertEqual(localResult.kind, .localNearClick)
    XCTAssertEqual(localResult.settleTime, 2.2, accuracy: 0.01)

    // 2. Remote modal in bottom-right after clicking top-left (0.1, 0.1)
    var remoteModal = baseline
    for r in 5 ... 7 {
      for c in 10 ... 13 {
        remoteModal[r * width + c] = 0.9
      }
    }
    let remoteResult = VideoEditorSmartAutoZoomEngine.analyzeGridSequence(
      preGrid: baseline,
      postSamples: [(2.3, remoteModal), (2.5, remoteModal)],
      actionPoint: CGPoint(x: 0.1, y: 0.1),
      actionEndTime: 2.0
    )
    XCTAssertEqual(remoteResult.kind, .localRemoteResult)
    XCTAssertGreaterThan(remoteResult.outcomeCentroid.x, 0.6)
    XCTAssertGreaterThan(remoteResult.outcomeCentroid.y, 0.55)

    // 3. Full-screen page navigation (>50% cells changed)
    let fullScreen = [Float](repeating: 0.85, count: count)
    let pageSwitch = VideoEditorSmartAutoZoomEngine.analyzeGridSequence(
      preGrid: baseline,
      postSamples: [(2.2, fullScreen)],
      actionPoint: CGPoint(x: 0.2, y: 0.2),
      actionEndTime: 2.0
    )
    XCTAssertEqual(pageSwitch.kind, .fullScreenTransition)
  }

  func testFullScreenOutcome_triggersEarlyZoomOutAndPreventsMerge() throws {
    let samples = makeMouseSamples(waypoints: [
      (0.0, 0.2, 0.2),
      (1.5, 0.2, 0.2),
      (2.8, 0.7, 0.7),
      (6.0, 0.7, 0.7),
    ])
    let capture = RecordingCursorCapture(clicks: [
      RecordedClick(time: 1.5, button: .left, phase: .down, normalizedX: 0.2, normalizedY: 0.2),
      RecordedClick(time: 1.55, button: .left, phase: .up, normalizedX: 0.2, normalizedY: 0.2),
      RecordedClick(time: 3.1, button: .left, phase: .down, normalizedX: 0.7, normalizedY: 0.7),
      RecordedClick(time: 3.15, button: .left, phase: .up, normalizedX: 0.7, normalizedY: 0.7),
    ])
    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 1920, height: 1080),
      samplesPerSecond: 30,
      mouseSamples: samples,
      cursorCapture: capture,
      isCursorBaked: false
    )

    let actions = VideoEditorSmartAutoZoomEngine.detectActions(from: metadata, duration: 6.0)
    let firstAction = try XCTUnwrap(actions.first)
    let outcomes: [UUID: VideoEditorSmartAutoZoomEngine.VisualOutcome] = [
      firstAction.id: VideoEditorSmartAutoZoomEngine.VisualOutcome(
        kind: .fullScreenTransition,
        settleTime: 1.85,
        changedCoverage: 0.78,
        outcomeCentroid: CGPoint(x: 0.5, y: 0.5),
        outcomeBounds: CGRect(x: 0, y: 0, width: 1, height: 1)
      ),
    ]

    let plan = VideoEditorSmartAutoZoomEngine.buildPlan(
      actions: actions,
      metadata: metadata,
      duration: 6.0,
      visualOutcomes: outcomes
    )
    XCTAssertEqual(plan.segments.count, 2, "Full-screen transition should zoom out before zooming into next action")
    XCTAssertLessThan(plan.segments[0].endTime, plan.segments[1].startTime)
  }

  func testDwellFallback_generatesZoomWithoutClickTelemetry() {
    let samples = makeMouseSamples(waypoints: [
      (0.0, 0.1, 0.1),
      (1.0, 0.7, 0.6),
      (2.4, 0.7, 0.6),
      (4.5, 0.2, 0.2),
    ])
    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 1920, height: 1080),
      samplesPerSecond: 30,
      mouseSamples: samples
    )

    let plan = VideoEditorSmartAutoZoomEngine.generatePlan(from: metadata, duration: 5.0)
    XCTAssertEqual(plan.segments.count, 1)
    XCTAssertGreaterThan(plan.segments[0].zoomLevel, 1.3)
  }

  func testConnectedComponentIsolation_ignoresMenuBarClockNoise() {
    let width = VideoEditorSmartAutoZoomEngine.rgbGridWidth
    let height = VideoEditorSmartAutoZoomEngine.rgbGridHeight
    let count = width * height
    let baseline = [Float](repeating: 0.2, count: count * 3)

    var post = baseline
    // Real popover cluster in bottom-left around (0.25, 0.70).
    for r in 11 ... 15 {
      for c in 5 ... 11 {
        let i = (r * width + c) * 3
        post[i] = 0.85; post[i + 1] = 0.88; post[i + 2] = 0.92
      }
    }
    // Stray menu bar clock tick at top-right (row 0, col 30-31): MUST NOT pollute outcomeBounds!
    for c in 30 ... 31 {
      let i = c * 3
      post[i] = 0.95; post[i + 1] = 0.95; post[i + 2] = 0.95
    }

    let result = VideoEditorSmartAutoZoomEngine.analyzeRGBGridSequence(
      preGrid: baseline,
      postSamples: [(2.2, post), (2.4, post)],
      actionPoint: CGPoint(x: 0.25, y: 0.65),
      actionEndTime: 2.0
    )

    XCTAssertEqual(result.kind, .localNearClick)
    XCTAssertGreaterThan(result.outcomeBounds.minY, 0.5, "Outcome bounds must ignore top-right menu bar clock noise")
    XCTAssertLessThan(result.outcomeBounds.maxX, 0.5, "Outcome bounds must stay tightly wrapped around the popover")
  }

  func testStrayEmptyBackgroundClick_filteredWhenVisualOutcomeNoneAndImmediateDeparture() throws {
    let samples = makeMouseSamples(waypoints: [
      (0.0, 0.1, 0.1),
      (1.0, 0.2, 0.2),   // stray focus click, then immediately zips away
      (1.2, 0.75, 0.75), // real target click
      (2.5, 0.75, 0.75),
      (5.0, 0.75, 0.75),
    ])
    let capture = RecordingCursorCapture(clicks: [
      RecordedClick(time: 1.0, button: .left, phase: .down, normalizedX: 0.2, normalizedY: 0.2),
      RecordedClick(time: 1.05, button: .left, phase: .up, normalizedX: 0.2, normalizedY: 0.2),
      RecordedClick(time: 2.5, button: .left, phase: .down, normalizedX: 0.75, normalizedY: 0.75),
      RecordedClick(time: 2.56, button: .left, phase: .up, normalizedX: 0.75, normalizedY: 0.75),
    ])
    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 1920, height: 1080),
      samplesPerSecond: 30,
      mouseSamples: samples,
      cursorCapture: capture,
      isCursorBaked: false
    )

    let actions = VideoEditorSmartAutoZoomEngine.detectActions(from: metadata, duration: 5.0)
    XCTAssertEqual(actions.count, 2)
    let outcomes: [UUID: VideoEditorSmartAutoZoomEngine.VisualOutcome] = [
      actions[0].id: .none(at: 1.05, point: CGPoint(x: 0.2, y: 0.2)),
      actions[1].id: VideoEditorSmartAutoZoomEngine.VisualOutcome(
        kind: .localNearClick,
        settleTime: 2.8,
        changedCoverage: 0.08,
        outcomeCentroid: CGPoint(x: 0.75, y: 0.75),
        outcomeBounds: CGRect(x: 0.65, y: 0.65, width: 0.20, height: 0.20)
      ),
    ]

    let plan = VideoEditorSmartAutoZoomEngine.buildPlan(
      actions: actions,
      metadata: metadata,
      duration: 5.0,
      visualOutcomes: outcomes
    )
    XCTAssertEqual(plan.segments.count, 1, "Stray click with no visual change and immediate departure should be ignored")
    XCTAssertGreaterThan(plan.segments[0].startTime, 1.5)
  }

  func testLookAheadCauseEffectDirectGlide_skipsIntermediatePumpAndGlidesMonotonically() throws {
    let samples = makeMouseSamples(waypoints: [
      (0.0, 0.15, 0.09),
      (1.5, 0.15, 0.09),
      (2.4, 0.48, 0.48),
      (2.8, 0.48, 0.48),
      (6.0, 0.48, 0.48),
    ])
    let capture = RecordingCursorCapture(clicks: [
      RecordedClick(time: 1.50, button: .left, phase: .down, normalizedX: 0.15, normalizedY: 0.09),
      RecordedClick(time: 1.55, button: .left, phase: .up, normalizedX: 0.15, normalizedY: 0.09),
      RecordedClick(time: 2.80, button: .left, phase: .down, normalizedX: 0.48, normalizedY: 0.48),
      RecordedClick(time: 2.86, button: .left, phase: .up, normalizedX: 0.48, normalizedY: 0.48),
    ])
    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 1680, height: 1050),
      samplesPerSecond: 30,
      mouseSamples: samples,
      cursorCapture: capture,
      isCursorBaked: false
    )

    let actions = VideoEditorSmartAutoZoomEngine.detectActions(from: metadata, duration: 6.0)
    XCTAssertEqual(actions.count, 2)

    let outcomes: [UUID: VideoEditorSmartAutoZoomEngine.VisualOutcome] = [
      actions[0].id: VideoEditorSmartAutoZoomEngine.VisualOutcome(
        kind: .localRemoteResult,
        settleTime: 1.85,
        changedCoverage: 0.12,
        outcomeCentroid: CGPoint(x: 0.48, y: 0.48),
        outcomeBounds: CGRect(x: 0.36, y: 0.38, width: 0.24, height: 0.20)
      ),
      actions[1].id: VideoEditorSmartAutoZoomEngine.VisualOutcome(
        kind: .fullScreenTransition,
        settleTime: 3.15,
        changedCoverage: 0.52,
        outcomeCentroid: CGPoint(x: 0.5, y: 0.5),
        outcomeBounds: CGRect(x: 0, y: 0, width: 1, height: 1)
      ),
    ]

    let plan = VideoEditorSmartAutoZoomEngine.buildPlan(
      actions: actions,
      metadata: metadata,
      duration: 6.0,
      visualOutcomes: outcomes
    )
    XCTAssertEqual(plan.segments.count, 1)
    let keyframes = try XCTUnwrap(plan.segments.first?.smartKeyframes)
    XCTAssertTrue(
      keyframes.allSatisfy { $0.zoomMultiplier >= 0.78 },
      "Intra-chapter zoom must never pump below 0.78x multiplier"
    )
    // X should progress monotonically from left (Close button) toward center (Don't Save modal).
    for i in 1 ..< keyframes.count {
      XCTAssertGreaterThanOrEqual(
        keyframes[i].center.x,
        keyframes[i - 1].center.x - 0.001,
        "Direct cause-to-effect glide must progress monotonically without head-fake reversals"
      )
    }
  }

  func testSidebarConsecutiveClicks_ignoreRemotePreviewHeadFake() throws {
    let samples = makeMouseSamples(waypoints: [
      (0.0, 0.28, 0.12),
      (1.5, 0.28, 0.12),
      (2.4, 0.28, 0.16),
      (2.7, 0.28, 0.16),
      (6.0, 0.28, 0.16),
    ])
    let capture = RecordingCursorCapture(clicks: [
      RecordedClick(time: 1.50, button: .left, phase: .down, normalizedX: 0.28, normalizedY: 0.12),
      RecordedClick(time: 1.55, button: .left, phase: .up, normalizedX: 0.28, normalizedY: 0.12),
      RecordedClick(time: 2.70, button: .left, phase: .down, normalizedX: 0.28, normalizedY: 0.16),
      RecordedClick(time: 2.75, button: .left, phase: .up, normalizedX: 0.28, normalizedY: 0.16),
    ])
    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 1680, height: 1050),
      samplesPerSecond: 30,
      mouseSamples: samples,
      cursorCapture: capture,
      isCursorBaked: false
    )

    let actions = VideoEditorSmartAutoZoomEngine.detectActions(from: metadata, duration: 6.0)
    let outcomes: [UUID: VideoEditorSmartAutoZoomEngine.VisualOutcome] = [
      actions[0].id: VideoEditorSmartAutoZoomEngine.VisualOutcome(
        kind: .localRemoteResult,
        settleTime: 1.85,
        changedCoverage: 0.18,
        outcomeCentroid: CGPoint(x: 0.62, y: 0.45),
        outcomeBounds: CGRect(x: 0.44, y: 0.25, width: 0.36, height: 0.40)
      ),
      actions[1].id: .none(at: 2.75, point: CGPoint(x: 0.28, y: 0.16)),
    ]

    let plan = VideoEditorSmartAutoZoomEngine.buildPlan(
      actions: actions,
      metadata: metadata,
      duration: 6.0,
      visualOutcomes: outcomes
    )
    XCTAssertEqual(plan.segments.count, 1)
    let keyframes = try XCTUnwrap(plan.segments.first?.smartKeyframes)
    XCTAssertTrue(
      keyframes.allSatisfy { $0.center.x < 0.40 },
      "Camera must stay steady on the sidebar instead of yanking right to a preview refresh between consecutive sidebar clicks"
    )
  }

  func testSustainedMotionOutcome_classifiesVideoPlaybackAsFullScreenZoomOut() {
    let width = VideoEditorSmartAutoZoomEngine.rgbGridWidth
    let height = VideoEditorSmartAutoZoomEngine.rgbGridHeight
    let count = width * height
    let baseline = [Float](repeating: 0.15, count: count * 3)

    // Simulate a video viewport covering ~22% of the screen continuously changing across 5 post-click frames.
    func frame(phase: Float) -> [Float] {
      var grid = baseline
      for r in 3 ... 11 {
        for c in 12 ... 25 {
          let i = (r * width + c) * 3
          let value = ((Float((r + c) % 5) * 0.14 + phase).truncatingRemainder(dividingBy: 0.8)) + 0.15
          grid[i] = value
          grid[i + 1] = 1.0 - value
          grid[i + 2] = 0.5
        }
      }
      return grid
    }

    let result = VideoEditorSmartAutoZoomEngine.analyzeRGBGridSequence(
      preGrid: baseline,
      postSamples: [
        (2.15, frame(phase: 0.10)),
        (2.35, frame(phase: 0.30)),
        (2.60, frame(phase: 0.50)),
        (2.90, frame(phase: 0.70)),
        (3.25, frame(phase: 0.20)),
      ],
      actionPoint: CGPoint(x: 0.55, y: 0.72),
      actionEndTime: 2.0
    )

    XCTAssertTrue(result.isSustainedMotion)
    XCTAssertEqual(
      result.kind,
      .fullScreenTransition,
      "Clicking Play to start continuous video playback should zoom out cleanly to full view"
    )
  }

  func testSmallSliderDrag_keepsCameraRockSteady() throws {
    let samples = makeMouseSamples(waypoints: [
      (0.0, 0.29, 0.32),
      (1.5, 0.29, 0.32),
      (2.2, 0.20, 0.32),
      (5.0, 0.20, 0.32),
    ])
    let capture = RecordingCursorCapture(clicks: [
      RecordedClick(time: 1.50, button: .left, phase: .down, normalizedX: 0.29, normalizedY: 0.32),
      RecordedClick(time: 2.20, button: .left, phase: .up, normalizedX: 0.20, normalizedY: 0.32),
    ])
    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 1680, height: 1050),
      samplesPerSecond: 30,
      mouseSamples: samples,
      cursorCapture: capture,
      isCursorBaked: false
    )

    let plan = VideoEditorSmartAutoZoomEngine.generatePlan(from: metadata, duration: 5.0)
    XCTAssertEqual(plan.segments.count, 1)
    let keyframes = try XCTUnwrap(plan.segments.first?.smartKeyframes)
    let xs = keyframes.map(\.center.x)
    let ys = keyframes.map(\.center.y)
    XCTAssertLessThan((xs.max() ?? 0) - (xs.min() ?? 0), 0.01, "Small slider drag must hold camera rock-steady horizontally")
    XCTAssertLessThan((ys.max() ?? 0) - (ys.min() ?? 0), 0.01, "Small slider drag must hold camera rock-steady vertically")
  }

  func testTrailingStopRecordingClick_filteredWithoutChoppyTailSegment() {
    let samples = makeMouseSamples(waypoints: [
      (0.0, 0.3, 0.3),
      (2.0, 0.3, 0.3),
      (9.7, 0.8, 0.05),
      (10.0, 0.8, 0.05),
    ])
    let capture = RecordingCursorCapture(clicks: [
      RecordedClick(time: 2.00, button: .left, phase: .down, normalizedX: 0.3, normalizedY: 0.3),
      RecordedClick(time: 2.06, button: .left, phase: .up, normalizedX: 0.3, normalizedY: 0.3),
      RecordedClick(time: 9.75, button: .left, phase: .down, normalizedX: 0.8, normalizedY: 0.05),
      RecordedClick(time: 9.80, button: .left, phase: .up, normalizedX: 0.8, normalizedY: 0.05),
    ])
    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 1680, height: 1050),
      samplesPerSecond: 30,
      mouseSamples: samples,
      cursorCapture: capture,
      isCursorBaked: false
    )

    let plan = VideoEditorSmartAutoZoomEngine.generatePlan(from: metadata, duration: 10.0)
    XCTAssertEqual(plan.segments.count, 1, "Isolated stop-recording click in final 0.55s must not emit a choppy tail segment")
    XCTAssertLessThan(plan.segments[0].endTime, 5.0)
  }

  func testClickWithNoPostActionSamples_doesNotCrash() {
    // Regression test: clicks with zero mouse samples in the post-click window (e.g. rapid consecutive clicks
    // or cursor leaving capture right after click) must never trap on `1 ..< 0` range construction.
    let capture = RecordingCursorCapture(clicks: [
      RecordedClick(time: 1.00, button: .left, phase: .down, normalizedX: 0.4, normalizedY: 0.4),
      RecordedClick(time: 1.05, button: .left, phase: .up, normalizedX: 0.4, normalizedY: 0.4),
      RecordedClick(time: 1.10, button: .left, phase: .down, normalizedX: 0.7, normalizedY: 0.7),
      RecordedClick(time: 1.15, button: .left, phase: .up, normalizedX: 0.7, normalizedY: 0.7),
    ])
    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 1680, height: 1050),
      samplesPerSecond: 30,
      mouseSamples: [
        RecordedMouseSample(time: 0.5, normalizedX: 0.4, normalizedY: 0.4, isInsideCapture: true),
        RecordedMouseSample(time: 1.0, normalizedX: 0.4, normalizedY: 0.4, isInsideCapture: true),
        RecordedMouseSample(time: 1.2, normalizedX: 0.7, normalizedY: 0.7, isInsideCapture: false),
      ],
      cursorCapture: capture,
      isCursorBaked: false
    )

    let plan = VideoEditorSmartAutoZoomEngine.generatePlan(from: metadata, duration: 4.0)
    XCTAssertFalse(plan.segments.isEmpty)
  }

  func testLongMultiActionWorkflow_20SecondBurstStaysCohesiveWithoutArbitraryMidSplit() throws {
    // Simulates a dense 20-second active editing session (18 consecutive clicks across the UI)
    // and verifies it stays cohesive instead of arbitrarily splitting at 14s with a jarring 0.22s zoom-out bounce.
    var waypoints: [(TimeInterval, CGFloat, CGFloat)] = [(0.0, 0.2, 0.2)]
    var clicks: [RecordedClick] = []
    let positions: [(CGFloat, CGFloat)] = [
      (0.22, 0.22), (0.25, 0.34), (0.24, 0.48), (0.52, 0.42), (0.68, 0.30),
      (0.72, 0.55), (0.45, 0.62), (0.28, 0.36), (0.28, 0.42), (0.60, 0.50),
      (0.75, 0.25), (0.78, 0.40), (0.50, 0.72), (0.32, 0.68), (0.26, 0.28),
      (0.30, 0.32), (0.58, 0.46), (0.64, 0.52),
    ]
    for (idx, pos) in positions.enumerated() {
      let t = 1.5 + Double(idx) * 1.05
      waypoints.append((t, pos.0, pos.1))
      clicks.append(RecordedClick(time: t, button: .left, phase: .down, normalizedX: pos.0, normalizedY: pos.1))
      clicks.append(RecordedClick(time: t + 0.06, button: .left, phase: .up, normalizedX: pos.0, normalizedY: pos.1))
    }
    waypoints.append((26.0, 0.64, 0.52))

    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 3360, height: 2100),
      samplesPerSecond: 30,
      mouseSamples: makeMouseSamples(waypoints: waypoints),
      cursorCapture: RecordingCursorCapture(clicks: clicks),
      isCursorBaked: false
    )

    let plan = VideoEditorSmartAutoZoomEngine.generatePlan(from: metadata, duration: 26.0, style: .balanced)
    XCTAssertEqual(plan.segments.count, 1, "Continuous 20s workflow must stay cohesive without a jarring mid-session split")
    let seg = try XCTUnwrap(plan.segments.first)
    XCTAssertGreaterThan(seg.duration, 18.0)
    let keyframes = try XCTUnwrap(seg.smartKeyframes)
    XCTAssertTrue(keyframes.allSatisfy { $0.zoomMultiplier >= 0.78 }, "Zero-pump discipline must hold across long multi-action chains")
  }

  func testComplex45SecondTutorialWorkflow_allStylesMaintainZeroOverlapAndSmoothCauseEffect() throws {
    // Realistic 45s tutorial: double-click -> typing -> small slider drag -> remote modal + click ->
    // full-screen transition -> idle gap -> large drag -> right-click menu -> trailing stop click.
    var samples = makeMouseSamples(waypoints: [
      (0.0, 0.20, 0.20),
      (1.8, 0.25, 0.30),  // double-click
      (5.0, 0.25, 0.30),  // typing hold
      (6.5, 0.28, 0.40),  // small slider drag start
      (7.2, 0.20, 0.40),  // small slider drag end
      (9.0, 0.15, 0.10),  // click Close
      (10.2, 0.50, 0.50), // click remote modal "Don't Save"
      (14.0, 0.50, 0.50), // page transition settle + full-screen view
      (20.0, 0.18, 0.65), // large drag start
      (21.0, 0.72, 0.45), // large drag end
      (27.0, 0.65, 0.35), // right-click context menu
      (31.0, 0.67, 0.44), // click menu item
      (44.7, 0.85, 0.04), // trailing stop-recording click (should be filtered!)
      (45.0, 0.85, 0.04),
    ])
    // Mark cursor outside capture briefly around 16s-18s.
    for i in samples.indices where samples[i].time >= 16.0 && samples[i].time <= 17.5 {
      samples[i] = RecordedMouseSample(
        time: samples[i].time,
        normalizedX: samples[i].normalizedX,
        normalizedY: samples[i].normalizedY,
        isInsideCapture: false
      )
    }

    let clicks: [RecordedClick] = [
      // Double-click at 1.8s
      RecordedClick(time: 1.80, button: .left, phase: .down, normalizedX: 0.25, normalizedY: 0.30),
      RecordedClick(time: 1.85, button: .left, phase: .up, normalizedX: 0.25, normalizedY: 0.30),
      RecordedClick(time: 1.98, button: .left, phase: .down, normalizedX: 0.25, normalizedY: 0.30),
      RecordedClick(time: 2.04, button: .left, phase: .up, normalizedX: 0.25, normalizedY: 0.30),
      // Small slider drag 6.5s -> 7.2s
      RecordedClick(time: 6.50, button: .left, phase: .down, normalizedX: 0.28, normalizedY: 0.40),
      RecordedClick(time: 7.20, button: .left, phase: .up, normalizedX: 0.20, normalizedY: 0.40),
      // Click Close at 9.0s -> click modal at 10.2s
      RecordedClick(time: 9.00, button: .left, phase: .down, normalizedX: 0.15, normalizedY: 0.10),
      RecordedClick(time: 9.05, button: .left, phase: .up, normalizedX: 0.15, normalizedY: 0.10),
      RecordedClick(time: 10.20, button: .left, phase: .down, normalizedX: 0.50, normalizedY: 0.50),
      RecordedClick(time: 10.26, button: .left, phase: .up, normalizedX: 0.50, normalizedY: 0.50),
      // Large file drag 20.0s -> 21.0s
      RecordedClick(time: 20.00, button: .left, phase: .down, normalizedX: 0.18, normalizedY: 0.65),
      RecordedClick(time: 21.00, button: .left, phase: .up, normalizedX: 0.72, normalizedY: 0.45),
      // Right-click menu 27.0s -> select item 31.0s
      RecordedClick(time: 27.00, button: .right, phase: .down, normalizedX: 0.65, normalizedY: 0.35),
      RecordedClick(time: 27.06, button: .right, phase: .up, normalizedX: 0.65, normalizedY: 0.35),
      RecordedClick(time: 31.00, button: .left, phase: .down, normalizedX: 0.67, normalizedY: 0.44),
      RecordedClick(time: 31.06, button: .left, phase: .up, normalizedX: 0.67, normalizedY: 0.44),
      // Trailing stop-recording click at 44.75s
      RecordedClick(time: 44.75, button: .left, phase: .down, normalizedX: 0.85, normalizedY: 0.04),
      RecordedClick(time: 44.80, button: .left, phase: .up, normalizedX: 0.85, normalizedY: 0.04),
    ]
    let appearance: [RecordedCursorChange] = [
      RecordedCursorChange(time: 0.0, imageID: 0, isHidden: false),
      RecordedCursorChange(time: 2.3, imageID: nil, isHidden: true),
      RecordedCursorChange(time: 4.9, imageID: 0, isHidden: false),
    ]
    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 3360, height: 2100),
      samplesPerSecond: 30,
      mouseSamples: samples,
      cursorCapture: RecordingCursorCapture(appearance: appearance, clicks: clicks),
      isCursorBaked: false
    )

    let actions = VideoEditorSmartAutoZoomEngine.detectActions(from: metadata, duration: 45.0)
    XCTAssertGreaterThanOrEqual(actions.count, 7)

    var outcomes: [UUID: VideoEditorSmartAutoZoomEngine.VisualOutcome] = [:]
    for action in actions {
      if abs(action.startTime - 9.0) < 0.2 {
        outcomes[action.id] = VideoEditorSmartAutoZoomEngine.VisualOutcome(
          kind: .localRemoteResult,
          settleTime: 9.3,
          changedCoverage: 0.14,
          outcomeCentroid: CGPoint(x: 0.50, y: 0.50),
          outcomeBounds: CGRect(x: 0.38, y: 0.40, width: 0.24, height: 0.20)
        )
      } else if abs(action.startTime - 10.2) < 0.2 {
        outcomes[action.id] = VideoEditorSmartAutoZoomEngine.VisualOutcome(
          kind: .fullScreenTransition,
          settleTime: 10.5,
          changedCoverage: 0.58,
          outcomeCentroid: CGPoint(x: 0.5, y: 0.5),
          outcomeBounds: CGRect(x: 0, y: 0, width: 1, height: 1)
        )
      }
    }

    for style in SmartAutoZoomStyle.allCases {
      let plan = VideoEditorSmartAutoZoomEngine.buildPlan(
        actions: actions,
        metadata: metadata,
        duration: 45.0,
        style: style,
        visualOutcomes: outcomes
      )
      XCTAssertGreaterThanOrEqual(plan.segments.count, 3, "Style \(style) should produce distinct chapters across 45s workflow")
      XCTAssertLessThan(plan.segments.last?.endTime ?? 45.0, 42.0, "Trailing stop-recording click must be filtered for \(style)")

      for i in 0 ..< plan.segments.count {
        let seg = plan.segments[i]
        XCTAssertGreaterThanOrEqual(seg.duration, 1.15)
        if i > 0 {
          XCTAssertGreaterThanOrEqual(seg.startTime, plan.segments[i - 1].endTime + 0.20)
        }
        let kfs = try XCTUnwrap(seg.smartKeyframes)
        XCTAssertTrue(kfs.allSatisfy { $0.zoomMultiplier >= 0.78 })
      }
    }
  }

  func testRapidConsecutiveFullScreenTransitions_doesNotBounceOutForTinyGap() {
    let samples = makeMouseSamples(waypoints: [
      (0.0, 0.2, 0.2),
      (1.5, 0.2, 0.2),
      (2.1, 0.7, 0.7),
      (5.0, 0.7, 0.7),
    ])
    let clicks = [
      RecordedClick(time: 1.50, button: .left, phase: .down, normalizedX: 0.2, normalizedY: 0.2),
      RecordedClick(time: 1.55, button: .left, phase: .up, normalizedX: 0.2, normalizedY: 0.2),
      RecordedClick(time: 2.10, button: .left, phase: .down, normalizedX: 0.7, normalizedY: 0.7),
      RecordedClick(time: 2.15, button: .left, phase: .up, normalizedX: 0.7, normalizedY: 0.7),
    ]
    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 1920, height: 1080),
      samplesPerSecond: 30,
      mouseSamples: samples,
      cursorCapture: RecordingCursorCapture(clicks: clicks),
      isCursorBaked: false
    )
    let actions = VideoEditorSmartAutoZoomEngine.detectActions(from: metadata, duration: 5.0)
    let outcomes = Dictionary(uniqueKeysWithValues: actions.map { action in
      (
        action.id,
        VideoEditorSmartAutoZoomEngine.VisualOutcome(
          kind: .fullScreenTransition,
          settleTime: action.endTime + 0.2,
          changedCoverage: 0.60,
          outcomeCentroid: CGPoint(x: 0.5, y: 0.5),
          outcomeBounds: CGRect(x: 0, y: 0, width: 1, height: 1)
        )
      )
    })

    let plan = VideoEditorSmartAutoZoomEngine.buildPlan(
      actions: actions,
      metadata: metadata,
      duration: 5.0,
      visualOutcomes: outcomes
    )
    XCTAssertEqual(plan.segments.count, 1, "Rapid clicks <0.95s apart must not bounce out to 1.0x for 0.2s and slam back in")
  }

  func testPathologicalMultiActionStorm_100ClicksAndEdgeCasesNeverCrash() {
    // 100 rapid/noisy clicks with duplicate timestamps, unmatched downs/ups, and out-of-bounds coordinates.
    var clicks: [RecordedClick] = []
    for i in 0 ..< 100 {
      let t = Double(i) * 0.28
      let x = CGFloat((i * 17) % 130) / 100.0 - 0.15 // intentionally includes < 0 and > 1
      let y = CGFloat((i * 29) % 130) / 100.0 - 0.15
      clicks.append(RecordedClick(time: t, button: i % 7 == 0 ? .right : .left, phase: .down, normalizedX: x, normalizedY: y))
      if i % 5 != 0 { // intentionally leave 20% unmatched downs
        clicks.append(RecordedClick(time: t + (i % 3 == 0 ? 0.0 : 0.04), button: i % 7 == 0 ? .right : .left, phase: .up, normalizedX: x, normalizedY: y))
      }
    }
    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 2560, height: 1600),
      samplesPerSecond: 30,
      mouseSamples: [
        RecordedMouseSample(time: 0.0, normalizedX: 0.5, normalizedY: 0.5, isInsideCapture: true),
      ],
      cursorCapture: RecordingCursorCapture(
        appearance: [RecordedCursorChange(time: 0.0, imageID: nil, isHidden: true)],
        clicks: clicks
      ),
      isCursorBaked: false
    )

    let plan = VideoEditorSmartAutoZoomEngine.generatePlan(from: metadata, duration: 30.0, style: .dynamic)
    XCTAssertFalse(plan.segments.isEmpty)
    for (i, seg) in plan.segments.enumerated() {
      XCTAssertTrue(seg.startTime.isFinite && seg.duration.isFinite && seg.zoomLevel.isFinite)
      XCTAssertGreaterThanOrEqual(seg.duration, 1.15)
      if i > 0 {
        XCTAssertGreaterThanOrEqual(seg.startTime, plan.segments[i - 1].endTime + 0.20)
      }
      for kf in seg.smartKeyframes ?? [] {
        XCTAssertTrue(kf.time.isFinite && kf.center.x.isFinite && kf.center.y.isFinite && kf.zoomMultiplier.isFinite)
        XCTAssertGreaterThanOrEqual(kf.center.x, 0)
        XCTAssertLessThanOrEqual(kf.center.x, 1)
        XCTAssertGreaterThanOrEqual(kf.center.y, 0)
        XCTAssertLessThanOrEqual(kf.center.y, 1)
      }
    }
  }

  func testEndToEndSpringAndShutterInvariants_acrossMultiActionSegments() {
    let samples = makeMouseSamples(waypoints: [
      (0.0, 0.12, 0.18),
      (1.2, 0.12, 0.18),
      (2.4, 0.82, 0.78),
      (3.8, 0.45, 0.30),
      (5.2, 0.85, 0.22),
      (9.0, 0.85, 0.22),
    ])
    let clicks = [
      RecordedClick(time: 1.20, button: .left, phase: .down, normalizedX: 0.12, normalizedY: 0.18),
      RecordedClick(time: 1.25, button: .left, phase: .up, normalizedX: 0.12, normalizedY: 0.18),
      RecordedClick(time: 2.40, button: .left, phase: .down, normalizedX: 0.82, normalizedY: 0.78),
      RecordedClick(time: 2.46, button: .left, phase: .up, normalizedX: 0.82, normalizedY: 0.78),
      RecordedClick(time: 3.80, button: .left, phase: .down, normalizedX: 0.45, normalizedY: 0.30),
      RecordedClick(time: 3.86, button: .left, phase: .up, normalizedX: 0.45, normalizedY: 0.30),
      RecordedClick(time: 5.20, button: .left, phase: .down, normalizedX: 0.85, normalizedY: 0.22),
      RecordedClick(time: 5.26, button: .left, phase: .up, normalizedX: 0.85, normalizedY: 0.22),
    ]
    let frameSize = CGSize(width: 3360, height: 2100)
    let metadata = RecordingMetadata(
      captureSize: frameSize,
      samplesPerSecond: 30,
      mouseSamples: samples,
      cursorCapture: RecordingCursorCapture(clicks: clicks),
      isCursorBaked: false
    )

    let plan = VideoEditorSmartAutoZoomEngine.generatePlan(from: metadata, duration: 9.0, style: .dynamic)
    XCTAssertFalse(plan.segments.isEmpty)

    var paths: [UUID: [AutoFocusCameraSample]] = [:]
    for seg in plan.segments {
      paths[seg.id] = VideoEditorAutoFocusEngine.buildPath(from: metadata, segment: seg)
      XCTAssertFalse(paths[seg.id]?.isEmpty ?? true)
    }

    var activeShutterFrames = 0
    for frame in 0 ..< 270 {
      let t = Double(frame) / 30.0
      let state = VideoEditorAutoFocusEngine.resolvedCameraState(
        at: t,
        segments: plan.segments,
        autoFocusPaths: paths,
        transitionDuration: ZoomCalculator.defaultTransitionDuration
      )
      XCTAssertGreaterThanOrEqual(state.zoomLevel, 1.0)
      XCTAssertLessThanOrEqual(state.zoomLevel, ZoomSegment.maxZoomLevel + 0.001)

      let crop = ZoomCalculator.calculateCropRect(center: state.center, zoomLevel: state.zoomLevel, frameSize: frameSize)
      XCTAssertGreaterThanOrEqual(crop.minX, -0.5)
      XCTAssertGreaterThanOrEqual(crop.minY, -0.5)
      XCTAssertLessThanOrEqual(crop.maxX, frameSize.width + 0.5)
      XCTAssertLessThanOrEqual(crop.maxY, frameSize.height + 0.5)

      let shutter = VideoEditorMotionBlurEngine.shutterPlan(
        at: t,
        frameDuration: 1.0 / 30.0,
        frameSize: frameSize,
        segments: plan.segments,
        autoFocusPaths: paths,
        transitionDuration: ZoomCalculator.defaultTransitionDuration,
        settings: .default
      )
      if shutter.isActive {
        activeShutterFrames += 1
        let weightSum = shutter.taps.reduce(Float(0)) { $0 + $1.weight }
        XCTAssertEqual(weightSum, 1.0, accuracy: 0.002)
      }
    }
    XCTAssertGreaterThan(activeShutterFrames, 10, "Multi-action pans and transitions should engage physical shutter blur")
  }

  // MARK: - Review Regression Tests

  @MainActor
  func testMergeSmartAutoZoomSegments_preservesUserZoomsAndEmptyPlanIsNoOp() {
    let manualZoom = ZoomSegment(
      startTime: 1.0,
      duration: 2.0,
      zoomLevel: 2.0,
      zoomCenter: CGPoint(x: 0.3, y: 0.3),
      zoomType: .manual
    )
    let regularAutoZoom = ZoomSegment(
      startTime: 6.0,
      duration: 1.5,
      zoomLevel: 1.8,
      zoomCenter: CGPoint(x: 0.5, y: 0.5),
      zoomType: .auto
    )
    let previousSmartZoom = ZoomSegment(
      startTime: 8.0,
      duration: 1.5,
      zoomLevel: 2.2,
      zoomCenter: CGPoint(x: 0.7, y: 0.7),
      zoomType: .auto,
      smartKeyframes: [
        AutoFocusCameraSample(time: 8.0, center: CGPoint(x: 0.7, y: 0.7), zoomMultiplier: 1.0),
        AutoFocusCameraSample(time: 9.5, center: CGPoint(x: 0.7, y: 0.7), zoomMultiplier: 1.0),
      ]
    )
    let existing = [manualZoom, regularAutoZoom, previousSmartZoom]

    // 1. Empty plan must leave all existing zooms completely untouched under both policies.
    XCTAssertEqual(
      VideoEditorState.mergeSmartAutoZoomSegments(existing: existing, generated: [], policy: .fillGaps),
      existing
    )
    XCTAssertEqual(
      VideoEditorState.mergeSmartAutoZoomSegments(existing: existing, generated: [], policy: .replaceAll),
      existing
    )

    // 2. Fill-gaps policy keeps manual & regular auto zooms, replaces prior smart zooms,
    //    and drops any generated segment overlapping a preserved user zoom.
    let overlappingGenerated = ZoomSegment(
      startTime: 2.2,
      duration: 1.5,
      zoomLevel: 2.0,
      zoomCenter: CGPoint(x: 0.4, y: 0.4),
      zoomType: .auto,
      smartKeyframes: [
        AutoFocusCameraSample(time: 2.2, center: CGPoint(x: 0.4, y: 0.4), zoomMultiplier: 1.0),
      ]
    )
    let gapGenerated = ZoomSegment(
      startTime: 3.5,
      duration: 2.0,
      zoomLevel: 2.0,
      zoomCenter: CGPoint(x: 0.6, y: 0.4),
      zoomType: .auto,
      smartKeyframes: [
        AutoFocusCameraSample(time: 3.5, center: CGPoint(x: 0.6, y: 0.4), zoomMultiplier: 1.0),
      ]
    )
    let replacementSmartGenerated = ZoomSegment(
      startTime: 8.2,
      duration: 1.6,
      zoomLevel: 2.1,
      zoomCenter: CGPoint(x: 0.8, y: 0.8),
      zoomType: .auto,
      smartKeyframes: [
        AutoFocusCameraSample(time: 8.2, center: CGPoint(x: 0.8, y: 0.8), zoomMultiplier: 1.0),
      ]
    )

    let merged = VideoEditorState.mergeSmartAutoZoomSegments(
      existing: existing,
      generated: [overlappingGenerated, gapGenerated, replacementSmartGenerated],
      policy: .fillGaps
    )
    XCTAssertEqual(merged.map(\.id), [
      manualZoom.id,
      gapGenerated.id,
      regularAutoZoom.id,
      replacementSmartGenerated.id,
    ])
    XCTAssertFalse(merged.contains { $0.id == overlappingGenerated.id })
    XCTAssertFalse(merged.contains { $0.id == previousSmartZoom.id })

    // 3. Explicit replaceAll policy replaces every segment when plan is non-empty.
    let replaced = VideoEditorState.mergeSmartAutoZoomSegments(
      existing: existing,
      generated: [overlappingGenerated, gapGenerated],
      policy: .replaceAll
    )
    XCTAssertEqual(replaced.map(\.id), [overlappingGenerated.id, gapGenerated.id])
  }

  @MainActor
  func testMovingSmartSegment_shiftsSmartKeyframesAndDoesNotFreezeCamera() throws {
    let clip = TimelineClip(
      source: .primary,
      sourceDuration: 12.0,
      sourceStart: 0.0,
      sourceEnd: 12.0
    )
    let placements = TimelineSequence.layout([clip])
    let originalKeyframes = [
      AutoFocusCameraSample(time: 1.2, center: CGPoint(x: 0.20, y: 0.25), zoomMultiplier: 1.0),
      AutoFocusCameraSample(time: 3.6, center: CGPoint(x: 0.80, y: 0.72), zoomMultiplier: 1.0),
    ]

    // Pure drag move from 1.0...4.0 to 5.0...8.0 (+4.0s source delta).
    let movedKeyframes = try XCTUnwrap(
      VideoEditorState.remapSmartKeyframes(
        originalKeyframes,
        fromOldRange: 1.0 ... 4.0,
        toNewRange: 5.0 ... 8.0,
        placements: placements
      )
    )
    XCTAssertEqual(movedKeyframes.count, 2)
    XCTAssertEqual(movedKeyframes[0].time, 5.2, accuracy: 0.001)
    XCTAssertEqual(movedKeyframes[1].time, 7.6, accuracy: 0.001)

    let movedSegment = ZoomSegment(
      startTime: 5.0,
      duration: 3.0,
      zoomLevel: 2.0,
      zoomCenter: CGPoint(x: 0.5, y: 0.5),
      zoomType: .auto,
      smartKeyframes: movedKeyframes
    )
    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 1920, height: 1080),
      samplesPerSecond: 30,
      mouseSamples: makeMouseSamples(waypoints: [(0, 0.5, 0.5), (12, 0.5, 0.5)]),
      isCursorBaked: false
    )
    let path = VideoEditorAutoFocusEngine.buildPath(from: metadata, segment: movedSegment)
    XCTAssertFalse(path.isEmpty)

    let earlyState = VideoEditorAutoFocusEngine.resolvedCameraState(
      at: 5.4,
      segments: [movedSegment],
      autoFocusPaths: [movedSegment.id: path],
      transitionDuration: ZoomCalculator.defaultTransitionDuration
    )
    let lateState = VideoEditorAutoFocusEngine.resolvedCameraState(
      at: 7.4,
      segments: [movedSegment],
      autoFocusPaths: [movedSegment.id: path],
      transitionDuration: ZoomCalculator.defaultTransitionDuration
    )
    let panDistance = hypot(lateState.center.x - earlyState.center.x, lateState.center.y - earlyState.center.y)
    XCTAssertGreaterThan(panDistance, 0.25, "Moved smart zoom must keep panning smoothly rather than clamping/freezing")

    // Resizing stretches keyframe times cleanly to fill the new range.
    let resizedKeyframes = try XCTUnwrap(
      VideoEditorState.remapSmartKeyframes(
        originalKeyframes,
        fromOldRange: 1.0 ... 4.0,
        toNewRange: 2.0 ... 8.0,
        placements: placements
      )
    )
    XCTAssertEqual(resizedKeyframes[0].time, 2.4, accuracy: 0.001)
    XCTAssertEqual(resizedKeyframes[1].time, 7.2, accuracy: 0.001)

    // Dragging onto an inserted non-primary clip returns nil to fall back to cursor-follow.
    let insertedClip = TimelineClip(
      source: .file(url: URL(fileURLWithPath: "/tmp/smart-move-inserted.mov")),
      sourceDuration: 4.0,
      sourceStart: 0.0,
      sourceEnd: 4.0
    )
    let mixedPlacements = TimelineSequence.layout([clip, insertedClip])
    let droppedOntoInserted = VideoEditorState.remapSmartKeyframes(
      originalKeyframes,
      fromOldRange: 1.0 ... 4.0,
      toNewRange: 12.5 ... 15.5,
      placements: mixedPlacements
    )
    XCTAssertNil(droppedOntoInserted)
  }

  @MainActor
  func testMapSmartSegments_splitsAcrossPrimaryClipCutsAndRemapsEditedTimeline() {
    let insertedURL = URL(fileURLWithPath: "/tmp/smart-cut-inserted.mov")

    // Edited timeline: primary [0...4], inserted [0...2], primary [6...10].
    // Sequence axis: primary1 = 0...4, inserted = 4...6, primary2 = 6...10.
    let primary1 = TimelineClip(
      source: .primary,
      sourceDuration: 10.0,
      sourceStart: 0.0,
      sourceEnd: 4.0
    )
    let inserted = TimelineClip(
      source: .file(url: insertedURL),
      sourceDuration: 2.0,
      sourceStart: 0.0,
      sourceEnd: 2.0
    )
    let primary2 = TimelineClip(
      source: .primary,
      sourceDuration: 10.0,
      sourceStart: 6.0,
      sourceEnd: 10.0
    )
    let livePlacements = TimelineSequence.layout([primary1, inserted, primary2])
    let liveDuration = livePlacements.last?.end ?? 10.0

    // Source-time segment spanning across the removed middle [4...6] and inserted clip.
    let crossCutSourceSegment = ZoomSegment(
      startTime: 2.0,
      duration: 6.0, // source 2.0...8.0
      zoomLevel: 2.0,
      zoomCenter: CGPoint(x: 0.5, y: 0.5),
      zoomType: .auto,
      smartKeyframes: [
        AutoFocusCameraSample(time: 2.0, center: CGPoint(x: 0.2, y: 0.2), zoomMultiplier: 1.0),
        AutoFocusCameraSample(time: 5.0, center: CGPoint(x: 0.5, y: 0.5), zoomMultiplier: 1.0),
        AutoFocusCameraSample(time: 8.0, center: CGPoint(x: 0.8, y: 0.8), zoomMultiplier: 1.0),
      ]
    )

    let mapped = VideoEditorState.mapSmartSegments(
      [crossCutSourceSegment],
      onto: livePlacements,
      timelineDuration: liveDuration
    )

    // Must split into two distinct segments across both overlapping primary clips,
    // aligned accurately around the inserted 2s clip.
    XCTAssertEqual(mapped.count, 2)
    XCTAssertNotEqual(mapped[0].id, mapped[1].id)

    XCTAssertEqual(mapped[0].startTime, 2.0, accuracy: 0.001)
    XCTAssertEqual(mapped[0].endTime, 4.0, accuracy: 0.001)
    XCTAssertEqual(mapped[0].smartKeyframes?.first?.time ?? -1, 2.0, accuracy: 0.001)
    XCTAssertEqual(mapped[0].smartKeyframes?.last?.time ?? -1, 4.0, accuracy: 0.001)

    XCTAssertEqual(mapped[1].startTime, 6.0, accuracy: 0.001)
    XCTAssertEqual(mapped[1].endTime, 8.0, accuracy: 0.001)
    XCTAssertEqual(mapped[1].smartKeyframes?.first?.time ?? -1, 6.0, accuracy: 0.001)
    XCTAssertEqual(mapped[1].smartKeyframes?.last?.time ?? -1, 8.0, accuracy: 0.001)
  }

  @MainActor
  func testMapSmartSegments_coalescesAcrossSplitPrimaryClipsWithoutDoubleZoom() {
    // User splits a 12s recording at 8.35s with `S` (two adjacent primary clips: 0...8.35 and 8.35...12.0).
    let primaryLeft = TimelineClip(
      source: .primary,
      sourceDuration: 12.0,
      sourceStart: 0.0,
      sourceEnd: 8.35
    )
    let primaryRight = TimelineClip(
      source: .primary,
      sourceDuration: 12.0,
      sourceStart: 8.35,
      sourceEnd: 12.0
    )
    let splitPlacements = TimelineSequence.layout([primaryLeft, primaryRight])
    let duration = TimelineSequence.duration([primaryLeft, primaryRight])

    let segmentAcrossSplit = ZoomSegment(
      startTime: 6.6,
      duration: 2.9, // 6.6...9.5 across the 8.35 split seam
      zoomLevel: 2.0,
      zoomCenter: CGPoint(x: 0.4, y: 0.5),
      zoomType: .auto,
      smartKeyframes: [
        AutoFocusCameraSample(time: 6.6, center: CGPoint(x: 0.4, y: 0.5), zoomMultiplier: 1.0),
        AutoFocusCameraSample(time: 9.5, center: CGPoint(x: 0.45, y: 0.52), zoomMultiplier: 1.0),
      ]
    )

    let mapped = VideoEditorState.mapSmartSegments(
      [segmentAcrossSplit],
      onto: splitPlacements,
      timelineDuration: duration
    )

    // Must produce ONE continuous zoom segment (6.6...9.5), never two touching blocks at 8.35.
    XCTAssertEqual(mapped.count, 1, "Splitting a primary clip must not split a continuous zoom into two double-zooming blocks")
    XCTAssertEqual(mapped[0].startTime, 6.6, accuracy: 0.001)
    XCTAssertEqual(mapped[0].endTime, 9.5, accuracy: 0.001)
  }

  func testLegacyTransitionPresetMigration_snapsStoredPresetsToUpdatedValues() {
    XCTAssertEqual(
      ZoomCalculator.migrateLegacyTransitionDuration(0.25),
      ZoomCalculator.fastTransitionDuration,
      accuracy: 0.0001
    )
    XCTAssertEqual(
      ZoomCalculator.migrateLegacyTransitionDuration(0.40),
      ZoomCalculator.balancedTransitionDuration,
      accuracy: 0.0001
    )
    XCTAssertEqual(
      ZoomCalculator.migrateLegacyTransitionDuration(0.60),
      ZoomCalculator.smoothTransitionDuration,
      accuracy: 0.0001
    )
    // Custom non-preset values are preserved (clamped to valid range).
    XCTAssertEqual(
      ZoomCalculator.migrateLegacyTransitionDuration(0.45),
      0.45,
      accuracy: 0.0001
    )
  }
}
