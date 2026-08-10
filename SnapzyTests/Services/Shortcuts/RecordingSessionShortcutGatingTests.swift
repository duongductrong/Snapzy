//
//  RecordingSessionShortcutGatingTests.swift
//  SnapzyTests
//
//  Unit tests for recording-session gating of global shortcuts:
//  the four recording-session kinds (pause/resume, toggle pen, restart,
//  delete) must hold a global registration only while a recording session
//  is active, so their combos stay free for other apps while Snapzy is idle.
//
//  `RecordingSessionShortcutGatingTests` exercises the registration decision
//  and Fn-binding bookkeeping through the `isRecordingSessionActive` seam.
//  `RecordingSessionHotkeyRegistrationTests` verifies the same gating at the
//  Carbon level with probe registrations (mirrors HotkeyUnregistrationTests).
//

import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Snapzy

final class RecordingSessionShortcutGatingTests: XCTestCase {

  private static let sessionKinds: [GlobalShortcutKind] = [
    .pauseResumeRecording,
    .togglePenRecording,
    .restartRecording,
    .deleteRecording,
  ]

  @MainActor
  private func preserveSessionActivitySource(of manager: KeyboardShortcutManager) {
    addTeardownBlock { @MainActor in
      manager.isRecordingSessionActive = { ScreenRecordingManager.shared.isActive }
    }
  }

  @MainActor
  private func preserveMasterEnabledState(of manager: KeyboardShortcutManager) {
    let wasEnabled = manager.isEnabled
    addTeardownBlock { @MainActor in
      wasEnabled ? manager.enable() : manager.disable()
    }
  }

  @MainActor
  func testShouldRegisterNow_gatesExactlyTheRecordingSessionKinds() {
    let manager = KeyboardShortcutManager.shared
    preserveSessionActivitySource(of: manager)

    manager.isRecordingSessionActive = { false }
    let gatedWhileIdle = GlobalShortcutKind.allCases.filter { !manager.shouldRegisterNow(for: $0) }
    XCTAssertEqual(
      Set(gatedWhileIdle),
      Set(Self.sessionKinds),
      "Only the four recording-session kinds may be gated while no recording is active"
    )

    manager.isRecordingSessionActive = { true }
    let gatedWhileActive = GlobalShortcutKind.allCases.filter { !manager.shouldRegisterNow(for: $0) }
    XCTAssertTrue(gatedWhileActive.isEmpty, "No kind may be gated while a recording session is active")
  }

  @MainActor
  func testShouldRegisterNow_sessionKindsFollowActivitySource() {
    let manager = KeyboardShortcutManager.shared
    preserveSessionActivitySource(of: manager)

    manager.isRecordingSessionActive = { false }
    for kind in Self.sessionKinds {
      XCTAssertFalse(manager.shouldRegisterNow(for: kind), "\(kind) must be gated while idle")
    }

    manager.isRecordingSessionActive = { true }
    for kind in Self.sessionKinds {
      XCTAssertTrue(manager.shouldRegisterNow(for: kind), "\(kind) must register while a session is active")
    }
  }

  @MainActor
  func testRecordingStartStopKinds_areNeverSessionGated() {
    let manager = KeyboardShortcutManager.shared
    preserveSessionActivitySource(of: manager)

    manager.isRecordingSessionActive = { false }
    XCTAssertTrue(
      manager.shouldRegisterNow(for: .recording),
      "The start/stop recording shortcut must stay global while idle"
    )
    XCTAssertTrue(
      manager.shouldRegisterNow(for: .fullscreen),
      "Non-recording kinds must stay global while idle"
    )
  }

  @MainActor
  func testFnBoundSessionShortcut_excludedFromFnBindingsWhileIdle() {
    let manager = KeyboardShortcutManager.shared
    preserveSessionActivitySource(of: manager)
    preserveMasterEnabledState(of: manager)

    let originalConfig = manager.shortcut(for: .pauseResumeRecording)
    let originalEnabled = manager.isShortcutEnabled(for: .pauseResumeRecording)
    addTeardownBlock { @MainActor in
      manager.setPauseResumeRecordingShortcut(originalConfig)
      manager.setShortcutEnabled(originalEnabled, for: .pauseResumeRecording)
    }

    let fnCombo = ShortcutConfig(
      keyCode: UInt32(kVK_F17),
      modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
        | ShortcutConfig.functionCarbonModifier
    )

    manager.enable()
    manager.isRecordingSessionActive = { false }
    manager.setPauseResumeRecordingShortcut(fnCombo)
    manager.setShortcutEnabled(true, for: .pauseResumeRecording)

    XCTAssertFalse(
      manager.fnBindings.contains { $0.config == fnCombo },
      "Session Fn-binding must stay out of fnBindings while no recording is active"
    )

    manager.isRecordingSessionActive = { true }
    manager.refreshShortcutRegistration()

    XCTAssertTrue(
      manager.fnBindings.contains { $0.config == fnCombo },
      "Session Fn-binding must be dispatched via fnBindings while a session is active"
    )
  }

  @MainActor
  func testClearedSessionKinds_resolveNil() {
    let manager = KeyboardShortcutManager.shared

    for kind in Self.sessionKinds {
      let initial = manager.shortcut(for: kind)
      addTeardownBlock { @MainActor in
        switch kind {
        case .pauseResumeRecording: manager.setPauseResumeRecordingShortcut(initial)
        case .togglePenRecording: manager.setTogglePenRecordingShortcut(initial)
        case .restartRecording: manager.setRestartRecordingShortcut(initial)
        case .deleteRecording: manager.setDeleteRecordingShortcut(initial)
        default: break
        }
      }

      switch kind {
      case .pauseResumeRecording: manager.setPauseResumeRecordingShortcut(nil)
      case .togglePenRecording: manager.setTogglePenRecordingShortcut(nil)
      case .restartRecording: manager.setRestartRecordingShortcut(nil)
      case .deleteRecording: manager.setDeleteRecordingShortcut(nil)
      default: break
      }

      XCTAssertNil(manager.shortcut(for: kind), "Cleared \(kind) must resolve to nil")
    }
  }
}

// MARK: - Carbon-level registration gating

final class RecordingSessionHotkeyRegistrationTests: XCTestCase {

  /// Exotic combos (Ctrl+Option+Shift+Cmd+F18/F19) — no system/app should hold them.
  private let sessionProbeConfig = ShortcutConfig(
    keyCode: UInt32(kVK_F18),
    modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
  )
  private let nonSessionProbeConfig = ShortcutConfig(
    keyCode: UInt32(kVK_F19),
    modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
  )
  private let zeroModifierProbeConfig = ShortcutConfig(keyCode: UInt32(kVK_F20), modifiers: 0)

  private func probeHotkeyID(for config: ShortcutConfig) -> EventHotKeyID {
    switch config.keyCode {
    case UInt32(kVK_F18): return EventHotKeyID(signature: OSType(0x5A54_5354), id: 991)  // "ZTST"
    case UInt32(kVK_F19): return EventHotKeyID(signature: OSType(0x5A54_5354), id: 992)
    default: return EventHotKeyID(signature: OSType(0x5A54_5354), id: 993)
    }
  }

  /// Attempt to register the probe combo from this process.
  /// Returns `eventHotKeyExistsErr` (-9878) when someone already holds it.
  @discardableResult
  private func probeRegister(_ config: ShortcutConfig) -> (status: OSStatus, ref: EventHotKeyRef?) {
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      config.keyCode,
      config.modifiers,
      probeHotkeyID(for: config),
      GetApplicationEventTarget(),
      0,
      &ref
    )
    return (status, ref)
  }

  private func assertComboFree(_ config: ShortcutConfig, _ message: String) {
    let probe = probeRegister(config)
    XCTAssertEqual(probe.status, noErr, message)
    if let ref = probe.ref { UnregisterEventHotKey(ref) }
  }

  private func assertComboHeld(_ config: ShortcutConfig, _ message: String) {
    let probe = probeRegister(config)
    XCTAssertEqual(probe.status, OSStatus(-9878), message)
    if let ref = probe.ref { UnregisterEventHotKey(ref) }
  }

  @MainActor
  private func preserveManagerState(
    of manager: KeyboardShortcutManager,
    kinds: [GlobalShortcutKind]
  ) {
    let wasEnabled = manager.isEnabled
    let originals = kinds.map { kind in
      (kind, manager.shortcut(for: kind), manager.isShortcutEnabled(for: kind))
    }
    addTeardownBlock { @MainActor in
      manager.isRecordingSessionActive = { ScreenRecordingManager.shared.isActive }
      for (kind, config, enabled) in originals {
        manager.setShortcutConfigForTest(config, kind: kind)
        manager.setShortcutEnabled(enabled, for: kind)
      }
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

  @MainActor
  func testSessionShortcut_registersOnlyWhileRecordingSessionActive() throws {
    try skipIfRunningInCI("Carbon hotkey registration is unsupported on headless CI runners")
    let manager = KeyboardShortcutManager.shared
    preserveManagerState(of: manager, kinds: [.pauseResumeRecording])
    try requireFreeProbe(sessionProbeConfig)

    manager.enable()
    manager.isRecordingSessionActive = { false }
    manager.setPauseResumeRecordingShortcut(sessionProbeConfig)
    manager.setShortcutEnabled(true, for: .pauseResumeRecording)

    assertComboFree(
      sessionProbeConfig,
      "Session shortcut must not hold its combo while no recording is active"
    )

    manager.isRecordingSessionActive = { true }
    manager.refreshShortcutRegistration()
    assertComboHeld(
      sessionProbeConfig,
      "Session shortcut must hold its combo while a recording session is active"
    )

    manager.isRecordingSessionActive = { false }
    manager.refreshShortcutRegistration()
    assertComboFree(
      sessionProbeConfig,
      "Session shortcut must release its combo when the recording session ends"
    )
  }

  @MainActor
  func testNonSessionShortcut_staysRegisteredRegardlessOfSessionState() throws {
    try skipIfRunningInCI("Carbon hotkey registration is unsupported on headless CI runners")
    let manager = KeyboardShortcutManager.shared
    preserveManagerState(of: manager, kinds: [.fullscreen])
    try requireFreeProbe(nonSessionProbeConfig)

    manager.enable()
    manager.isRecordingSessionActive = { false }
    manager.setFullscreenShortcut(nonSessionProbeConfig)
    manager.setShortcutEnabled(true, for: .fullscreen)

    assertComboHeld(
      nonSessionProbeConfig,
      "Non-session shortcut must hold its combo while no recording is active"
    )

    manager.isRecordingSessionActive = { true }
    manager.refreshShortcutRegistration()
    assertComboHeld(
      nonSessionProbeConfig,
      "Non-session shortcut must keep its combo while a recording session is active"
    )
  }

  @MainActor
  func testDisabledSessionShortcut_staysUnregisteredWhileSessionActive() throws {
    try skipIfRunningInCI("Carbon hotkey registration is unsupported on headless CI runners")
    let manager = KeyboardShortcutManager.shared
    preserveManagerState(of: manager, kinds: [.togglePenRecording])
    try requireFreeProbe(sessionProbeConfig)

    manager.enable()
    manager.isRecordingSessionActive = { true }
    manager.setTogglePenRecordingShortcut(sessionProbeConfig)
    manager.setShortcutEnabled(false, for: .togglePenRecording)

    assertComboFree(
      sessionProbeConfig,
      "Disabled session shortcut must not register even while a session is active"
    )
  }

  @MainActor
  func testZeroModifierSessionShortcut_staysUnregisteredWhileSessionActive() throws {
    try skipIfRunningInCI("Carbon hotkey registration is unsupported on headless CI runners")
    let manager = KeyboardShortcutManager.shared
    preserveManagerState(of: manager, kinds: [.restartRecording])
    try requireFreeProbe(zeroModifierProbeConfig)

    manager.enable()
    manager.isRecordingSessionActive = { true }
    manager.setRestartRecordingShortcut(zeroModifierProbeConfig)
    manager.setShortcutEnabled(true, for: .restartRecording)

    assertComboFree(
      zeroModifierProbeConfig,
      "Zero-modifier configs must stay unregistered even while a session is active"
    )
  }

  @MainActor
  func testClearedSessionShortcut_staysUnregisteredWhileSessionActive() throws {
    try skipIfRunningInCI("Carbon hotkey registration is unsupported on headless CI runners")
    let manager = KeyboardShortcutManager.shared
    preserveManagerState(of: manager, kinds: [.deleteRecording])
    try requireFreeProbe(sessionProbeConfig)

    manager.enable()
    manager.isRecordingSessionActive = { true }
    manager.setDeleteRecordingShortcut(sessionProbeConfig)
    manager.setShortcutEnabled(true, for: .deleteRecording)
    assertComboHeld(sessionProbeConfig, "Precondition: active session holds the bound combo")

    manager.setDeleteRecordingShortcut(nil)
    assertComboFree(
      sessionProbeConfig,
      "Clearing the session shortcut must free the combo even while a session is active"
    )
  }
}

@MainActor
private extension KeyboardShortcutManager {
  /// Restore helper so tests can reset any kind through the same public setters.
  func setShortcutConfigForTest(_ config: ShortcutConfig?, kind: GlobalShortcutKind) {
    switch kind {
    case .fullscreen: setFullscreenShortcut(config)
    case .area: setAreaShortcut(config)
    case .repeatArea: setRepeatAreaShortcut(config)
    case .areaAnnotate: setAreaAnnotateShortcut(config)
    case .activeWindow: setActiveWindowShortcut(config)
    case .scrollingCapture: setScrollingCaptureShortcut(config)
    case .recording: setRecordingShortcut(config)
    case .pauseResumeRecording: setPauseResumeRecordingShortcut(config)
    case .togglePenRecording: setTogglePenRecordingShortcut(config)
    case .restartRecording: setRestartRecordingShortcut(config)
    case .deleteRecording: setDeleteRecordingShortcut(config)
    case .annotate: setAnnotateShortcut(config)
    case .videoEditor: setVideoEditorShortcut(config)
    case .cloudUploads: setCloudUploadsShortcut(config)
    case .shortcutList: setShortcutListShortcut(config)
    case .ocr: setOCRShortcut(config)
    case .smartElement: setSmartElementShortcut(config)
    case .objectCutout: setObjectCutoutShortcut(config)
    case .history: setHistoryShortcut(config)
    }
  }
}
