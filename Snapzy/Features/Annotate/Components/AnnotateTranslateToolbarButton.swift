//
//  AnnotateTranslateToolbarButton.swift
//  Snapzy
//
//  Toolbar pull-down for Auto Translate, built like the Rotate & Flip button: one
//  `ToolbarButton` with a chevron and the same hover glass, opening a native menu
//  with icons and shortcut hints (Translate Whole Image, Translate Area…, target
//  language, engine, export toggle, removal).
//

import AppKit
import SwiftUI

struct AnnotateTranslateToolbarButton: View {
  @ObservedObject var state: AnnotateState
  @ObservedObject private var shortcuts = AnnotateShortcutManager.shared
  @State private var anchor = MenuAnchor()
  @State private var isMenuOpen = false

  var body: some View {
    ToolbarButton(
      icon: "translate",
      isSelected: isMenuOpen || state.isAutoTranslateRunning || state.isTranslateAreaSelecting,
      activeGlassTint: nil,
      showsMenuIndicator: true
    ) {
      presentMenu()
    }
    .background(MenuAnchorView(anchor: anchor))
    .disabled(!state.canAutoTranslate && !state.isAutoTranslateRunning)
    .help(helpText)
  }

  private var helpText: String {
    if state.isAutoTranslateRunning {
      return "\(L10n.Translate.translating) — \(L10n.AnnotateTranslate.cancelHint)"
    }
    return "\(L10n.AnnotateTranslate.actionTitle) → \(state.autoTranslateTarget.displayName)"
  }

  private func presentMenu() {
    guard let view = anchor.view else { return }
    let menu = NSMenu()
    menu.autoenablesItems = false

    if state.isAutoTranslateRunning {
      let cancel = ClosureMenuItem(title: L10n.Common.cancel, keyEquivalent: "\u{1b}") { [weak state] in
        state?.cancelAutoTranslate()
      }
      cancel.keyEquivalentModifierMask = []
      cancel.image = symbol("stop.circle")
      menu.addItem(cancel)
      menu.addItem(.separator())
    }

    let canRun = state.canAutoTranslate && !state.isAutoTranslateRunning
    let whole = ClosureMenuItem(title: L10n.AnnotateTranslate.translateWholeImage, keyEquivalent: "") { [weak state] in
      state?.autoTranslate()
    }
    whole.image = symbol("translate")
    whole.isEnabled = canRun
    applyShortcut(.autoTranslate, to: whole)
    menu.addItem(whole)

    let area = ClosureMenuItem(
      title: state.isTranslateAreaSelecting ? L10n.AnnotateTranslate.cancelAreaSelection : L10n.AnnotateTranslate.translateArea,
      keyEquivalent: ""
    ) { [weak state] in
      state?.toggleTranslateAreaSelection()
    }
    area.image = symbol("text.viewfinder")
    area.isEnabled = canRun
    applyShortcut(.translateArea, to: area)
    menu.addItem(area)

    menu.addItem(.separator())

    let current = state.autoTranslateTarget
    let languageItem = NSMenuItem(
      title: "\(L10n.Translate.targetLanguageLabel): \(current.displayName)",
      action: nil,
      keyEquivalent: ""
    )
    languageItem.image = symbol("globe")
    let languageMenu = NSMenu()
    for language in TranslationLanguage.all.sorted(by: { $0.displayName < $1.displayName }) {
      let item = ClosureMenuItem(title: language.displayName, keyEquivalent: "") { [weak state] in
        state?.setAutoTranslateTarget(language)
      }
      item.state = language == current ? .on : .off
      languageMenu.addItem(item)
    }
    languageItem.submenu = languageMenu
    menu.addItem(languageItem)

    let engine = NSMenuItem(title: engineDescription, action: nil, keyEquivalent: "")
    engine.image = symbol(isRemoteEngine ? "network" : "lock.laptopcomputer")
    engine.isEnabled = false
    menu.addItem(engine)

    let settings = ClosureMenuItem(title: L10n.Translate.openSettings, keyEquivalent: "") {
      AnnotateState.openTranslationSettings()
    }
    settings.image = symbol("gearshape")
    menu.addItem(settings)

    menu.addItem(.separator())

    let export = ClosureMenuItem(title: L10n.AnnotateTranslate.includeInExport, keyEquivalent: "") { [weak state] in
      guard let state else { return }
      state.setIncludesTranslationsInExport(!state.includesTranslationsInExport)
    }
    export.image = symbol("square.and.arrow.up")
    export.state = state.includesTranslationsInExport ? .on : .off
    menu.addItem(export)

    let remove = ClosureMenuItem(title: L10n.AnnotateTranslate.removeTranslations, keyEquivalent: "") { [weak state] in
      state?.removeAllTranslations()
    }
    remove.image = symbol("trash")
    remove.isEnabled = state.translationAnnotationCount > 0 && !state.isAutoTranslateRunning
    menu.addItem(remove)

    isMenuOpen = true
    // Drop just below the button's leading edge, like the Rotate & Flip pull-down.
    let origin = NSPoint(x: 0, y: view.isFlipped ? view.bounds.height + 4 : -4)
    menu.popUp(positioning: nil, at: origin, in: view)
    isMenuOpen = false
  }

  /// Shows the configured shortcut as the item's key hint (display only: the menu
  /// lives only while open, and the window handles the real shortcut).
  private func applyShortcut(_ kind: AnnotateActionShortcutKind, to item: NSMenuItem) {
    guard shortcuts.isActionShortcutEnabled(for: kind),
          let config = shortcuts.shortcut(for: kind),
          let key = config.menuKeyEquivalent else { return }
    item.keyEquivalent = key
    item.keyEquivalentModifierMask = config.menuModifierFlags
  }

  private func symbol(_ name: String) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)
  }

  private var isRemoteEngine: Bool {
    if case .remote = TranslationEngineResolver().resolve() { return true }
    return false
  }

  private var engineDescription: String {
    switch TranslationEngineResolver().resolve() {
    case .apple:
      return L10n.AnnotateTranslate.engineApple
    case .remote(let model):
      return L10n.AnnotateTranslate.engineRemote(model.name)
    case .unavailable:
      return L10n.Translate.requiresMacOS15Title
    }
  }
}
