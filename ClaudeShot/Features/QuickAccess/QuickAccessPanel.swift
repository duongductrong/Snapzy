//
//  QuickAccessPanel.swift
//  ClaudeShot
//
//  NSPanel subclass for quick access screenshot overlay
//

import AppKit
import Foundation

/// Non-activating floating panel for screenshot previews
final class QuickAccessPanel: NSPanel {

  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    configurePanel()
  }

  private func configurePanel() {
    level = .floating
    isFloatingPanel = true
    hidesOnDeactivate = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false  // Cards have their own shadows
    collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    acceptsMouseMovedEvents = true
    ignoresMouseEvents = false
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
