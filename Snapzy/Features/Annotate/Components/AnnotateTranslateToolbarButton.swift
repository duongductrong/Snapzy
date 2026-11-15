//
//  AnnotateTranslateToolbarButton.swift
//  Snapzy
//
//  Toolbar entry for Auto Translate: click to translate (or cancel a run), chevron
//  for the target language, engine, export toggle and removal.
//

import AppKit
import SwiftUI

struct AnnotateTranslateToolbarButton: View {
  @ObservedObject var state: AnnotateState
  @ObservedObject private var shortcuts = AnnotateShortcutManager.shared
  @State private var anchor = MenuAnchor()
  @State private var isMenuOpen = false

  var body: some View {
    HStack(spacing: 0) {
      ToolbarButton(
        icon: "translate",
        isSelected: state.isAutoTranslateRunning,
        activeGlassTint: nil
      ) {
        state.toggleAutoTranslate()
      }
      .disabled(!state.canAutoTranslate && !state.isAutoTranslateRunning)
      .opacity(state.canAutoTranslate || state.isAutoTranslateRunning ? 1 : 0.4)
      .help(helpText)

      Button(action: presentMenu) {
        Image(systemName: "chevron.down")
          .font(.system(size: 7, weight: .bold))
          .opacity(isMenuOpen ? 0.9 : 0.55)
          .frame(width: ToolbarButton.menuIndicatorWidth + 2, height: ControlMetrics.toolbarButton)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .background(MenuAnchorView(anchor: anchor))
      .help(L10n.Translate.targetLanguageLabel)
    }
  }

  private var helpText: String {
    if state.isAutoTranslateRunning {
      return "\(L10n.Translate.translating) — \(L10n.AnnotateTranslate.cancelHint)"
    }
    let title = "\(L10n.AnnotateTranslate.actionTitle) → \(state.autoTranslateTarget.displayName)"
    guard shortcuts.isActionShortcutEnabled(for: .autoTranslate),
          let shortcut = shortcuts.autoTranslateShortcut else { return title }
    return "\(title) (\(shortcut.displayString))"
  }

  private func presentMenu() {
    guard let view = anchor.view else { return }
    let menu = NSMenu()
    menu.autoenablesItems = false

    if state.isAutoTranslateRunning {
      menu.addItem(ClosureMenuItem(title: L10n.Common.cancel, keyEquivalent: "") { [weak state] in
        state?.cancelAutoTranslate()
      })
    } else {
      let run = ClosureMenuItem(title: L10n.AnnotateTranslate.actionTitle, keyEquivalent: "") { [weak state] in
        state?.autoTranslate()
      }
      run.image = NSImage(systemSymbolName: "translate", accessibilityDescription: nil)
      run.isEnabled = state.canAutoTranslate
      menu.addItem(run)
    }

    menu.addItem(.separator())

    let languageItem = NSMenuItem(title: L10n.Translate.targetLanguageLabel, action: nil, keyEquivalent: "")
    let languageMenu = NSMenu()
    let current = state.autoTranslateTarget
    for language in TranslationLanguage.all.sorted(by: { $0.displayName < $1.displayName }) {
      let item = ClosureMenuItem(title: language.displayName, keyEquivalent: "") { [weak state] in
        state?.setAutoTranslateTarget(language)
      }
      item.state = language == current ? .on : .off
      languageMenu.addItem(item)
    }
    languageItem.submenu = languageMenu
    languageItem.title = "\(L10n.Translate.targetLanguageLabel): \(current.displayName)"
    menu.addItem(languageItem)

    let engine = NSMenuItem(title: engineDescription, action: nil, keyEquivalent: "")
    engine.isEnabled = false
    menu.addItem(engine)

    menu.addItem(ClosureMenuItem(title: L10n.Translate.openSettings, keyEquivalent: "") {
      AnnotateState.openTranslationSettings()
    })

    menu.addItem(.separator())

    let export = ClosureMenuItem(title: L10n.AnnotateTranslate.includeInExport, keyEquivalent: "") { [weak state] in
      guard let state else { return }
      state.setIncludesTranslationsInExport(!state.includesTranslationsInExport)
    }
    export.state = state.includesTranslationsInExport ? .on : .off
    menu.addItem(export)

    let remove = ClosureMenuItem(title: L10n.AnnotateTranslate.removeTranslations, keyEquivalent: "") { [weak state] in
      state?.removeAllTranslations()
    }
    remove.isEnabled = state.translationAnnotationCount > 0 && !state.isAutoTranslateRunning
    menu.addItem(remove)

    isMenuOpen = true
    let origin = NSPoint(x: 0, y: view.isFlipped ? view.bounds.height + 4 : -4)
    menu.popUp(positioning: nil, at: origin, in: view)
    isMenuOpen = false
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
