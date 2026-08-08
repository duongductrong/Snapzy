//
//  QuickAccessPanelController.swift
//  Snapzy
//
//  Controller for managing quick access panel lifecycle and positioning
//  with CleanShot X-style slide animations
//

import AppKit
import Foundation
import SwiftUI

/// Manages quick access panel for screenshot previews with animated transitions
@MainActor
final class QuickAccessPanelController {

  private enum PanelTransition {
    case entering
    case exiting
  }

  private var panel: QuickAccessPanel?
  var window: NSWindow? { panel }
  private var position: QuickAccessPosition = .bottomRight
  private let padding: CGFloat = 20
  /// Non-nil while an enter/exit animation is running. Cleared by the guarded
  /// transition finish — never trusted to clear on its own (see `runTransition`).
  private var activeTransition: PanelTransition?
  /// Monotonic token invalidating stale transition finishes (animation completion
  /// handler or watchdog) once a newer transition or close supersedes them.
  private var transitionToken: UInt64 = 0
  private var visibleItemCount = 0
  private var overlayScale: CGFloat = 1
  /// Display the visible panel is pinned to; see `QuickAccessScreenAnchor`.
  private var screenAnchor = QuickAccessScreenAnchor()
  /// Screen the panel is currently positioned against.
  var anchoredScreen: NSScreen { screenAnchor.screen }
  private var isAnimating: Bool { activeTransition != nil }
  /// True while the panel is sliding/fading out. Callers must not reposition a
  /// dying panel — they need a fresh `show()` instead.
  var isDismissing: Bool { activeTransition == .exiting }
  private var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  /// Show SwiftUI content in floating panel with slide-in animation
  func show<Content: View>(_ content: Content, size: CGSize, itemCount: Int, scale: CGFloat) {
    // Never drop a show request. A stale panel or an in-flight/wedged transition
    // must not swallow it — force-close and start clean instead.
    if panel != nil || activeTransition != nil {
      forceClosePanel(reason: "show superseded existing panel or transition")
    }

    visibleItemCount = itemCount
    overlayScale = scale

    let screen = ScreenUtility.activeScreen()
    screenAnchor.anchor(to: screen)
    let targetOrigin = position.calculateOrigin(for: size, on: screen, padding: padding)
    let targetFrame = NSRect(origin: targetOrigin, size: size)

    let panel = QuickAccessPanel(contentRect: targetFrame)
    let hostingView = NSHostingView(rootView: content)
    hostingView.frame = NSRect(origin: .zero, size: size)
    panel.contentView = hostingView
    panel.updatePassthroughRegion(itemCount: visibleItemCount, scale: overlayScale)

    self.panel = panel

    if reduceMotion {
      // Simple fade-in for reduced motion
      panel.alphaValue = 0
      panel.orderFrontRegardless()
      NSAnimationContext.runAnimationGroup { context in
        context.duration = QuickAccessAnimations.panelExitDuration
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        panel.animator().alphaValue = 1
      }
    } else {
      slideIn(panel, onto: screen, size: size)
    }

    QuickAccessSound.appear.play(reduceMotion: reduceMotion)
  }

  /// Re-anchor a visible panel to the display the user is capturing on.
  ///
  /// The panel is only positioned when it first appears, so a capture taken on
  /// another display used to leave Quick Access stranded on the previous one
  /// (#467). No-op when the cursor is still on the anchored display.
  func moveToActiveScreenIfNeeded() {
    guard let panel, !isDismissing, screenAnchor.anchorToActiveScreen() else { return }

    let screen = screenAnchor.screen
    let size = panel.frame.size

    // Any in-flight enter belongs to the old display — supersede it so its
    // completion/watchdog can't drag the panel back.
    transitionToken &+= 1
    activeTransition = nil

    guard !reduceMotion else {
      let origin = position.calculateOrigin(for: size, on: screen, padding: padding)
      panel.setFrame(NSRect(origin: origin, size: size), display: true)
      panel.updatePassthroughRegion(itemCount: visibleItemCount, scale: overlayScale)
      return
    }

    // Replay the entrance on the new display instead of flying the panel across
    // the desktop — it reads as arriving with the capture.
    slideIn(panel, onto: screen, size: size)
  }

  /// Park the panel off the edge of `screen` and slide it into its corner.
  private func slideIn(_ panel: QuickAccessPanel, onto screen: NSScreen, size: CGSize) {
    let targetOrigin = position.calculateOrigin(for: size, on: screen, padding: padding)
    let offscreenOrigin = position.offscreenOrigin(for: size, on: screen, padding: padding)

    panel.setFrame(NSRect(origin: offscreenOrigin, size: size), display: false)
    panel.alphaValue = 1
    panel.orderFrontRegardless()

    runTransition(
      .entering,
      duration: QuickAccessAnimations.panelEnterDuration,
      animations: { context in
        context.timingFunction = CAMediaTimingFunction(
          controlPoints: 0.22, 1.0, 0.36, 1.0  // Custom spring-like curve
        )
        panel.animator().setFrame(NSRect(origin: targetOrigin, size: size), display: true)
      },
      completion: { [weak self] in
        panel.updatePassthroughRegion(
          itemCount: self?.visibleItemCount ?? 0,
          scale: self?.overlayScale ?? 1
        )
      }
    )
  }

  /// Update panel content with new SwiftUI view
  func updateContent<Content: View>(_ content: Content) {
    guard let panel = panel else { return }
    let hostingView = NSHostingView(rootView: content)
    hostingView.frame = panel.contentView?.bounds ?? .zero
    panel.contentView = hostingView
    panel.updatePassthroughRegion(itemCount: visibleItemCount, scale: overlayScale)
  }

  func updateInteractionMetrics(itemCount: Int, scale: CGFloat) {
    visibleItemCount = itemCount
    overlayScale = scale
    panel?.updatePassthroughRegion(itemCount: itemCount, scale: scale)
  }

  /// Update panel position on screen
  func updatePosition(_ newPosition: QuickAccessPosition) {
    position = newPosition
    repositionPanel()
  }

  /// Resize panel and reposition instantly to avoid fighting SwiftUI card animations
  func updateSize(_ size: CGSize) {
    guard let panel = panel, !isAnimating else { return }
    let origin = position.calculateOrigin(for: size, on: screenAnchor.screen, padding: padding)
    let targetFrame = NSRect(origin: origin, size: size)
    panel.setFrame(targetFrame, display: true, animate: false)
    panel.updatePassthroughRegion(itemCount: visibleItemCount, scale: overlayScale)
  }

  /// Hide panel with slide-out animation
  func hide() {
    guard let panel = panel else {
      // Defensive: never let a wedged transition block future show/hide calls.
      activeTransition = nil
      return
    }

    switch activeTransition {
    case .exiting:
      // Already sliding out — let it finish.
      return
    case .entering:
      // Enter interrupted: close instantly instead of dropping the hide,
      // so the panel can never get stuck on screen with an empty stack.
      forceClosePanel(reason: "hide interrupted enter transition")
      return
    case nil:
      break
    }

    if reduceMotion {
      // Simple fade-out for reduced motion. Tracked as a transition so the panel
      // still counts as dismissing while it fades (no reposition, no wedge).
      runTransition(
        .exiting,
        duration: QuickAccessAnimations.panelExitDuration,
        animations: { context in
          context.timingFunction = CAMediaTimingFunction(name: .easeIn)
          panel.animator().alphaValue = 0
        },
        completion: { [weak self] in
          panel.close()
          if self?.panel === panel { self?.panel = nil }
        }
      )
    } else {
      // Slide-out to off-screen, on the display the panel actually lives on
      let size = panel.frame.size
      let offscreenOrigin = position.offscreenOrigin(
        for: size,
        on: screenAnchor.screen,
        padding: padding
      )
      let offscreenFrame = NSRect(origin: offscreenOrigin, size: size)

      runTransition(
        .exiting,
        duration: QuickAccessAnimations.panelExitDuration,
        animations: { context in
          context.timingFunction = CAMediaTimingFunction(name: .easeIn)
          panel.animator().setFrame(offscreenFrame, display: true)
          panel.animator().alphaValue = 0.5
        },
        completion: { [weak self] in
          panel.close()
          if self?.panel === panel { self?.panel = nil }
        }
      )
    }
  }

  func suspendMouseMonitors() {
    panel?.suspendMouseMonitors()
  }

  func resumeMouseMonitors() {
    panel?.resumeMouseMonitors()
  }

  /// Self-heal the panel's hover monitors after editor windows close (a stalled
  /// runloop can get the global event tap silently disabled by the system).
  func reinstallMouseMonitors() {
    panel?.reinstallMouseMonitors()
  }

  /// Check if panel is currently visible
  var isVisible: Bool {
    panel != nil
  }

  private func repositionPanel() {
    guard let panel = panel, !isAnimating else { return }
    let size = panel.frame.size
    let origin = position.calculateOrigin(for: size, on: screenAnchor.screen, padding: padding)

    if reduceMotion {
      panel.setFrameOrigin(origin)
      panel.updatePassthroughRegion(itemCount: visibleItemCount, scale: overlayScale)
    } else {
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.3
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        panel.animator().setFrameOrigin(origin)
      }, completionHandler: { [weak self] in
        MainActor.assumeIsolated {
          guard let self else { return }
          panel.updatePassthroughRegion(itemCount: self.visibleItemCount, scale: self.overlayScale)
        }
      })
    }
  }

  /// Runs a panel transition and guarantees the transition state always clears.
  /// AppKit can drop `NSAnimationContext` completion handlers (window ordered out
  /// mid-animation, runloop stall), which previously wedged `isAnimating` forever
  /// and silently swallowed every later show/hide. A watchdog fires shortly after
  /// the expected duration and force-completes the transition; the token guard
  /// makes whichever finish arrives second a no-op.
  private func runTransition(
    _ kind: PanelTransition,
    duration: TimeInterval,
    animations: @escaping (NSAnimationContext) -> Void,
    completion: @escaping () -> Void
  ) {
    activeTransition = kind
    transitionToken &+= 1
    let token = transitionToken

    let finish = { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.transitionToken == token else { return }
        self.transitionToken &+= 1
        self.activeTransition = nil
        completion()
      }
    }

    NSAnimationContext.runAnimationGroup(animations, completionHandler: finish)

    Task { @MainActor [weak self] in
      let watchdogSlack: TimeInterval = 0.5
      try? await Task.sleep(nanoseconds: UInt64((duration + watchdogSlack) * 1_000_000_000))
      guard !Task.isCancelled else { return }
      finish()
    }
  }

  /// Immediately closes the current panel and clears any in-flight transition.
  /// Used when a new show/hide supersedes an unfinished (or wedged) transition.
  private func forceClosePanel(reason: String) {
    transitionToken &+= 1  // invalidate pending animation completion + watchdog
    activeTransition = nil
    if let panel {
      panel.close()
      self.panel = nil
    }
    DiagnosticLogger.shared.log(
      .warning,
      .ui,
      "Quick access panel force-closed",
      context: ["reason": reason]
    )
  }
}
