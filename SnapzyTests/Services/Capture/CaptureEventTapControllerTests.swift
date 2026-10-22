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
    var keyEvents: [(type: CGEventType, keyCode: Int64)] = []
    var consumesKeys = true
    var scrollEvents: [(deltaY: CGFloat, hasPreciseScrollingDeltas: Bool, isCommandDown: Bool)] = []

    func eventTapDidObserveMouseMoved(at screenPoint: CGPoint) {
      movedPoints.append(screenPoint)
    }

    func eventTapDidReceiveButton(_ kind: CaptureButtonEvent, at screenPoint: CGPoint) {
      buttonEvents.append((kind, screenPoint))
    }

    func eventTapShouldConsumeKeyEvent(_ event: CGEvent) -> Bool {
      keyEvents.append((event.type, event.getIntegerValueField(.keyboardEventKeycode)))
      return consumesKeys
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
    var createsRunLoopSource = true
    var createTapCallCount = 0
    var enabledStates: [Bool] = []
    var invalidatedTaps: [CFMachPort] = []
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
        createRunLoopSource: { [unowned self] tap in
          guard createsRunLoopSource else { return nil }
          return CFMachPortCreateRunLoopSource(nil, unsafeDowncast(tap, to: CFMachPort.self), 0)
        },
        setTapEnabled: { [unowned self] _, enabled in
          enabledStates.append(enabled)
        },
        invalidateTap: { [unowned self] tap in
          let port = unsafeDowncast(tap, to: CFMachPort.self)
          invalidatedTaps.append(port)
          CFMachPortInvalidate(port)
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

  // MARK: - Tap Teardown (issue #566)

  func testStop_invalidatesTapPort() throws {
    controller.start()
    let port = try XCTUnwrap(environment.port)
    controller.stop()
    XCTAssertEqual(environment.invalidatedTaps.count, 1)
    XCTAssertTrue(environment.invalidatedTaps.first === port)
    XCTAssertFalse(CFMachPortIsValid(port))
  }

  func testStop_calledTwice_invalidatesOnce() {
    controller.start()
    controller.stop()
    controller.stop()
    XCTAssertEqual(environment.invalidatedTaps.count, 1)
  }

  func testStop_whenNotRunning_invalidatesNothing() {
    controller.stop()
    XCTAssertTrue(environment.invalidatedTaps.isEmpty)
  }

  func testRepeatedSessions_invalidateEveryCreatedTap() {
    for _ in 0..<50 {
      XCTAssertTrue(controller.start())
      controller.stop()
    }
    XCTAssertEqual(environment.createTapCallCount, 50)
    XCTAssertEqual(environment.invalidatedTaps.count, 50)
    XCTAssertTrue(environment.invalidatedTaps.allSatisfy { !CFMachPortIsValid($0) })
  }

  func testStart_whenRunLoopSourceCreationFails_invalidatesTap() throws {
    environment.createsRunLoopSource = false
    XCTAssertFalse(controller.start())
    XCTAssertFalse(controller.isRunning)
    let port = try XCTUnwrap(environment.port)
    XCTAssertEqual(environment.invalidatedTaps.count, 1)
    XCTAssertFalse(CFMachPortIsValid(port))
  }

  func testDeinit_whileRunning_invalidatesTap() throws {
    controller.start()
    let port = try XCTUnwrap(environment.port)
    controller = nil
    XCTAssertEqual(environment.invalidatedTaps.count, 1)
    XCTAssertFalse(CFMachPortIsValid(port))
    controller = CaptureEventTapController(dependencies: environment.makeDependencies())
  }

  /// End-to-end against the window server: the live teardown must leave no tap
  /// registered for this process. Uses a listen-only mouse tap (no
  /// Accessibility permission needed) with the live run-loop/enable/invalidate
  /// seams, so it exercises the same CF lifecycle as the production tap.
  func testLiveTap_repeatedSessions_leaveNoRegisteredTaps() throws {
    var live = CaptureEventTapDependencies.live(eventMask: CaptureEventTapController.eventMask)
    live.isAccessibilityTrusted = { true }
    live.createTap = { callback, userInfo in
      CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: CGEventMask(1) << CGEventMask(CGEventType.mouseMoved.rawValue),
        callback: callback,
        userInfo: userInfo
      )
    }
    let liveController = CaptureEventTapController(dependencies: live)
    let baseline = Self.registeredTapCountForCurrentProcess()

    for _ in 0..<5 {
      guard liveController.start() else {
        throw XCTSkip("Window server event taps unavailable in this environment")
      }
      XCTAssertEqual(Self.registeredTapCountForCurrentProcess(), baseline + 1)
      liveController.stop()
    }

    XCTAssertEqual(Self.registeredTapCountForCurrentProcess(), baseline)
  }

  private static func registeredTapCountForCurrentProcess() -> Int {
    var count: UInt32 = 0
    CGGetEventTapList(0, nil, &count)
    var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
    CGGetEventTapList(count, &taps, &count)
    let pid = getpid()
    return taps.prefix(Int(count)).filter { $0.tappingProcess == pid }.count
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

  func testHandleTapEvent_keyEvents_areRoutedAndConsumedWhenDelegateClaimsThem() throws {
    for (keyCode, keyDown) in [(53, true), (49, true), (49, false), (0, true)] as [(UInt16, Bool)] {
      let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown))
      let result = controller.handleTapEvent(type: keyDown ? .keyDown : .keyUp, event: event)
      XCTAssertNil(result, "key \(keyCode) \(keyDown ? "down" : "up") should be consumed")
    }

    XCTAssertEqual(delegate.keyEvents.map(\.keyCode), [53, 49, 49, 0])
    XCTAssertEqual(delegate.keyEvents.map(\.type), [.keyDown, .keyDown, .keyUp, .keyDown])
  }

  func testHandleTapEvent_keyEvent_passesThroughWhenDelegateDeclines() throws {
    delegate.consumesKeys = false
    let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)) // 'a'

    let result = controller.handleTapEvent(type: .keyDown, event: event)

    XCTAssertNotNil(result)
    XCTAssertEqual(delegate.keyEvents.count, 1)
  }

  func testHandleTapEvent_keyEvent_withoutDelegate_passesThrough() throws {
    controller.delegate = nil
    let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true))

    XCTAssertNotNil(controller.handleTapEvent(type: .keyDown, event: event))
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
      .keyDown, .keyUp,
      .scrollWheel,
    ]
    for eventType in required {
      XCTAssertNotEqual(mask & (CGEventMask(1) << CGEventMask(eventType.rawValue)), 0, "\(eventType) missing from mask")
    }
  }
}
