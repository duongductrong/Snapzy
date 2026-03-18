//
//  SplashWindow.swift
//  Snapzy
//
//  Maximized window for splash & onboarding with traffic lights, no toolbar
//

import AppKit
import SwiftUI

// MARK: - SplashWindow

/// Maximized NSWindow with transparent titlebar and traffic lights for splash/onboarding
final class SplashWindow: NSWindow {

  init(screen: NSScreen) {
    // Size to ~85% of visible screen (max 1200×800) for a normal window feel
    let windowSize = NSSize(
      width: min(screen.visibleFrame.width * 0.85, 1200),
      height: min(screen.visibleFrame.height * 0.85, 800)
    )
    let origin = NSPoint(
      x: screen.visibleFrame.midX - windowSize.width / 2,
      y: screen.visibleFrame.midY - windowSize.height / 2
    )
    super.init(
      contentRect: NSRect(origin: origin, size: windowSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    configureWindow()
    setupBlurBackground()
  }

  private func configureWindow() {
    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    backgroundColor = .clear
    isOpaque = false
    level = .normal
    hasShadow = true
    isReleasedWhenClosed = false
    minSize = NSSize(width: 700, height: 500)
    collectionBehavior = [.managed, .participatesInCycle]
    animationBehavior = .none

    // Start invisible for fade-in animation
    alphaValue = 0
  }

  private func setupBlurBackground() {
    let container = NSView()
    container.wantsLayer = true

    // Blur effect behind the window
    let blurView = NSVisualEffectView()
    blurView.blendingMode = .behindWindow
    blurView.material = .hudWindow
    blurView.state = .active
    blurView.autoresizingMask = [.width, .height]
    container.addSubview(blurView)

    self.contentView = container
  }

  /// Attach SwiftUI content on top of blur background
  func attachContent(_ view: some View) {
    guard let container = contentView else { return }
    let hostingView = NSHostingView(rootView: view)
    hostingView.autoresizingMask = [.width, .height]
    hostingView.frame = container.bounds
    hostingView.layer?.backgroundColor = .clear
    container.addSubview(hostingView)
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  override func layoutIfNeeded() {
    super.layoutIfNeeded()
    layoutTrafficLights()
  }
}

// MARK: - SplashWindowController

/// Manages splash window lifecycle — hosts the unified splash + onboarding flow
@MainActor
final class SplashWindowController: NSObject, NSWindowDelegate {
  static let shared = SplashWindowController()

  private var splashWindow: SplashWindow?

  private override init() {}

  /// Show splash with integrated onboarding flow.
  /// - Parameter forceOnboarding: When true, always show onboarding steps (used by "Restart Onboarding")
  func show(forceOnboarding: Bool = false) {
    guard let screen = NSScreen.main else { return }

    // Skip splash entirely when user opted out and no onboarding/sponsor is pending
    if !forceOnboarding,
       OnboardingFlowView.hasCompletedOnboarding,
       UserDefaults.standard.bool(forKey: PreferencesKeys.sponsorPromptSeen),
       UserDefaults.standard.bool(forKey: PreferencesKeys.splashSkipped) {
      return
    }

    // Show app in Cmd+Tab switcher
    NSApp.setActivationPolicy(.regular)

    let window = SplashWindow(screen: screen)
    window.delegate = self
    self.splashWindow = window

    let needsOnboarding = forceOnboarding || !OnboardingFlowView.hasCompletedOnboarding

    let rootView = SplashOnboardingRootView(
      needsOnboarding: needsOnboarding,
      showSponsorPrompt: forceOnboarding
        || !UserDefaults.standard.bool(forKey: PreferencesKeys.sponsorPromptSeen),
      onDismiss: { [weak self] in
        self?.dismiss()
      }
    )
    window.attachContent(rootView)

    // Show window and activate
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    // Fade in
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
      self?.animateIn()
    }
  }

  private func animateIn() {
    guard let window = splashWindow else { return }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.5
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      window.animator().alphaValue = 1.0
    }
  }

  /// Fade out splash window and clean up
  func dismiss() {
    guard let window = splashWindow else { return }

    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.4
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      window.animator().alphaValue = 0
    }, completionHandler: { [weak self] in
      window.orderOut(nil)
      window.close()
      MainActor.assumeIsolated {
        self?.splashWindow = nil

        // Revert to menu-bar-only mode (hide from Cmd+Tab switcher)
        NSApp.setActivationPolicy(.accessory)
      }
    })
  }

  // MARK: - NSWindowDelegate

  nonisolated func windowWillClose(_ notification: Notification) {
    MainActor.assumeIsolated {
      self.splashWindow = nil
      NSApp.setActivationPolicy(.accessory)
    }
  }
}
