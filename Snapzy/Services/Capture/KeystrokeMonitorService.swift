//
//  KeystrokeMonitorService.swift
//  Snapzy
//
//  Detects global keyboard events and builds human-readable keystroke
//  display strings (e.g. "⌘ ⇧ S") for the keystroke overlay.
//

import AppKit
import Foundation

@MainActor
final class KeystrokeMonitorService {

  static let tapLocation: CGEventTapLocation = .cgSessionEventTap
  static let tapPlacement: CGEventTapPlacement = .headInsertEventTap
  static let tapOptions: CGEventTapOptions = .defaultTap

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var globalFlagsChangedMonitor: Any?
  private var localFlagsChangedMonitor: Any?
  private var observedModifierFlags: NSEvent.ModifierFlags = []
  private var isRunning = false

  /// Called with the formatted keystroke string (e.g. "⌘ ⇧ S")
  var onKeystroke: ((String) -> Void)?

  func start() {
    guard !isRunning else { return }
    let mask = CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)
    guard let eventTap = CGEvent.tapCreate(
      tap: Self.tapLocation,
      place: Self.tapPlacement,
      options: Self.tapOptions,
      eventsOfInterest: mask,
      callback: Self.tapCallback,
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    ) else {
      DiagnosticLogger.shared.log(.error, .recording, "Failed to create keystroke event tap")
      return
    }
    guard let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0) else {
      CFMachPortInvalidate(eventTap)
      DiagnosticLogger.shared.log(.error, .recording, "Failed to create keystroke event tap source")
      return
    }

    self.eventTap = eventTap
    self.runLoopSource = runLoopSource
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)

    globalFlagsChangedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) {
      [weak self] event in
      MainActor.assumeIsolated {
        self?.handleModifierFlagsChanged(event.modifierFlags)
      }
    }
    localFlagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
      [weak self] event in
      MainActor.assumeIsolated {
        self?.handleModifierFlagsChanged(event.modifierFlags)
      }
      return event
    }
    isRunning = true
  }

  func stop() {
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
      CFRunLoopSourceInvalidate(runLoopSource)
    }
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
    }
    if let globalFlagsChangedMonitor {
      NSEvent.removeMonitor(globalFlagsChangedMonitor)
    }
    if let localFlagsChangedMonitor {
      NSEvent.removeMonitor(localFlagsChangedMonitor)
    }
    runLoopSource = nil
    eventTap = nil
    globalFlagsChangedMonitor = nil
    localFlagsChangedMonitor = nil
    observedModifierFlags = []
    isRunning = false
    onKeystroke = nil
  }

  private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<KeystrokeMonitorService>
      .fromOpaque(userInfo)
      .takeUnretainedValue()
    return MainActor.assumeIsolated {
      service.handleTapEvent(type: type, event: event)
    }
  }

  func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }
    } else if type == .keyDown {
      if let keyEvent = NSEvent(cgEvent: event) {
        handleKeyDown(keyEvent)
      }
    }
    return Unmanaged.passUnretained(event)
  }

  // MARK: - Event Processing

  func handleModifierFlagsChanged(_ flags: NSEvent.ModifierFlags) {
    observedModifierFlags = flags.intersection(.deviceIndependentFlagsMask)
  }

  private func handleKeyDown(_ event: NSEvent) {
    // Ignore key repeats to avoid spamming
    guard !event.isARepeat else { return }

    let flags = event.modifierFlags
      .union(observedModifierFlags)
      .intersection(.deviceIndependentFlagsMask)
    let hasCommand = flags.contains(.command)
    let hasOption = flags.contains(.option)
    let hasControl = flags.contains(.control)
    let hasShift = flags.contains(.shift)

    let hasModifier = hasCommand || hasOption || hasControl

    // Resolve from keyCode because synthesized NSEvents may not contain characters.
    let keyName = Self.keyDisplayName(for: event.keyCode, event: event)

    // Filter: only show when a modifier (⌘/⌥/⌃) is held, or a special key is pressed
    let isSpecialKey = Self.isSpecialKey(event.keyCode)
    guard hasModifier || isSpecialKey else { return }

    // Build display string: modifiers first, then key
    var parts: [String] = []
    if hasControl { parts.append("⌃") }
    if hasOption { parts.append("⌥") }
    if hasShift { parts.append("⇧") }
    if hasCommand { parts.append("⌘") }

    if let keyName {
      parts.append(keyName)
    }

    guard !parts.isEmpty else { return }
    let displayString = parts.joined(separator: " ")
    onKeystroke?(displayString)
  }

  // MARK: - Key Code Mapping

  /// Whether the keyCode is a special key (Return, Tab, arrows, function keys, etc.)
  private static func isSpecialKey(_ keyCode: UInt16) -> Bool {
    return specialKeyName(for: keyCode) != nil
  }

  /// Resolve a display name for the given keyCode.
  /// Priority: special key symbol → ShortcutConfig keyCode map → charactersIgnoringModifiers fallback.
  private static func keyDisplayName(for keyCode: UInt16, event: NSEvent) -> String? {
    // 1. Special keys (Return, Tab, Arrows, F-keys, etc.)
    if let special = specialKeyName(for: keyCode) {
      return special
    }

    // 2. KeyCode-based lookup via ShortcutConfig using the active keyboard layout.
    let mapped = ShortcutConfig.keyCodeToDisplayString(UInt32(keyCode))
    if mapped != "?" {
      return mapped
    }

    // 3. Last resort: use event characters (may be nil for synthesized events)
    if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
      return chars.uppercased()
    }

    return nil
  }

  /// Maps macOS virtual key codes to human-readable special key symbols
  private static func specialKeyName(for keyCode: UInt16) -> String? {
    switch keyCode {
    case 36: return "⏎"       // Return
    case 48: return "⇥"       // Tab
    case 49: return "␣"       // Space
    case 51: return "⌫"       // Delete
    case 53: return "⎋"       // Escape
    case 76: return "⌤"       // Enter (numpad)
    case 117: return "⌦"      // Forward Delete

    // Arrow keys
    case 123: return "←"
    case 124: return "→"
    case 125: return "↓"
    case 126: return "↑"

    // Function keys
    case 122: return "F1"
    case 120: return "F2"
    case 99: return "F3"
    case 118: return "F4"
    case 96: return "F5"
    case 97: return "F6"
    case 98: return "F7"
    case 100: return "F8"
    case 101: return "F9"
    case 109: return "F10"
    case 103: return "F11"
    case 111: return "F12"

    // Navigation
    case 115: return "Home"
    case 119: return "End"
    case 116: return "PgUp"
    case 121: return "PgDn"

    default: return nil
    }
  }
}
