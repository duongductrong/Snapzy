//
//  HistoryTraditionalEdgeRevealController.swift
//  Snapzy
//
//  Optional top-edge hover reveal for the traditional floating history panel
//

import AppKit
import Combine

/// Watches the topmost screen edge and slides the traditional panel in on dwell,
/// mirroring the Hanging reveal. Only presentations started here are auto-hidden;
/// panels opened by shortcut, menu, or expanded browsing are never touched.
@MainActor
final class HistoryTraditionalEdgeRevealController {
  weak var manager: HistoryFloatingManager?

  private var timer: Timer?
  private var hoverState = HistoryEdgeHoverState()
  private var lastEdgeScreen: NSScreen?
  private var revealScreen: NSScreen?
  private var isEdgeRevealed = false
  private var isMenuTracking = false
  private var isStarted = false
  private var observations: Set<AnyCancellable> = []

  deinit {}

  var isMonitoring: Bool {
    timer != nil
  }

  func start() {
    guard !isStarted else { return }
    isStarted = true
    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.updateConfiguration() }
      .store(in: &observations)
    NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
      .sink { [weak self] _ in self?.isMenuTracking = true }
      .store(in: &observations)
    NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
      .sink { [weak self] _ in self?.isMenuTracking = false }
      .store(in: &observations)
    NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
      .sink { [weak self] _ in self?.edgeRevealedPanelDidLoseScreen() }
      .store(in: &observations)
    NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
      .sink { [weak self] _ in self?.edgeRevealedPanelDidLoseScreen() }
      .store(in: &observations)
    updateConfiguration()
  }

  func updateConfiguration() {
    guard isStarted, let manager,
          manager.displayStyle == .traditional,
          manager.isEnabled,
          manager.isEdgeRevealEnabled,
          UserDefaults.standard.snapzyHistoryEnabled
    else {
      timer?.invalidate()
      timer = nil
      isEdgeRevealed = false
      hoverState = HistoryEdgeHoverState()
      lastEdgeScreen = nil
      revealScreen = nil
      return
    }
    guard timer == nil else { return }
    let timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.checkPointer() }
    }
    timer.tolerance = 0.015
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  func panelDidHide() {
    isEdgeRevealed = false
    revealScreen = nil
    hoverState.dismiss()
  }

  private func edgeRevealedPanelDidLoseScreen() {
    guard isEdgeRevealed else { return }
    manager?.hide()
  }

  private var captureInteractionIsActive: Bool {
    ScreenCaptureManager.shared.isCapturing
      || !CaptureChromeWindowRegistry.shared.windowIDs(
        roles: [.captureOverlay], visibleOnly: true
      ).isEmpty
  }

  private func checkPointer() {
    guard let manager else { return }
    let point = NSEvent.mouseLocation
    let screens = NSScreen.screens
    let edgeScreen = HistoryHangingLayout.edgeScreenIndex(at: point, frames: screens.map(\.frame)).map { screens[$0] }
    let presenting = manager.isTraditionalPanelVisible

    if captureInteractionIsActive {
      if isEdgeRevealed {
        manager.hide()
      }
      hoverState.suspend(atEdge: edgeScreen != nil)
      lastEdgeScreen = edgeScreen
      return
    }

    if presenting, manager.presentationMode != .compact || manager.isPinned {
      isEdgeRevealed = false
    }
    if presenting, isEdgeRevealed, let edgeScreen, let lastEdgeScreen,
       edgeScreen.frame != lastEdgeScreen.frame {
      manager.hide()
      hoverState = HistoryEdgeHoverState()
    }
    if !presenting, lastEdgeScreen?.frame != edgeScreen?.frame {
      hoverState = HistoryEdgeHoverState()
    }
    lastEdgeScreen = edgeScreen

    let inside: Bool = if presenting, let panelFrame = manager.traditionalPanelFrame,
                          let screen = revealScreen ?? NSScreen.main {
      HistoryHangingLayout.containsPointer(point, panelFrame: panelFrame, screenFrame: screen.frame)
    } else {
      false
    }

    let suppressed = NSApp.modalWindow != nil
      || manager.isModalInteractionActive
      || (!presenting && (isMenuTracking || NSEvent.pressedMouseButtons != 0))
    let action = hoverState.update(
      atEdge: edgeScreen != nil,
      insideShelf: inside,
      visible: presenting,
      keepOpen: manager.isPinned || isMenuTracking || NSEvent.pressedMouseButtons != 0,
      suppressed: suppressed,
      now: ProcessInfo.processInfo.systemUptime
    )
    switch action {
    case .none:
      break
    case .reveal:
      guard !presenting, !suppressed else { break }
      isEdgeRevealed = true
      revealScreen = edgeScreen
      manager.showCompact(becomesKey: false)
    case .dismiss:
      guard isEdgeRevealed, !manager.isPinned else { break }
      manager.hide()
    }
  }
}
