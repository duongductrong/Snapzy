//
//  AnnotateImageTransformMenu.swift
//  Snapzy
//
//  Rotate / flip actions, offered from the toolbar Transform button and the canvas context menu.
//  Shortcuts are handled in `AnnotateWindow.performKeyEquivalent`; the menus only show the hints
//  so users can learn them.
//

import AppKit
import SwiftUI

// MARK: - Actions

/// One whole-image transform action with its shortcut hint.
struct AnnotateImageTransformAction: Identifiable {
  let id: String
  let title: String
  let symbol: String
  /// Lower-case key, matching `AnnotateWindow`'s key-code handling.
  let key: Character
  let modifiers: NSEvent.ModifierFlags
  let perform: (AnnotateState) -> Void
  let startsGroup: Bool

  static let all: [AnnotateImageTransformAction] = [
    AnnotateImageTransformAction(
      id: "rotate-left", title: L10n.AnnotateUI.rotateLeft, symbol: "rotate.left",
      key: "l", modifiers: [.command], perform: { $0.rotateImage(clockwise: false) }, startsGroup: false
    ),
    AnnotateImageTransformAction(
      id: "rotate-right", title: L10n.AnnotateUI.rotateRight, symbol: "rotate.right",
      key: "r", modifiers: [.command], perform: { $0.rotateImage(clockwise: true) }, startsGroup: false
    ),
    AnnotateImageTransformAction(
      id: "flip-horizontal", title: L10n.AnnotateUI.flipHorizontal,
      symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right",
      key: "h", modifiers: [.command, .control], perform: { $0.flipImage(.horizontal) }, startsGroup: true
    ),
    AnnotateImageTransformAction(
      id: "flip-vertical", title: L10n.AnnotateUI.flipVertical,
      symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down",
      key: "v", modifiers: [.command, .control], perform: { $0.flipImage(.vertical) }, startsGroup: false
    ),
  ]

  var swiftUIModifiers: EventModifiers {
    var result: EventModifiers = []
    if modifiers.contains(.command) { result.insert(.command) }
    if modifiers.contains(.control) { result.insert(.control) }
    if modifiers.contains(.option) { result.insert(.option) }
    if modifiers.contains(.shift) { result.insert(.shift) }
    return result
  }
}

// MARK: - Context Menu Items

/// SwiftUI items for the canvas `.contextMenu`.
struct AnnotateImageTransformMenuItems: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    ForEach(AnnotateImageTransformAction.all) { action in
      if action.startsGroup {
        Divider()
      }
      Button {
        action.perform(state)
      } label: {
        Label(action.title, systemImage: action.symbol)
      }
      .keyboardShortcut(KeyEquivalent(action.key), modifiers: action.swiftUIModifiers)
    }
    .disabled(!state.canRotateImage)
  }
}

// MARK: - Toolbar Button

/// A `ToolbarButton` with a pull-down chevron that pops an `NSMenu` below itself. A SwiftUI `Menu` label is
/// re-rendered by AppKit (thinner, dimmer glyph, no hover glass) and drops shortcut hints,
/// so the toolbar slot uses a native menu instead to match its neighbours exactly.
struct AnnotateImageTransformToolbarButton: View {
  @ObservedObject var state: AnnotateState
  @State private var anchor = MenuAnchor()
  @State private var isMenuOpen = false

  var body: some View {
    ToolbarButton(
      icon: "rectangle.landscape.rotate",
      isSelected: isMenuOpen,
      activeGlassTint: nil,
      showsMenuIndicator: true
    ) {
      presentMenu()
    }
    .background(MenuAnchorView(anchor: anchor))
    .disabled(!state.canRotateImage)
  }

  private func presentMenu() {
    guard let view = anchor.view else { return }
    let menu = NSMenu()
    menu.autoenablesItems = false
    for action in AnnotateImageTransformAction.all {
      if action.startsGroup {
        menu.addItem(.separator())
      }
      let item = ClosureMenuItem(title: action.title, keyEquivalent: String(action.key)) { [weak state] in
        guard let state else { return }
        action.perform(state)
      }
      item.keyEquivalentModifierMask = action.modifiers
      item.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)
      item.isEnabled = state.canRotateImage
      menu.addItem(item)
    }

    isMenuOpen = true
    // Drop just below the button's leading edge, like a native toolbar pull-down.
    let origin = NSPoint(x: 0, y: view.isFlipped ? view.bounds.height + 4 : -4)
    menu.popUp(positioning: nil, at: origin, in: view)
    isMenuOpen = false
  }
}

private final class ClosureMenuItem: NSMenuItem {
  private let handler: () -> Void

  init(title: String, keyEquivalent: String, handler: @escaping () -> Void) {
    self.handler = handler
    super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
    target = self
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func fire() {
    handler()
  }
}

private final class MenuAnchor {
  weak var view: NSView?
}

private struct MenuAnchorView: NSViewRepresentable {
  let anchor: MenuAnchor

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    anchor.view = view
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    anchor.view = nsView
  }
}
