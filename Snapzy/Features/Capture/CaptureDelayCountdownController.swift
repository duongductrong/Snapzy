//
//  CaptureDelayCountdownController.swift
//  Snapzy
//
//  Shows a small non-activating countdown HUD before a delayed screenshot.
//  The HUD never takes focus, so menus and hover states opened in other apps
//  stay open until the capture fires. Esc or clicking the HUD cancels.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class CaptureDelayCountdownController {
  static let shared = CaptureDelayCountdownController()

  /// Time for the HUD to leave the screen before the capture starts.
  private let hudDismissSettleDelay: TimeInterval = 0.15

  private let model = CaptureDelayCountdownModel()
  private var panel: NSPanel?
  private var timer: Timer?
  private var countdown = CaptureDelayCountdown(seconds: 0)
  private var onFinish: (@MainActor () -> Void)?
  private var globalKeyMonitor: Any?
  private var localKeyMonitor: Any?

  private init() {}

  var isActive: Bool { onFinish != nil }

  /// Count down `seconds`, then run `onFinish`. Ignored while another
  /// countdown is running.
  func start(seconds: Int, captureName: String, onFinish: @escaping @MainActor () -> Void) {
    guard !isActive else {
      DiagnosticLogger.shared.log(.debug, .capture, "Capture delay ignored: countdown already running", context: [
        "capture": captureName,
      ])
      return
    }
    guard seconds > 0 else {
      onFinish()
      return
    }

    DiagnosticLogger.shared.log(.info, .capture, "Capture delay started", context: [
      "capture": captureName,
      "seconds": "\(seconds)",
    ])
    self.onFinish = onFinish
    countdown = CaptureDelayCountdown(seconds: seconds)
    model.remainingSeconds = seconds
    showPanel()
    installKeyMonitors()

    let timer = Timer(timeInterval: 1, repeats: true) { _ in
      Task { @MainActor in CaptureDelayCountdownController.shared.tick() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  func cancel() {
    guard isActive else { return }
    DiagnosticLogger.shared.log(.info, .capture, "Capture delay cancelled")
    onFinish = nil
    tearDown()
  }

  private func tick() {
    let didFinish = countdown.tick()
    model.remainingSeconds = countdown.remainingSeconds
    guard didFinish, let onFinish else { return }

    self.onFinish = nil
    tearDown()
    // Let the HUD disappear so it never ends up in the screenshot.
    DispatchQueue.main.asyncAfter(deadline: .now() + hudDismissSettleDelay) {
      onFinish()
    }
  }

  private func tearDown() {
    timer?.invalidate()
    timer = nil
    removeKeyMonitors()
    panel?.orderOut(nil)
  }

  // MARK: - Panel

  private func showPanel() {
    let panel = self.panel ?? makePanel()
    self.panel = panel

    let mouseLocation = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
    if let visibleFrame = screen?.visibleFrame {
      let size = panel.frame.size
      panel.setFrameOrigin(NSPoint(
        x: visibleFrame.midX - size.width / 2,
        y: visibleFrame.midY - size.height / 2
      ))
    }
    panel.orderFrontRegardless()
  }

  private func makePanel() -> NSPanel {
    let size = NSSize(width: 150, height: 150)
    let panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: true
    )
    panel.isFloatingPanel = true
    // Above menus, so the countdown stays visible over an open menu.
    panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.sharingType = .none
    panel.contentView = FirstMouseHostingView(rootView: CaptureDelayCountdownView(model: model) { [weak self] in
      self?.cancel()
    })
    return panel
  }

  // MARK: - Esc to cancel

  private func installKeyMonitors() {
    // Global monitor covers the usual case (another app is frontmost); it only
    // delivers events when Snapzy has Accessibility permission. The local
    // monitor covers Snapzy itself being active.
    globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == 53 else { return }
      Task { @MainActor in self?.cancel() }
    }
    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == 53, self?.isActive == true else { return event }
      self?.cancel()
      return nil
    }
  }

  private func removeKeyMonitors() {
    if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
    if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
    globalKeyMonitor = nil
    localKeyMonitor = nil
  }
}

// MARK: - HUD view

/// The panel never becomes key, so the first click must reach SwiftUI directly.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
private final class CaptureDelayCountdownModel: ObservableObject {
  @Published var remainingSeconds = 0
}

private struct CaptureDelayCountdownView: View {
  @ObservedObject var model: CaptureDelayCountdownModel
  let onCancel: () -> Void

  var body: some View {
    VStack(spacing: 6) {
      Text(verbatim: "\(model.remainingSeconds)")
        .font(.system(size: 64, weight: .semibold, design: .rounded))
        .monospacedDigit()
      Text(L10n.ScreenCapture.captureDelayCancelHint)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
    }
    .frame(width: 150, height: 150)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.1))
    )
    .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    .onTapGesture(perform: onCancel)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
  }
}
