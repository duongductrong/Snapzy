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

  private var panel: QuickAccessPanel?
  private var position: QuickAccessPosition = .bottomRight
  private let padding: CGFloat = 20
  private var isAnimating = false
  private var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  /// Show SwiftUI content in floating panel with slide-in animation
  func show<Content: View>(_ content: Content, size: CGSize) {
    guard !isAnimating else { return }

    let screen = NSScreen.main ?? NSScreen.screens.first!
    let targetOrigin = position.calculateOrigin(for: size, on: screen, padding: padding)
    let targetFrame = NSRect(origin: targetOrigin, size: size)

    let panel = QuickAccessPanel(contentRect: targetFrame)
    let hostingView = NSHostingView(rootView: content)
    hostingView.frame = NSRect(origin: .zero, size: size)
    panel.contentView = hostingView

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
      // Slide-in from off-screen
      let offscreenOrigin = position.offscreenOrigin(for: size, on: screen, padding: padding)
      let offscreenFrame = NSRect(origin: offscreenOrigin, size: size)

      panel.setFrame(offscreenFrame, display: false)
      panel.alphaValue = 1
      panel.orderFrontRegardless()

      isAnimating = true
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = QuickAccessAnimations.panelEnterDuration
        context.timingFunction = CAMediaTimingFunction(
          controlPoints: 0.22, 1.0, 0.36, 1.0  // Custom spring-like curve
        )
        panel.animator().setFrame(targetFrame, display: true)
      }, completionHandler: { [weak self] in
        self?.isAnimating = false
      })
    }

    QuickAccessSound.appear.play(reduceMotion: reduceMotion)
  }

  /// Update panel content with new SwiftUI view
  func updateContent<Content: View>(_ content: Content) {
    guard let panel = panel else { return }
    let hostingView = NSHostingView(rootView: content)
    hostingView.frame = panel.contentView?.bounds ?? .zero
    panel.contentView = hostingView
  }

  /// Update panel position on screen
  func updatePosition(_ newPosition: QuickAccessPosition) {
    position = newPosition
    repositionPanel()
  }

  /// Resize panel and reposition instantly to avoid fighting SwiftUI card animations
  func updateSize(_ size: CGSize) {
    guard let panel = panel, !isAnimating else { return }
    let screen = NSScreen.main ?? NSScreen.screens.first!
    let origin = position.calculateOrigin(for: size, on: screen, padding: padding)
    let targetFrame = NSRect(origin: origin, size: size)
    panel.setFrame(targetFrame, display: true, animate: false)
  }

  /// Hide panel with slide-out animation
  func hide() {
    guard let panel = panel, !isAnimating else { return }

    if reduceMotion {
      // Simple fade-out for reduced motion
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = QuickAccessAnimations.panelExitDuration
        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
        panel.animator().alphaValue = 0
      }, completionHandler: { [weak self] in
        panel.close()
        self?.panel = nil
      })
    } else {
      // Slide-out to off-screen
      let screen = NSScreen.main ?? NSScreen.screens.first!
      let size = panel.frame.size
      let offscreenOrigin = position.offscreenOrigin(for: size, on: screen, padding: padding)
      let offscreenFrame = NSRect(origin: offscreenOrigin, size: size)

      isAnimating = true
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = QuickAccessAnimations.panelExitDuration
        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
        panel.animator().setFrame(offscreenFrame, display: true)
        panel.animator().alphaValue = 0.5
      }, completionHandler: { [weak self] in
        panel.close()
        self?.panel = nil
        self?.isAnimating = false
      })
    }
  }

  /// Check if panel is currently visible
  var isVisible: Bool {
    panel != nil
  }

  private func repositionPanel() {
    guard let panel = panel, !isAnimating else { return }
    let size = panel.frame.size
    let screen = NSScreen.main ?? NSScreen.screens.first!
    let origin = position.calculateOrigin(for: size, on: screen, padding: padding)

    if reduceMotion {
      panel.setFrameOrigin(origin)
    } else {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.3
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        panel.animator().setFrameOrigin(origin)
      }
    }
  }
}
