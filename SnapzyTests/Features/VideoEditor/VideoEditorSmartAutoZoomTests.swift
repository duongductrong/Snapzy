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
}
