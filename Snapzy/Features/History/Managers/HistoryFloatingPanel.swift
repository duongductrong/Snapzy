//
//  HistoryFloatingPanel.swift
//  Snapzy
//
//  NSPanel subclass for the floating history panel
//

import AppKit
import Carbon.HIToolbox
import Foundation

/// Non-activating floating panel for capture history
final class HistoryFloatingPanel: NSPanel {
  var onDidResignKey: (() -> Void)?
  private var localArrowEventMonitor: Any?

  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    configurePanel()
  }

  private static let defaultLevel: NSWindow.Level = .floating
  private static let pinnedLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)

  private func configurePanel() {
    level = Self.defaultLevel
    isFloatingPanel = true
    hidesOnDeactivate = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    acceptsMouseMovedEvents = true
    ignoresMouseEvents = false
  }

  func updateWindowLevel(isPinned: Bool) {
    level = isPinned ? Self.pinnedLevel : Self.defaultLevel
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

  override func close() {
    removeLocalArrowEventMonitor()
    super.close()
  }

  override func sendEvent(_ event: NSEvent) {
    guard handleArrowNavigationEvent(event) else {
      super.sendEvent(event)
      return
    }
  }

  func installLocalArrowEventMonitor() {
    guard localArrowEventMonitor == nil else { return }
    localArrowEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self,
            event.windowNumber == self.windowNumber,
            self.isVisible,
            self.isKeyWindow,
            self.shouldHandleArrowNavigationEvent(event) else {
        return event
      }
      return self.handleArrowNavigationEvent(event) ? nil : event
    }
  }

  func removeLocalArrowEventMonitor() {
    guard let localArrowEventMonitor else { return }
    NSEvent.removeMonitor(localArrowEventMonitor)
    self.localArrowEventMonitor = nil
  }

  private func shouldHandleArrowNavigationEvent(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown,
          HistoryFloatingNavigationDirection(keyCode: event.keyCode) != nil else { return false }

    let flags = navigationModifierFlags(for: event)
    return !isTextInputActive && (flags.isEmpty || flags == .shift)
  }

  @discardableResult
  private func handleArrowNavigationEvent(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown,
          HistoryFloatingNavigationDirection(keyCode: event.keyCode) != nil else { return false }

    let flags = navigationModifierFlags(for: event)
    guard !isTextInputActive, flags.isEmpty || flags == .shift else { return false }

    NotificationCenter.default.post(
      name: .historyMoveFocus,
      object: self,
      userInfo: ["keyCode": event.keyCode, "extendsSelection": flags == .shift]
    )
    return true
  }

  private func navigationModifierFlags(for event: NSEvent) -> NSEvent.ModifierFlags {
    let navigationModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    return event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .intersection(navigationModifiers)
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

    if event.keyCode == 0 && flags == .command {
      if isTextInputActive {
        return super.performKeyEquivalent(with: event)
      }

      NotificationCenter.default.post(name: .historySelectAll, object: self)
      return true
    }

    if event.keyCode == 35 && flags == .command {
      if isTextInputActive {
        return super.performKeyEquivalent(with: event)
      }

      HistoryFloatingManager.shared.togglePin()
      return true
    }

    if HistoryFloatingManager.shared.isToggleModeShortcutEnabled,
       let toggleShortcut = HistoryFloatingManager.shared.toggleModeShortcut,
       let eventShortcut = ShortcutConfig(from: event) {
      if eventShortcut.keyCode == toggleShortcut.keyCode && eventShortcut.modifiers == toggleShortcut.modifiers {
        if isTextInputActive {
          return super.performKeyEquivalent(with: event)
        }
        HistoryFloatingManager.shared.togglePresentationMode()
        return true
      }
    }

    return super.performKeyEquivalent(with: event)
  }

  override func keyDown(with event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

    if !isTextInputActive, flags.isEmpty, (event.keyCode == 51 || event.keyCode == 117) {
      NotificationCenter.default.post(name: .historyDeleteSelection, object: self)
      return
    }

    if !isTextInputActive, flags.isEmpty, (event.keyCode == 36 || event.keyCode == 76) {
      NotificationCenter.default.post(name: .historyActivateSelection, object: self)
      return
    }

    super.keyDown(with: event)
  }

}
