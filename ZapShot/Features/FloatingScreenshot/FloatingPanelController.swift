//
//  FloatingPanelController.swift
//  ZapShot
//
//  Controller for managing floating panel lifecycle and positioning
//

import AppKit
import Foundation
import SwiftUI

/// Manages floating panel for screenshot previews
@MainActor
final class FloatingPanelController {

  private var panel: FloatingPanel?
  private var position: FloatingPosition = .bottomRight
  private let padding: CGFloat = 20

  /// Show SwiftUI content in floating panel
  func show<Content: View>(_ content: Content, size: CGSize) {
    let screen = NSScreen.main ?? NSScreen.screens.first!
    let origin = position.calculateOrigin(for: size, on: screen, padding: padding)
    let frame = NSRect(origin: origin, size: size)

    let panel = FloatingPanel(contentRect: frame)
    let hostingView = NSHostingView(rootView: content)
    hostingView.frame = NSRect(origin: .zero, size: size)
    panel.contentView = hostingView
    panel.orderFrontRegardless()

    self.panel = panel
  }

  /// Update panel content with new SwiftUI view
  func updateContent<Content: View>(_ content: Content) {
    guard let panel = panel else { return }
    let hostingView = NSHostingView(rootView: content)
    hostingView.frame = panel.contentView?.bounds ?? .zero
    panel.contentView = hostingView
  }

  /// Update panel position on screen
  func updatePosition(_ newPosition: FloatingPosition) {
    position = newPosition
    repositionPanel()
  }

  /// Resize panel and reposition
  func updateSize(_ size: CGSize) {
    guard let panel = panel else { return }
    let screen = NSScreen.main ?? NSScreen.screens.first!
    let origin = position.calculateOrigin(for: size, on: screen, padding: padding)
    panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
  }

  /// Hide and release panel
  func hide() {
    panel?.close()
    panel = nil
  }

  /// Check if panel is currently visible
  var isVisible: Bool {
    panel != nil
  }

  private func repositionPanel() {
    guard let panel = panel else { return }
    let size = panel.frame.size
    let screen = NSScreen.main ?? NSScreen.screens.first!
    let origin = position.calculateOrigin(for: size, on: screen, padding: padding)
    panel.setFrameOrigin(origin)
  }
}
