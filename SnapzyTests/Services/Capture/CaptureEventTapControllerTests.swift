//
//  CaptureEventTapControllerTests.swift
//  SnapzyTests
//
//  Unit tests for CaptureEventTapController: start/stop state machine,
//  delegate routing via the factory seam, and the permission-denied path.
//

import CoreGraphics
@testable import Snapzy
import XCTest

final class CaptureEventTapControllerTests: XCTestCase {
  private final class DelegateSpy: CaptureEventTapDelegate {
    var movedPoints: [CGPoint] = []
    var buttonEvents: [(CaptureButtonEvent, CGPoint)] = []
    var keyEvents: [CaptureKeyEvent] = []
    var scrollEvents: [(deltaY: CGFloat, hasPreciseScrollingDeltas: Bool, isCommandDown: Bool)] = []

    func eventTapDidObserveMouseMoved(at screenPoint: CGPoint) {
      movedPoints.append(screenPoint)
    }

    func eventTapDidReceiveButton(_ kind: CaptureButtonEvent, at screenPoint: CGPoint) {
      buttonEvents.append((kind, screenPoint))
    }

    func eventTapDidReceiveKey(_ key: CaptureKeyEvent) {
      keyEvents.append(key)
    }

    func eventTapDidReceiveScroll(deltaY: CGFloat, hasPreciseScrollingDeltas: Bool, isCommandDown: Bool) {
      scrollEvents.append((deltaY, hasPreciseScrollingDeltas, isCommandDown))
    }
  }

  /// Records dependency calls. The tap handle is a real local `CFMachPort` so
  /// the run-loop-source seam can produce a genuine source without a real tap.
  private final class FakeEnvironment {
    var isTrusted = true
    var createsTap = true
    var createTapCallCount = 0
    var enabledStates: [Bool] = []
    var port: CFMachPort?

    func makeDependencies() -> CaptureEventTapDependencies {
      CaptureEventTapDependencies(
        isAccessibilityTrusted: { [unowned self] in isTrusted },
        createTap: { [unowned self] _, _ in
          createTapCallCount += 1
          guard createsTap else { return nil }
          var context = CFMachPortContext()
          let port = CFMachPortCreate(nil, { _, _, _, _ in }, &context, nil)
          self.port = port
          return port
        },
        createRunLoopSource: { tap in
          CFMachPortCreateRunLoopSource(nil, unsafeDowncast(tap, to: CFMachPort.self), 0)
        },
        setTapEnabled: { [unowned self] _, enabled in
          enabledStates.append(enabled)
        }
      )
    }
  }

  private var environment: FakeEnvironment!
  private var controller: CaptureEventTapController!
  private var delegate: DelegateSpy!

  override func setUp() {
    super.setUp()
    environment = FakeEnvironment()
    controller = CaptureEventTapController(dependencies: environment.makeDependencies())
    delegate = DelegateSpy()
    controller.delegate = delegate
  }

  override func tearDown() {
    controller.stop()
    controller = nil
    environment = nil
    delegate = nil
    super.tearDown()
  }

  // MARK: - Availability

  func testIsAvailable_reflectsPermissionChecker() {
    environment.isTrusted = true
    XCTAssertTrue(controller.isAvailable)
    environment.isTrusted = false
    XCTAssertFalse(controller.isAvailable)
  }

  // MARK: - Start/Stop State Machine

  func testStart_createsTapAndMarksRunning() {
    XCTAssertTrue(controller.start())
    XCTAssertTrue(controller.isRunning)
    XCTAssertEqual(environment.createTapCallCount, 1)
    XCTAssertEqual(environment.enabledStates, [true])
  }

  func testStart_whenAlreadyRunning_isNoOp() {
    XCTAssertTrue(controller.start())
    XCTAssertTrue(controller.start())
    XCTAssertEqual(environment.createTapCallCount, 1)
  }

  func testStart_whenPermissionDenied_returnsFalseAndCreatesNoTap() {
    environment.isTrusted = false
    XCTAssertFalse(controller.start())
    XCTAssertFalse(controller.isRunning)
    XCTAssertEqual(environment.createTapCallCount, 0)
  }

  func testStart_whenTapCreationFails_returnsFalseAndNotRunning() {
    environment.createsTap = false
    XCTAssertFalse(controller.start())
    XCTAssertFalse(controller.isRunning)
  }

  func testStop_whenNotRunning_isNoOp() {
    controller.stop()
    XCTAssertTrue(environment.enabledStates.isEmpty)
  }

  func testStop_disablesTapAndClearsRunning() {
    controller.start()
    controller.stop()
    XCTAssertFalse(controller.isRunning)
    XCTAssertEqual(environment.enabledStates, [true, false])
  }

  func testStop_thenStart_restartsCleanly() {
    controller.start()
    controller.stop()
    XCTAssertTrue(controller.start())
    XCTAssertTrue(controller.isRunning)
    XCTAssertEqual(environment.createTapCallCount, 2)
  }

  // MARK: - Delegate Routing

  func testHandleTapEvent_mouseMoved_isConsumedButNotifiesDelegate() throws {
    let point = CGPoint(x: 100, y: 200)
    let event = try XCTUnwrap(CGEvent(
      mouseEventSource: nil,
      mouseType: .mouseMoved,
      mouseCursorPosition: point,
      mouseButton: .left
    ))

    let result = controller.handleTapEvent(type: .mouseMoved, event: event)

    XCTAssertNil(result, "mouseMoved should be consumed after observation")
    XCTAssertEqual(delegate.movedPoints, [point])
    XCTAssertTrue(delegate.buttonEvents.isEmpty)
  }

  func testHandleTapEvent_buttonEvents_areConsumedAndRouted() throws {
    let point = CGPoint(x: 10, y: 20)
    let cases: [(CGEventType, CaptureButtonEvent)] = [
      (.leftMouseDown, .leftMouseDown),
      (.leftMouseUp, .leftMouseUp),
      (.leftMouseDragged, .leftMouseDragged),
      (.rightMouseDown, .rightMouseDown),
      (.rightMouseUp, .rightMouseUp),
      (.rightMouseDragged, .rightMouseDragged),
    ]

    for (eventType, _) in cases {
      let event = try XCTUnwrap(CGEvent(
        mouseEventSource: nil,
        mouseType: eventType,
        mouseCursorPosition: point,
        mouseButton: .left
      ))
      let result = controller.handleTapEvent(type: eventType, event: event)
      XCTAssertNil(result, "\(eventType) should be consumed")
    }

    XCTAssertEqual(delegate.buttonEvents.map(\.0), cases.map(\.1))
    XCTAssertTrue(delegate.buttonEvents.allSatisfy { $0.1 == point })
  }

  func testHandleTapEvent_keyDown_routesMappedKeysAndConsumes() throws {
    let cases: [(UInt16, CaptureKeyEvent)] = [
      (53, .escape),
      (126, .arrowUp),
      (125, .arrowDown),
      (123, .arrowLeft),
      (124, .arrowRight),
      (36, .return),
      (76, .return),
    ]

    for (keyCode, _) in cases {
      let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true))
      let result = controller.handleTapEvent(type: .keyDown, event: event)
      XCTAssertNil(result, "keyDown \(keyCode) should be consumed")
    }

    XCTAssertEqual(delegate.keyEvents, cases.map(\.1))
  }

  func testHandleTapEvent_keyDown_unmappedKey_passesThroughButNotRouted() throws {
    let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)) // 'a'

    let result = controller.handleTapEvent(type: .keyDown, event: event)

    XCTAssertNotNil(result)
    XCTAssertTrue(delegate.keyEvents.isEmpty)
  }

  func testHandleTapEvent_scrollWheel_isConsumedByDefault() throws {
    XCTAssertTrue(CaptureEventTapController.consumesScrollWheelEvents)
    let event = try XCTUnwrap(CGEvent(
      scrollWheelEvent2Source: nil,
      units: .line,
      wheelCount: 1,
      wheel1: 1,
      wheel2: 0,
      wheel3: 0
    ))

    let result = controller.handleTapEvent(type: .scrollWheel, event: event)

    XCTAssertNil(result)
  }

  func testHandleTapEvent_scrollWheel_notifiesDelegateWithWheelNotchDelta() throws {
    let event = try XCTUnwrap(CGEvent(
      scrollWheelEvent2Source: nil,
      units: .line,
      wheelCount: 1,
      wheel1: -1,
      wheel2: 0,
      wheel3: 0
    ))

    let result = controller.handleTapEvent(type: .scrollWheel, event: event)

    XCTAssertNil(result, "scrollWheel stays consumed after observation")
    XCTAssertEqual(delegate.scrollEvents.count, 1)
    XCTAssertEqual(delegate.scrollEvents.first?.deltaY, -1)
    XCTAssertEqual(delegate.scrollEvents.first?.hasPreciseScrollingDeltas, false)
    XCTAssertEqual(delegate.scrollEvents.first?.isCommandDown, false)
  }

  func testHandleTapEvent_scrollWheel_preciseDeltaAndCommandFlag_areForwarded() throws {
    let event = try XCTUnwrap(CGEvent(
      scrollWheelEvent2Source: nil,
      units: .pixel,
      wheelCount: 1,
      wheel1: 12,
      wheel2: 0,
      wheel3: 0
    ))
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 12)
    event.flags = .maskCommand

    let result = controller.handleTapEvent(type: .scrollWheel, event: event)

    XCTAssertNil(result, "scrollWheel stays consumed after observation")
    XCTAssertEqual(delegate.scrollEvents.count, 1)
    XCTAssertEqual(delegate.scrollEvents.first?.deltaY, 12)
    XCTAssertEqual(delegate.scrollEvents.first?.hasPreciseScrollingDeltas, true)
    XCTAssertEqual(delegate.scrollEvents.first?.isCommandDown, true)
  }

  // MARK: - Tap Disabled Recovery

  func testHandleTapEvent_tapDisabledByTimeout_reenablesTap() throws {
    controller.start()
    let event = try XCTUnwrap(CGEvent(
      mouseEventSource: nil,
      mouseType: .mouseMoved,
      mouseCursorPosition: .zero,
      mouseButton: .left
    ))

    _ = controller.handleTapEvent(type: .tapDisabledByTimeout, event: event)

    XCTAssertEqual(environment.enabledStates, [true, true])
  }

  func testHandleTapEvent_tapDisabledByUserInput_reenablesTap() throws {
    controller.start()
    let event = try XCTUnwrap(CGEvent(
      mouseEventSource: nil,
      mouseType: .mouseMoved,
      mouseCursorPosition: .zero,
      mouseButton: .left
    ))

    _ = controller.handleTapEvent(type: .tapDisabledByUserInput, event: event)

    XCTAssertEqual(environment.enabledStates, [true, true])
  }

  // MARK: - Event Mask

  func testEventMask_coversRequiredEventTypes() {
    let mask = CaptureEventTapController.eventMask
    let required: [CGEventType] = [
      .mouseMoved,
      .leftMouseDown, .leftMouseUp, .leftMouseDragged,
      .rightMouseDown, .rightMouseUp, .rightMouseDragged,
      .keyDown,
      .scrollWheel,
    ]
    for eventType in required {
      XCTAssertNotEqual(mask & (CGEventMask(1) << CGEventMask(eventType.rawValue)), 0, "\(eventType) missing from mask")
    }
  }
}
