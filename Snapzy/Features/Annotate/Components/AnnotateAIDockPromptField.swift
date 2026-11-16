//
//  AnnotateAIDockPromptField.swift
//  Snapzy
//
//  The Ask AI prompt's text field, backed by a plain NSTextField so focus is owned by
//  AppKit instead of SwiftUI's @FocusState.
//
//  Why: the canvas's KeyEventNSView reclaims first responder on every window update, and
//  the prompt is inserted mid-animation. A @FocusState write that lands before the field is
//  in the window is dropped while the state still reads `true`, so later writes are no-ops
//  and the field sits there without a caret. Here the field asks the window directly, waits
//  for its window if it has none yet, and checks that the field editor really took over.
//

import AppKit
import SwiftUI

struct AnnotateAIDockPromptField: NSViewRepresentable {
  @Binding var text: String
  let placeholder: String
  /// Bump to pull the caret into the field (opening the prompt, after a run, ⌘K again).
  let focusRequest: Int
  /// False while a run is in flight: the field steps aside and takes the caret back after.
  let isActive: Bool
  let onSubmit: () -> Void
  let onEscape: () -> Void

  static let font = NSFont.systemFont(ofSize: 13, weight: .medium)

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> PromptTextField {
    let field = PromptTextField()
    field.delegate = context.coordinator
    field.isBordered = false
    field.isBezeled = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = Self.font
    field.textColor = NSColor(LiquidGlassTokens.inkPrimary)
    field.lineBreakMode = .byClipping
    field.usesSingleLineMode = true
    field.maximumNumberOfLines = 1
    field.cell?.wraps = false
    field.cell?.isScrollable = true
    field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    field.stringValue = text
    field.onEscape = onEscape
    field.isEditable = isActive
    applyPlaceholder(to: field)
    context.coordinator.lastFocusRequest = focusRequest
    field.requestFocus()
    return field
  }

  func updateNSView(_ field: PromptTextField, context: Context) {
    context.coordinator.parent = self
    field.onEscape = onEscape
    // Don't stomp on marked text (IME composition) with a stale binding value.
    if field.stringValue != text, (field.currentEditor() as? NSTextView)?.hasMarkedText() != true {
      field.stringValue = text
    }
    if field.placeholderAttributedString?.string != placeholder {
      applyPlaceholder(to: field)
    }
    if field.isEditable != isActive {
      field.setActive(isActive)
    }
    if context.coordinator.lastFocusRequest != focusRequest {
      context.coordinator.lastFocusRequest = focusRequest
      field.requestFocus()
    }
  }

  private func applyPlaceholder(to field: NSTextField) {
    field.placeholderAttributedString = NSAttributedString(
      string: placeholder,
      attributes: [
        .font: Self.font,
        .foregroundColor: NSColor(LiquidGlassTokens.inkFaint),
      ]
    )
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: AnnotateAIDockPromptField
    var lastFocusRequest = 0

    init(_ parent: AnnotateAIDockPromptField) {
      self.parent = parent
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      parent.text = field.stringValue
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
      switch selector {
      case #selector(NSResponder.insertNewline(_:)):
        // Return confirms an IME candidate first, like every native field.
        guard !textView.hasMarkedText() else { return false }
        parent.text = textView.string
        parent.onSubmit()
        return true
      case #selector(NSResponder.cancelOperation(_:)):
        guard !textView.hasMarkedText() else { return false }
        parent.onEscape()
        return true
      default:
        return false
      }
    }
  }
}

final class PromptTextField: NSTextField {
  var onEscape: (() -> Void)?
  private var wantsFocus = false
  private var focusAttempts = 0

  override var acceptsFirstResponder: Bool { isEditable }

  /// Puts the caret in the field now, or as soon as the field reaches a window, retrying
  /// briefly while the dock's insertion animation and the canvas's responder reclaim settle.
  func requestFocus() {
    wantsFocus = true
    focusAttempts = 0
    attemptFocus()
  }

  /// Whether a prompt field holds the keyboard in `window`.
  static func isEditing(in window: NSWindow?) -> Bool {
    (window?.firstResponder as? NSTextView)?.delegate is PromptTextField
  }

  var isEditing: Bool {
    guard let editor = currentEditor() else { return false }
    return window?.firstResponder === editor
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if wantsFocus { attemptFocus() }
  }

  private func attemptFocus() {
    guard wantsFocus, isEditable, let window else { return }
    ensureKeyWindow()
    if isEditing {
      wantsFocus = false
      return
    }
    // Opening the prompt is an explicit ask for the keyboard, so take it even from an
    // annotation's text editor that is still tearing down.
    window.makeFirstResponder(self)
    if isEditing {
      wantsFocus = false
      placeCaretAtEnd()
      return
    }
    focusAttempts += 1
    guard focusAttempts < 10 else {
      wantsFocus = false
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
      self?.attemptFocus()
    }
  }

  /// Steps aside for a run (the canvas keeps its shortcuts) and returns the caret after,
  /// unless the user put the keyboard somewhere else meanwhile.
  func setActive(_ active: Bool) {
    if active {
      isEditable = true
      let responder = window?.firstResponder
      if responder == nil || responder is NSWindow || responder is KeyEventNSView {
        requestFocus()
      }
    } else {
      wantsFocus = false
      if isEditing { window?.makeFirstResponder(nil) }
      isEditable = false
    }
  }

  /// AppKit only draws the caret in the key window. The inline overlay is a nonactivating
  /// panel that drops key status between text inputs (a run, Settings, another app), and a
  /// field that is already first responder there would otherwise take typing with no caret.
  private func ensureKeyWindow() {
    guard let window, !window.isKeyWindow, window.canBecomeKey else { return }
    window.makeKey()
  }

  /// Lets a click on the field key a `becomesKeyOnlyIfNeeded` panel.
  override var needsPanelToBecomeKey: Bool { isEditable }

  override func mouseDown(with event: NSEvent) {
    if isEditable { ensureKeyWindow() }
    super.mouseDown(with: event)
    // A click is an explicit ask for the caret; make sure it actually landed.
    if isEditable, !isEditing { requestFocus() }
  }

  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted {
      ensureKeyWindow()
      styleFieldEditor()
      placeCaretAtEnd()
    }
    return accepted
  }

  /// A caret in the field's ink, so it reads on the glass in both appearances.
  private func styleFieldEditor() {
    guard let editor = currentEditor() as? NSTextView else { return }
    editor.insertionPointColor = NSColor(LiquidGlassTokens.inkPrimary)
  }

  /// AppKit selects all on focus; a prompt continues where you left off instead.
  private func placeCaretAtEnd() {
    guard let editor = currentEditor() else { return }
    editor.selectedRange = NSRange(location: (stringValue as NSString).length, length: 0)
  }

  override func cancelOperation(_ sender: Any?) {
    onEscape?()
  }
}
