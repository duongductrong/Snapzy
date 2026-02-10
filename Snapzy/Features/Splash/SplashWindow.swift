//
//  SplashWindow.swift
//  Snapzy
//
//  Fullscreen splash overlay with transparent background and blur effect
//

import AppKit
import SwiftUI

// MARK: - SplashWindow

/// Fullscreen transparent NSPanel with blur background for splash overlay
final class SplashWindow: NSPanel {
  let blurView: NSVisualEffectView

  init(screen: NSScreen) {
    self.blurView = NSVisualEffectView()

    super.init(
      contentRect: screen.frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    configureWindow()
    setupViews(screen: screen)
  }

  private func configureWindow() {
    isFloatingPanel = true
    isOpaque = false
    backgroundColor = .clear
    level = .floating
    hasShadow = false
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    animationBehavior = .none
  }

  private func setupViews(screen: NSScreen) {
    let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))

    // Blur background — starts invisible, animated in later
    blurView.frame = container.bounds
    blurView.autoresizingMask = [.width, .height]
    blurView.blendingMode = .behindWindow
    blurView.material = .fullScreenUI
    blurView.state = .active
    blurView.alphaValue = 0
    container.addSubview(blurView)

    self.contentView = container
  }

  /// Attach SwiftUI content on top of blur layer
  func attachContent(_ view: some View) {
    guard let container = contentView else { return }
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = container.bounds
    hostingView.autoresizingMask = [.width, .height]
    hostingView.layer?.backgroundColor = .clear
    container.addSubview(hostingView)
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

// MARK: - SplashWindowController

/// Manages splash window lifecycle — hosts the unified splash + onboarding flow
@MainActor
final class SplashWindowController {
  static let shared = SplashWindowController()

  private var splashWindow: SplashWindow?

  private init() {}

  /// Show splash with integrated onboarding flow.
  /// - Parameter forceOnboarding: When true, always show onboarding steps (used by "Restart Onboarding")
  func show(forceOnboarding: Bool = false) {
    guard let screen = NSScreen.main else { return }

    let window = SplashWindow(screen: screen)
    self.splashWindow = window

    let needsOnboarding = forceOnboarding || !OnboardingFlowView.hasCompletedOnboarding

    let rootView = SplashOnboardingRootView(
      needsOnboarding: needsOnboarding,
      onDismiss: { [weak self] in
        self?.dismiss()
      }
    )
    window.attachContent(rootView)

    // Show window
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    // Animate blur in after brief delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      self?.animateBlurIn()
    }
  }

  private func animateBlurIn() {
    guard let window = splashWindow else { return }
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.6
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      window.blurView.animator().alphaValue = 1.0
    })
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
      self?.splashWindow = nil
    })
  }
}
