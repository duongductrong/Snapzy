//
//  SnapzyOnboardingWindowController.swift
//  Snapzy
//
//  Window controller hosting the borderless Dark Liquid Glass onboarding window.
//

import AppKit
import SwiftUI

@MainActor
final class SnapzyOnboardingWindowController: NSObject, NSWindowDelegate {
  static let shared = SnapzyOnboardingWindowController()

  private var window: NSWindow?
  var onClose: (() -> Void)?

  private var isPresenting = false
  private var isEnforcing = false

  var isVisible: Bool { window?.isVisible ?? false }

  func show() {
    NSApp.setActivationPolicy(.regular)
    activate()

    let window = window ?? makeWindow()
    self.window = window

    let isFirstPresentation = !window.isVisible
    if isFirstPresentation {
      window.setFrame(Self.preferredFrame(), display: false)
      window.alphaValue = SnapzyMotionPreferences.shared.reduceMotion ? 1 : 0
    }

    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()

    fitWithinScreen(window)

    if isFirstPresentation {
      presentAnimated(window)
    }

    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(120))
      guard let window = self.window else { return }
      window.makeKeyAndOrderFront(nil)
      self.activate()
    }
  }

  func close() {
    guard let window else { return }
    dismissAnimated(window)
  }

  // MARK: - Geometry & Clamping

  private static func visibleFrame(of screen: NSScreen?) -> NSRect {
    (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
      ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
  }

  private static func sizeLimits(on screen: NSScreen?) -> (min: NSSize, max: NSSize) {
    let visible = visibleFrame(of: screen)
    let inset = SnapzyOnboardingMetrics.screenMargin * 2
    let ceiling = NSSize(
      width: min(SnapzyOnboardingMetrics.maxSize.width, max(visible.width - inset, 1)),
      height: min(SnapzyOnboardingMetrics.maxSize.height, max(visible.height - inset, 1))
    )
    let floor = NSSize(
      width: min(SnapzyOnboardingMetrics.minSize.width, ceiling.width),
      height: min(SnapzyOnboardingMetrics.minSize.height, ceiling.height)
    )
    return (floor, ceiling)
  }

  private static func preferredFrame(on screen: NSScreen? = nil) -> NSRect {
    let visible = visibleFrame(of: screen)
    let limits = sizeLimits(on: screen)

    let size = NSSize(
      width: min(max(visible.width * SnapzyOnboardingMetrics.screenFill, limits.min.width), limits.max.width),
      height: min(max(visible.height * SnapzyOnboardingMetrics.screenFill, limits.min.height), limits.max.height)
    )

    return NSRect(
      x: (visible.midX - size.width / 2).rounded(),
      y: (visible.midY - size.height / 2).rounded(),
      width: size.width.rounded(),
      height: size.height.rounded()
    )
  }

  private func clamped(_ size: NSSize, on screen: NSScreen?) -> NSSize {
    let limits = Self.sizeLimits(on: screen)
    return NSSize(
      width: min(max(size.width, limits.min.width), limits.max.width),
      height: min(max(size.height, limits.min.height), limits.max.height)
    )
  }

  private func fitWithinScreen(_ window: NSWindow) {
    let size = clamped(window.frame.size, on: window.screen)
    guard size != window.frame.size else { return }
    let visible = Self.visibleFrame(of: window.screen)
    window.setFrame(
      NSRect(
        x: (visible.midX - size.width / 2).rounded(),
        y: (visible.midY - size.height / 2).rounded(),
        width: size.width,
        height: size.height
      ),
      display: true
    )
  }

  private func enforceSizeLimits(on window: NSWindow) {
    let size = clamped(window.frame.size, on: window.screen)
    guard size != window.frame.size else { return }

    var frame = window.frame
    frame.origin.y += frame.height - size.height
    frame.size = size
    window.setFrame(Self.nudgedOnScreen(frame, on: window.screen), display: true)
  }

  private static func nudgedOnScreen(_ frame: NSRect, on screen: NSScreen?) -> NSRect {
    let visible = visibleFrame(of: screen)
    var frame = frame
    frame.origin.x = min(max(frame.minX, visible.minX), max(visible.maxX - frame.width, visible.minX))
    frame.origin.y = min(max(frame.minY, visible.minY), max(visible.maxY - frame.height, visible.minY))
    return frame
  }

  // MARK: - Presentation & Animation

  private func presentAnimated(_ window: NSWindow) {
    guard !SnapzyMotionPreferences.shared.reduceMotion else {
      window.alphaValue = 1
      return
    }

    let target = window.frame
    let start = clamped(
      NSSize(width: target.width * 0.98, height: target.height * 0.98),
      on: window.screen
    )
    isPresenting = true
    window.setFrame(
      NSRect(
        x: (target.midX - start.width / 2).rounded(),
        y: (target.midY - start.height / 2).rounded(),
        width: start.width,
        height: start.height
      ),
      display: false
    )

    NSAnimationContext.runAnimationGroup { context in
      context.duration = SnapzyMotionSpec.settle.duration
      context.timingFunction = SnapzyMotionSpec.glide.timingFunction
      window.animator().alphaValue = 1
      window.animator().setFrame(target, display: true)
    } completionHandler: { [weak self] in
      window.alphaValue = 1
      window.setFrame(target, display: false)
      MainActor.assumeIsolated { self?.isPresenting = false }
    }
  }

  private func dismissAnimated(_ window: NSWindow) {
    guard !SnapzyMotionPreferences.shared.reduceMotion else {
      window.close()
      return
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = SnapzyMotionSpec.contentOut.duration + 0.06
      context.timingFunction = SnapzyMotionSpec.contentOut.timingFunction
      window.animator().alphaValue = 0
    } completionHandler: { [weak self] in
      window.close()
      window.alphaValue = 1
      MainActor.assumeIsolated {
        self?.window = nil
        NSApp.revertActivationPolicyToAccessoryIfNeeded(excluding: window)
      }
    }
  }

  // MARK: - Window Construction

  private func activate() {
    NSApp.activate(ignoringOtherApps: true)
  }

  private func makeWindow() -> NSWindow {
    let created = SnapzyOnboardingPanel(
      contentRect: Self.preferredFrame(),
      styleMask: [.borderless, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    created.title = L10n.Splash.welcomeTitle
    created.delegate = self
    created.isReleasedWhenClosed = false
    created.level = .normal
    created.collectionBehavior = [.fullScreenAuxiliary]
    fitWithinScreen(created)

    created.isOpaque = false
    created.backgroundColor = .clear
    created.hasShadow = true
    created.isMovableByWindowBackground = true
    created.appearance = NSAppearance(named: .darkAqua)

    let hosting = NSHostingView(
      rootView: SnapzyOnboardingView(onDismiss: { [weak self] in
        self?.close()
      })
      .environmentObject(OnboardingLocalizationController())
    )
    hosting.sizingOptions = [.minSize, .maxSize]

    hosting.wantsLayer = true
    hosting.layer?.cornerRadius = SnapzyOnboardingMetrics.windowRadius
    hosting.layer?.cornerCurve = .continuous
    hosting.layer?.masksToBounds = true
    hosting.layer?.drawsAsynchronously = true

    created.contentView = hosting
    return created
  }

  // MARK: - NSWindowDelegate

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    clamped(frameSize, on: sender.screen)
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    enforceSizeLimits(on: window)
  }

  func windowDidResize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow,
          !isPresenting, !isEnforcing, !window.inLiveResize else { return }
    isEnforcing = true
    Task { @MainActor [weak self] in
      self?.enforceSizeLimits(on: window)
      self?.isEnforcing = false
    }
  }

  func windowDidChangeScreen(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    fitWithinScreen(window)
  }

  func windowWillClose(_ notification: Notification) {
    MainActor.assumeIsolated {
      self.window = nil
      let closingWindow = notification.object as? NSWindow
      NSApp.revertActivationPolicyToAccessoryIfNeeded(excluding: closingWindow)
      self.onClose?()
    }
  }
}

private final class SnapzyOnboardingPanel: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
