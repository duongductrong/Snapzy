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
  enum TransportKey {
    case shuttleReverse
    case shuttlePause
    case shuttleForward
    case stepBackward
    case stepForward
    case trimStartToPlayhead
    case trimEndToPlayhead
    case addTextOverlay
    case toggleBookmark
    case toggleSnapping
  }

  private static let activeEditorLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
  private static let aKeyCode: UInt16 = 0 // kVK_ANSI_A
  private static let copyKeyCode: UInt16 = 8 // kVK_ANSI_C
  private static let tKeyCode: UInt16 = 17 // kVK_ANSI_T
  private static let rightBracketKeyCode: UInt16 = 30 // kVK_ANSI_RightBracket
  private static let leftBracketKeyCode: UInt16 = 33 // kVK_ANSI_LeftBracket
  private static let lKeyCode: UInt16 = 37 // kVK_ANSI_L
  private static let jKeyCode: UInt16 = 38 // kVK_ANSI_J
  private static let kKeyCode: UInt16 = 40 // kVK_ANSI_K
  private static let commaKeyCode: UInt16 = 43 // kVK_ANSI_Comma
  private static let nKeyCode: UInt16 = 45 // kVK_ANSI_N
  private static let mKeyCode: UInt16 = 46 // kVK_ANSI_M
  private static let periodKeyCode: UInt16 = 47 // kVK_ANSI_Period
  private static let spaceKeyCode: UInt16 = 49 // kVK_Space
  private static let escapeKeyCode: UInt16 = 53 // kVK_Escape
  private var restingLevel: NSWindow.Level = .normal
  private var themeObserver: AnyCancellable?
  private var consumedSpaceKeyDown = false
  private var consumedEscapeKeyDown = false
  private weak var mouseDownOutsideTextResponder: NSResponder?
  var onTogglePlayback: (() -> Void)?
  /// Intercepts J/K/L shuttle and ,/. frame stepping before AVPlayerView can hijack them.
  var onTransportKey: ((TransportKey) -> Bool)?
  /// Configurable AI prompt shortcut (default ⌘K). Returns whether the key was handled.
  var onAIPromptShortcut: (() -> Bool)?
  /// Intercepts ⌘A when no text input is active to select all items on the focused timeline track.
  var onSelectAllTrackItems: (() -> Bool)?

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

  /// True only when `firstResponder` is an actively editable text input (`NSTextView` or
  /// `NSTextField` with `isEditable == true`). Focused buttons (`NSButton`), sliders
  /// (`NSSlider`), pop-ups (`NSPopUpButton`), segmented controls (`NSSegmentedControl`),
  /// and static labels return `false` so Space and transport keys are never swallowed.
  var isActivelyEditingTextInput: Bool {
    if let textView = firstResponder as? NSTextView {
      return textView.isEditable
    }
    if let textField = firstResponder as? NSTextField {
      return textField.isEditable
    }
    return false
  }

  private var activeTextResponderView: NSView? {
    if let textView = firstResponder as? NSTextView, textView.isEditable {
      return textView
    }
    if let textField = firstResponder as? NSTextField, textField.isEditable {
      return textField
    }
    return nil
  }

  private func isWindowPoint(_ point: NSPoint, insideTextResponder responderView: NSView) -> Bool {
    let hitTarget: NSView = if let textView = responderView as? NSTextView,
                               textView.isFieldEditor,
                               let delegateView = textView.delegate as? NSView {
      delegateView
    } else if let scrollView = responderView.enclosingScrollView {
      scrollView
    } else {
      responderView
    }
    guard hitTarget.window === self else { return false }
    let rectInWindow = hitTarget.convert(hitTarget.bounds, to: nil).insetBy(dx: -4, dy: -4)
    return rectInWindow.contains(point)
  }

  override func sendEvent(_ event: NSEvent) {
    let modifiers = event.modifierFlags.intersection([
      .command, .shift, .option, .control, .function,
    ])

    // Track clicks outside an active text field so clicking a plain SwiftUI tile, slider,
    // or timeline track blurs the stranded NSTextView after mouseUp completes.
    if event.type == .leftMouseDown {
      if let textView = activeTextResponderView,
         !isWindowPoint(event.locationInWindow, insideTextResponder: textView) {
        mouseDownOutsideTextResponder = textView
      } else {
        mouseDownOutsideTextResponder = nil
      }
    } else if event.type == .leftMouseUp, let priorText = mouseDownOutsideTextResponder {
      mouseDownOutsideTextResponder = nil
      super.sendEvent(event)
      if firstResponder === priorText,
         let priorView = priorText as? NSView,
         !isWindowPoint(event.locationInWindow, insideTextResponder: priorView) {
        makeFirstResponder(nil)
      }
      return
    }

    // Escape always lets the user exit any focused text input so Space, J/K/L, ,/., T, S
    // work on the very next keystroke, EXCEPT when IME composition (`hasMarkedText`) is active
    // (e.g. Vietnamese Telex/VNI or Japanese Kana), where Esc cancels only the marked text.
    if event.type == .keyDown,
       modifiers.isEmpty,
       event.keyCode == Self.escapeKeyCode,
       firstResponder is NSTextView || firstResponder is NSTextField {
      if (firstResponder as? NSTextInputClient)?.hasMarkedText() == true {
        super.sendEvent(event)
        return
      }
      consumedEscapeKeyDown = true
      if let textView = firstResponder as? NSTextView, !textView.isFieldEditor {
        _ = performKeyEquivalent(with: event)
        textView.nextResponder?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: self)
      } else {
        super.sendEvent(event)
      }
      if firstResponder is NSTextView || firstResponder is NSTextField {
        makeFirstResponder(nil)
      }
      return
    }

    if event.type == .keyUp,
       event.keyCode == Self.escapeKeyCode,
       consumedEscapeKeyDown {
      consumedEscapeKeyDown = false
      return
    }

    // Swallow Space keyUp whenever Space is acting as the editor transport shortcut so a
    // focused NSButton / NSPopUpButton / NSSegmentedControl never triggers on keyUp.
    if event.type == .keyUp,
       event.keyCode == Self.spaceKeyCode,
       onTogglePlayback != nil,
       consumedSpaceKeyDown || (modifiers.isEmpty && !isActivelyEditingTextInput) {
      consumedSpaceKeyDown = false
      return
    }

    if event.type == .keyDown {
      let hasMarkedIME = (firstResponder as? NSTextInputClient)?.hasMarkedText() == true
      if modifiers.isEmpty, !isActivelyEditingTextInput, !hasMarkedIME {
        if event.keyCode == Self.spaceKeyCode, let onTogglePlayback {
          // Intercept before AVPlayerView or focused AppKit controls (NSButton, NSSlider,
          // NSPopUpButton, NSSegmentedControl) can consume Space.
          consumedSpaceKeyDown = true
          if !event.isARepeat {
            onTogglePlayback()
          }
          return
        }
        if let onTransportKey {
          switch event.keyCode {
          case Self.jKeyCode:
            if !event.isARepeat, onTransportKey(.shuttleReverse) {
              return
            }
            if event.isARepeat {
              return
            }
          case Self.kKeyCode:
            if !event.isARepeat, onTransportKey(.shuttlePause) {
              return
            }
            if event.isARepeat {
              return
            }
          case Self.lKeyCode:
            if !event.isARepeat, onTransportKey(.shuttleForward) {
              return
            }
            if event.isARepeat {
              return
            }
          case Self.commaKeyCode:
            if onTransportKey(.stepBackward) {
              return
            }
          case Self.periodKeyCode:
            if onTransportKey(.stepForward) {
              return
            }
          case Self.leftBracketKeyCode:
            if !event.isARepeat, onTransportKey(.trimStartToPlayhead) {
              return
            }
            if event.isARepeat {
              return
            }
          case Self.rightBracketKeyCode:
            if !event.isARepeat, onTransportKey(.trimEndToPlayhead) {
              return
            }
            if event.isARepeat {
              return
            }
          case Self.tKeyCode:
            if !event.isARepeat, onTransportKey(.addTextOverlay) {
              return
            }
            if event.isARepeat {
              return
            }
          case Self.mKeyCode:
            if !event.isARepeat, onTransportKey(.toggleBookmark) {
              return
            }
            if event.isARepeat {
              return
            }
          case Self.nKeyCode:
            if !event.isARepeat, onTransportKey(.toggleSnapping) {
              return
            }
            if event.isARepeat {
              return
            }
          default:
            break
          }
        }
      } else if event.keyCode == Self.spaceKeyCode {
        consumedSpaceKeyDown = false
      }
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

    let selectAllMods = event.modifierFlags.intersection([
      .command, .shift, .option, .control, .function,
    ])
    let rawChar = event.charactersIgnoringModifiers?.lowercased()
    let isSelectAllKey = rawChar == "a" || (event.keyCode == Self.aKeyCode && rawChar != "q")
    if event.type == .keyDown,
       selectAllMods == .command,
       isSelectAllKey,
       !isActivelyEditingTextInput,
       let onSelectAllTrackItems {
      if event.isARepeat {
        return true
      }
      if onSelectAllTrackItems() {
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
