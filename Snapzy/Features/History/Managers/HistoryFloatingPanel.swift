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

  private var isTextInputActive: Bool {
    guard let responder = firstResponder else { return false }
    return responder is NSTextView || responder is NSTextField
  }

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
      if isTextInputActive {
        return super.performKeyEquivalent(with: event)
      }

      NotificationCenter.default.post(name: .historyCopySelection, object: self)
      return true
    }

    return super.performKeyEquivalent(with: event)
  }

  override func keyDown(with event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

    if !isTextInputActive, flags.isEmpty, (event.keyCode == 36 || event.keyCode == 76) {
      NotificationCenter.default.post(name: .historyActivateSelection, object: self)
      return
    }

    super.keyDown(with: event)
  }
}
