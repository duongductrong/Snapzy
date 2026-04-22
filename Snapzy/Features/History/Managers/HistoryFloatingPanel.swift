//
//  HistoryFloatingPanel.swift
//  Snapzy
//
//  NSPanel subclass for the floating history panel
//

import AppKit
import Foundation

/// Non-activating floating panel for capture history
final class HistoryFloatingPanel: NSPanel {
  static var cornerRadius: CGFloat {
    HistoryFloatingLayout.cornerRadius(for: HistoryFloatingLayout.storedScale())
  }

  var onDidResignKey: (() -> Void)?

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
    hasShadow = true
    collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    acceptsMouseMovedEvents = true
    ignoresMouseEvents = false
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func resignKey() {
    super.resignKey()

    DispatchQueue.main.async { [weak self] in
      self?.onDidResignKey?()
    }
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard event.type == .keyDown else {
      return super.performKeyEquivalent(with: event)
    }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

    if event.keyCode == 8 && flags == .command {
      NotificationCenter.default.post(name: .historyCopySelection, object: self)
      return true
    }

    return super.performKeyEquivalent(with: event)
  }
}
