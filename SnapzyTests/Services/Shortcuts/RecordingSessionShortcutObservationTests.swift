//
//  RecordingSessionShortcutObservationTests.swift
//  SnapzyTests
//
//  Integration tests for the production observation path behind recording-session
//  shortcut gating: KeyboardShortcutManager re-registers session-scoped shortcuts
//  (toggle pen, pause/resume, restart, delete) when ScreenRecordingManager.$state
//  transitions to/from a non-idle session.
//
//  Unlike `RecordingSessionShortcutGatingTests` / `RecordingSessionHotkeyRegistrationTests`,
//  these tests never stub `isRecordingSessionActive` and never call
//  `refreshShortcutRegistration()` manually — the registration refresh must be driven
//  by the real `ScreenRecordingManager.$state` publisher, exactly as in the app.
//

import AppKit
import Carbon.HIToolbox
import Combine
import XCTest
@testable import Snapzy

final class RecordingSessionShortcutObservationTests: XCTestCase {

  /// Exotic combo (Ctrl+Option+Shift+Cmd+F18) — no system/app should hold it.
  private let sessionProbeConfig = ShortcutConfig(
    keyCode: UInt32(kVK_F18),
    modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
  )

  private func probeHotkeyID() -> EventHotKeyID {
    EventHotKeyID(signature: OSType(0x5A54_4F42), id: 981)  // "ZTOB"
  }

  @discardableResult
  private func probeRegister(_ config: ShortcutConfig) -> (status: OSStatus, ref: EventHotKeyRef?) {
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      config.keyCode,
      config.modifiers,
      probeHotkeyID(),
      GetApplicationEventTarget(),
      0,
      &ref
    )
    return (status, ref)
  }

  private func assertComboHeld(_ config: ShortcutConfig, _ message: String) {
    let probe = probeRegister(config)
    XCTAssertEqual(probe.status, OSStatus(-9878), message)  // eventHotKeyExistsErr
    if let ref = probe.ref { UnregisterEventHotKey(ref) }
  }

  private func assertComboFree(_ config: ShortcutConfig, _ message: String) {
    let probe = probeRegister(config)
    XCTAssertEqual(probe.status, noErr, message)
    if let ref = probe.ref { UnregisterEventHotKey(ref) }
  }

  @MainActor
  private func preserveManagerState(of manager: KeyboardShortcutManager) {
    let wasEnabled = manager.isEnabled
    let originalConfig = manager.shortcut(for: .togglePenRecording)
    let originalEnabled = manager.isShortcutEnabled(for: .togglePenRecording)
    addTeardownBlock { @MainActor in
      manager.setTogglePenRecordingShortcut(originalConfig)
      manager.setShortcutEnabled(originalEnabled, for: .togglePenRecording)
      ScreenRecordingManager.shared.setStateForTesting(.idle)
      wasEnabled ? manager.enable() : manager.disable()
    }
  }

  @MainActor
  private func requireFreeProbe(_ config: ShortcutConfig) throws {
    let pre = probeRegister(config)
    guard pre.status == noErr else {
      throw XCTSkip("Probe combo unexpectedly held before test (status \(pre.status))")
    }
    UnregisterEventHotKey(pre.ref!)
  }

  /// The regression scenario for issue #517: bind the toggle-pen shortcut while
  /// Snapzy is idle, start a recording session, press the combo — the Carbon
  /// registration must appear purely from the $state observation, with no
  /// manual refresh.
  @MainActor
  func testTogglePenShortcut_becomesRegisteredWhenRecordingSessionStarts() throws {
    try skipIfRunningInCI("Carbon hotkey registration is unsupported on headless CI runners")
    let manager = KeyboardShortcutManager.shared
    preserveManagerState(of: manager)
    try requireFreeProbe(sessionProbeConfig)

    manager.enable()
    // Snapzy idle: session-scoped kind must not hold its combo.
    XCTAssertFalse(manager.shouldRegisterNow(for: .togglePenRecording))

    manager.setTogglePenRecordingShortcut(sessionProbeConfig)
    manager.setShortcutEnabled(true, for: .togglePenRecording)
    assertComboFree(
      sessionProbeConfig,
      "Toggle-pen shortcut must not hold its combo while no recording session is active"
    )

    // Start a recording session the way the recorder does: a state transition
    // on the live ScreenRecordingManager publisher (preparing → recording).
    ScreenRecordingManager.shared.setStateForTesting(.preparing)
    assertComboHeld(
      sessionProbeConfig,
      "Toggle-pen shortcut must hold its combo as soon as the recording session starts — registration must be driven by the real $state publisher"
    )

    ScreenRecordingManager.shared.setStateForTesting(.recording)
    assertComboHeld(
      sessionProbeConfig,
      "Toggle-pen shortcut must keep its combo while the session is recording"
    )
  }

  /// The session end path: the combo must be released without any manual refresh.
  @MainActor
  func testTogglePenShortcut_releasedWhenRecordingSessionEnds() throws {
    try skipIfRunningInCI("Carbon hotkey registration is unsupported on headless CI runners")
    let manager = KeyboardShortcutManager.shared
    preserveManagerState(of: manager)
    try requireFreeProbe(sessionProbeConfig)

    manager.enable()
    manager.setTogglePenRecordingShortcut(sessionProbeConfig)
    manager.setShortcutEnabled(true, for: .togglePenRecording)

    ScreenRecordingManager.shared.setStateForTesting(.recording)
    assertComboHeld(sessionProbeConfig, "Precondition: active session holds the bound combo")

    ScreenRecordingManager.shared.setStateForTesting(.idle)
    assertComboFree(
      sessionProbeConfig,
      "Toggle-pen shortcut must release its combo when the recording session ends"
    )
  }

  /// Paused sessions are still active sessions: the combo must stay held.
  @MainActor
  func testTogglePenShortcut_staysRegisteredWhilePaused() throws {
    try skipIfRunningInCI("Carbon hotkey registration is unsupported on headless CI runners")
    let manager = KeyboardShortcutManager.shared
    preserveManagerState(of: manager)
    try requireFreeProbe(sessionProbeConfig)

    manager.enable()
    manager.setTogglePenRecordingShortcut(sessionProbeConfig)
    manager.setShortcutEnabled(true, for: .togglePenRecording)

    ScreenRecordingManager.shared.setStateForTesting(.recording)
    ScreenRecordingManager.shared.setStateForTesting(.paused)
    assertComboHeld(
      sessionProbeConfig,
      "Toggle-pen shortcut must stay registered while the session is paused"
    )
  }

  /// The pause/resume shortcut shares the same observation path; cover it as the
  /// sibling session kind so a future regression cannot split the kinds apart.
  @MainActor
  func testPauseResumeShortcut_becomesRegisteredWhenRecordingSessionStarts() throws {
    try skipIfRunningInCI("Carbon hotkey registration is unsupported on headless CI runners")
    let manager = KeyboardShortcutManager.shared
    let wasEnabled = manager.isEnabled
    let originalConfig = manager.shortcut(for: .pauseResumeRecording)
    let originalEnabled = manager.isShortcutEnabled(for: .pauseResumeRecording)
    addTeardownBlock { @MainActor in
      manager.setPauseResumeRecordingShortcut(originalConfig)
      manager.setShortcutEnabled(originalEnabled, for: .pauseResumeRecording)
      ScreenRecordingManager.shared.setStateForTesting(.idle)
      wasEnabled ? manager.enable() : manager.disable()
    }
    try requireFreeProbe(sessionProbeConfig)

    manager.enable()
    manager.setPauseResumeRecordingShortcut(sessionProbeConfig)
    manager.setShortcutEnabled(true, for: .pauseResumeRecording)
    assertComboFree(
      sessionProbeConfig,
      "Pause/resume shortcut must not hold its combo while no recording session is active"
    )

    ScreenRecordingManager.shared.setStateForTesting(.recording)
    assertComboHeld(
      sessionProbeConfig,
      "Pause/resume shortcut must hold its combo while a recording session is active"
    )
  }

  /// A failed prepare (state snapping back to idle) must not leave the combo held.
  @MainActor
  func testTogglePenShortcut_releasedWhenPrepareFailsBackToIdle() throws {
    try skipIfRunningInCI("Carbon hotkey registration is unsupported on headless CI runners")
    let manager = KeyboardShortcutManager.shared
    preserveManagerState(of: manager)
    try requireFreeProbe(sessionProbeConfig)

    manager.enable()
    manager.setTogglePenRecordingShortcut(sessionProbeConfig)
    manager.setShortcutEnabled(true, for: .togglePenRecording)

    ScreenRecordingManager.shared.setStateForTesting(.preparing)
    assertComboHeld(sessionProbeConfig, "Precondition: preparing session holds the bound combo")

    ScreenRecordingManager.shared.setStateForTesting(.idle)
    assertComboFree(
      sessionProbeConfig,
      "A prepare failure snapping back to idle must release the combo"
    )
  }
}

// MARK: - @Published emission semantics (load-bearing for the observation fix)

/// Pins the Combine semantics the session-gating observation depends on:
/// `@Published` delivers its event on `willSet` — the emitted value is the new
/// state, but the property itself still holds the PREVIOUS value at delivery
/// time. `KeyboardShortcutManager` must therefore act on the emitted value, not
/// on a fresh `ScreenRecordingManager.shared.isActive` read inside the sink.
@MainActor
final class PublishedRecordingStateEmissionTests: XCTestCase {

  private var cancellables = Set<AnyCancellable>()

  override func tearDown() {
    cancellables.removeAll()
    ScreenRecordingManager.shared.setStateForTesting(.idle)
    super.tearDown()
  }

  func testProjectedPublisher_emitsNewValueBeforePropertyCommits() {
    let manager = ScreenRecordingManager.shared
    let emitted: [Bool] = []
    let propertyReadsAtDelivery: [Bool] = []
    var emittedValues = emitted
    var propertyValues = propertyReadsAtDelivery

    manager.$state
      .map { $0 != .idle }
      .removeDuplicates()
      .sink { active in
        emittedValues.append(active)
        // What the (buggy) re-read inside the sink would observe:
        propertyValues.append(manager.isActive)
      }
      .store(in: &cancellables)

    XCTAssertEqual(emittedValues, [false], "Subscription emits the current value immediately")

    manager.setStateForTesting(.preparing)

    XCTAssertEqual(
      emittedValues,
      [false, true],
      "The emitted value must be the committed new state"
    )
    XCTAssertEqual(
      propertyValues,
      [false, false],
      "At delivery time the property still holds the previous value — re-reading it inside the sink is stale by exactly one transition"
    )

    manager.setStateForTesting(.idle)

    XCTAssertEqual(emittedValues, [false, true, false], "The idle transition must also emit")
  }
}
