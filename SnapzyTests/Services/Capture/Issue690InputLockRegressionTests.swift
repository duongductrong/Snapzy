//
//  Issue690InputLockRegressionTests.swift
//  SnapzyTests
//
//  Regression coverage for https://github.com/duongductrong/Snapzy/issues/690: the live
//  passthrough tap re-enabled itself after every WindowServer timeout, so a stalled main
//  thread kept pointer and keyboard input locked system-wide until a forced shutdown. The
//  tap now stays disabled and ends the session, and every session has a hard time limit.
//

import AppKit
import CoreGraphics
@testable import Snapzy
import XCTest

final class Issue690InputLockRegressionTests: XCTestCase {
  /// `nonisolated`: under the target's default MainActor isolation this class would get an
  /// isolated deinit, which on macOS 15 runs through the
  /// `swift_task_deinitOnExecutorMainActorBackDeploy` shim and double-frees an object that
  /// still has `unowned` references outstanding (CI crash).
  private nonisolated final class Env {
    var enabledStates: [Bool] = []
    var deadlines: [DispatchWorkItem] = []

    func deps() -> CaptureEventTapDependencies {
      CaptureEventTapDependencies(
        isAccessibilityTrusted: { true },
        createTap: { _, _ in
          var context = CFMachPortContext()
          return CFMachPortCreate(nil, { _, _, _, _ in }, &context, nil)
        },
        createRunLoopSource: { CFMachPortCreateRunLoopSource(nil, unsafeDowncast($0, to: CFMachPort.self), 0) },
        setTapEnabled: { [unowned self] _, enabled in enabledStates.append(enabled) },
        invalidateTap: { CFMachPortInvalidate(unsafeDowncast($0, to: CFMachPort.self)) },
        scheduleDeadline: { [unowned self] _, work in deadlines.append(work) }
      )
    }
  }

  override func tearDown() {
    AreaSelectionController.shared.cancelSelection()
    super.tearDown()
  }

  private func mouseMoved() throws -> CGEvent {
    try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: .zero, mouseButton: .left))
  }

  private func key(_ code: CGKeyCode, flags: CGEventFlags = []) throws -> CGEvent {
    let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true))
    event.flags = flags
    return event
  }

  private func drainMainQueue() {
    let drained = expectation(description: "main queue drained")
    DispatchQueue.main.async { drained.fulfill() }
    wait(for: [drained], timeout: 2)
  }

  // MARK: - Tap layer

  /// A stalled main thread produces a stream of timeouts; none may re-arm the tap, and
  /// even with no delegate left the tap unregisters itself.
  func testTap_repeatedTimeouts_neverReenableAndTapTearsDownWithoutDelegate() throws {
    let env = Env()
    let tap = CaptureEventTapController(dependencies: env.deps())
    XCTAssertTrue(tap.start())
    XCTAssertNil(tap.delegate)

    for _ in 0..<50 {
      _ = tap.handleTapEvent(type: .tapDisabledByTimeout, event: try mouseMoved())
    }
    drainMainQueue()

    XCTAssertEqual(env.enabledStates.filter { $0 }.count, 1, "only the initial enable")
    XCTAssertFalse(tap.isRunning)
    withExtendedLifetime(env) {} // outlive the tap's unowned captures
  }

  /// The deadline disables the tap on its own (background) queue, so input is released
  /// even if the main run loop never gets to tearing the session down.
  func testTap_sessionDeadline_releasesInputWithoutMainThread() throws {
    let env = Env()
    let tap = CaptureEventTapController(dependencies: env.deps())
    XCTAssertTrue(tap.start())
    let work = try XCTUnwrap(env.deadlines.first)

    let ran = expectation(description: "deadline ran")
    DispatchQueue.global().async {
      work.perform()
      ran.fulfill()
    }
    wait(for: [ran], timeout: 2)

    XCTAssertEqual(env.enabledStates.last, false)
    tap.stop()
    withExtendedLifetime(env) {} // outlive the tap's unowned captures
  }

  // MARK: - Session (real AreaSelectionController)

  private func startPassthroughSession(
    completion: @escaping AreaSelectionResultCompletion = { _ in }
  ) throws -> AreaSelectionController {
    try skipIfRunningInCI("Presents real overlay windows")
    let controller = AreaSelectionController.shared
    controller.startSelection(mode: .screenshot, backdrops: [:], completion: completion)
    guard !NSScreen.screens.isEmpty else { throw XCTSkip("no screens") }
    // Marks the session as tap-driven (test hook); 'x' is consumed and changes nothing else.
    XCTAssertTrue(controller.testHandleLivePassthroughKey(try key(7)))
    return controller
  }

  func testSession_tapTimeout_cancelsSession() throws {
    var cancelled = false
    let controller = try startPassthroughSession { cancelled = $0 == nil }

    controller.eventTapDidStop(reason: .disabledByTimeout)

    XCTAssertTrue(cancelled)
    XCTAssertFalse(controller.isPresenting)
  }

  func testSession_timeLimit_cancelsSession() throws {
    var cancelled = false
    let controller = try startPassthroughSession { cancelled = $0 == nil }

    controller.eventTapDidStop(reason: .sessionTimeLimit)

    XCTAssertTrue(cancelled)
    XCTAssertFalse(controller.isPresenting)
  }

  /// ⌘⌥Esc is matched as Esc, so a responsive session always lets the user out with it.
  func testSession_commandOptionEscape_cancelsSession() throws {
    var cancelled = false
    let controller = try startPassthroughSession { cancelled = $0 == nil }

    XCTAssertTrue(controller.testHandleLivePassthroughKey(try key(53, flags: [.maskCommand, .maskAlternate])))

    XCTAssertTrue(cancelled)
    XCTAssertFalse(controller.isPresenting)
  }
}
