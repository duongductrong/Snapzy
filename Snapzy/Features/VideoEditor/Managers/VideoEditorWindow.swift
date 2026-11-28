//
//  VideoEditorWindow.swift
//  Snapzy
//
//  Dark mode video editor window configuration
//

import AppKit
import Combine

// MARK: - Notifications

extension Notification.Name {
  static let videoEditorCloudUpload = Notification.Name("videoEditorCloudUpload")
}

/// Custom NSWindow for video editing with dark mode appearance
class VideoEditorWindow: NSWindow {
  nonisolated deinit {}

  private static let activeEditorLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
  private static let copyKeyCode: UInt16 = 8 // kVK_ANSI_C
  private static let spaceKeyCode: UInt16 = 49 // kVK_Space
  private var restingLevel: NSWindow.Level = .normal
  private var themeObserver: AnyCancellable?
  var onTogglePlayback: (() -> Void)?
  /// Configurable AI prompt shortcut (default ⌘K). Returns whether the key was handled.
  var onAIPromptShortcut: (() -> Bool)?

  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    configure()
  }

  override func layoutIfNeeded() {
    super.layoutIfNeeded()

    layoutTrafficLights()
  }

  private func configure() {
    applyTheme()
    setupThemeObserver()

    // Enable full-size content view
    styleMask.insert(.fullSizeContentView)

    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    minSize = NSSize(width: 400, height: 300)
    isReleasedWhenClosed = false
    center()

    // Explicit normal level for proper Cmd+Tab behavior
    level = restingLevel

    // Register as managed window for normal Cmd+` cycling
    collectionBehavior = [.managed, .participatesInCycle]

    applyCornerRadius()
  }

  private func setupThemeObserver() {
    themeObserver = ThemeManager.shared.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.applyTheme()
      }
  }

  func applyActiveEditorLevel() {
    level = Self.activeEditorLevel
  }

  func restoreRestingLevel() {
    level = restingLevel
  }

  override func close() {
    if let hostedContent = contentView {
      contentView = nil
      // Defer `NSHostingView.deinit` onto a raw C RunLoop turn outside any active
      // Swift Concurrency `Task` frame (works even when the window was never ordered front
      // and AppKit skips `windowWillClose`).
      CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
        withExtendedLifetime(hostedContent) {}
      }
      CFRunLoopWakeUp(CFRunLoopGetMain())
    }
    super.close()
  }

  func syncLevelWithFocusState() {
    level = (isKeyWindow || isMainWindow) ? Self.activeEditorLevel : restingLevel
  }

  /// Apply current theme from ThemeManager
  func applyTheme() {
    let themeManager = ThemeManager.shared
    appearance = themeManager.nsAppearance
    backgroundColor = WindowSurfacePalette.backgroundColor(for: themeManager.preferredAppearance)
  }

  override var canBecomeKey: Bool {
    true
  }

  override var canBecomeMain: Bool {
    true
  }

  override func sendEvent(_ event: NSEvent) {
    let modifiers = event.modifierFlags.intersection([
      .command, .shift, .option, .control, .function,
    ])
    if event.type == .keyDown,
       event.keyCode == Self.spaceKeyCode,
       modifiers.isEmpty,
       onTogglePlayback != nil,
       !(firstResponder is NSTextView),
       !(firstResponder is NSTextField) {
      // AVPlayerView can otherwise consume Space before the SwiftUI shortcut and
      // change its transport without updating the editor's playback state.
      if !event.isARepeat {
        onTogglePlayback?()
      }
      return
    }

    super.sendEvent(event)
  }

  /// Do not let an unhandled copy key equivalent fall through to NSWindow's
  /// default `keyDown`, which emits the macOS alert sound. SwiftUI/text
  /// responders still get first refusal through `super`; this only consumes a
  /// Command-C that no responder in the editor can handle.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    // Matched ahead of SwiftUI so it also works while the prompt field has the caret
    // (it toggles the prompt). Reserved editor combos are rejected by validation.
    if let onAIPromptShortcut,
       VideoEditorShortcutManager.shared.matches(.aiPrompt, event: event) {
      // Holding the combo must not flip the prompt open/closed on every repeat.
      if event.isARepeat {
        return true
      }
      if onAIPromptShortcut() {
        return true
      }
    }

    if super.performKeyEquivalent(with: event) {
      return true
    }

    let modifiers = event.modifierFlags.intersection([
      .command, .shift, .option, .control, .function,
    ])
    guard event.type == .keyDown,
          modifiers == .command,
          event.keyCode == Self.copyKeyCode
    else {
      return false
    }

    return true
  }
}
