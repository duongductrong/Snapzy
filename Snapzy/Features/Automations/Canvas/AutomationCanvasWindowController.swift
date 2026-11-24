//
//  AutomationCanvasWindowController.swift
//  Snapzy
//
//  Opens the canvas editor in its own resizable window, one per automation.
//  The window is a standard titled window with a unified AppKit toolbar (add,
//  tidy up, zoom, save, inspector); the title is the automation's name and the
//  subtitle says when there are unsaved changes. Save writes to the store and
//  keeps the window open; closing with unsaved edits asks first.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class AutomationCanvasWindowController {
  static let shared = AutomationCanvasWindowController()

  private var sessions: [UUID: AutomationCanvasWindowSession] = [:]

  private init() {}

  /// Shows the canvas for `automation`, or brings its window forward if open.
  /// `onOpenInList` hands the current draft to the list editor.
  func open(
    _ automation: Automation,
    isNew: Bool,
    onOpenInList: ((Automation, Bool) -> Void)? = nil
  ) {
    if let session = sessions[automation.id] {
      session.window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let session = AutomationCanvasWindowSession(
      automation: automation,
      isNew: isNew,
      onOpenInList: onOpenInList,
      onClosed: { [weak self] id in self?.sessions[id] = nil }
    )
    sessions[automation.id] = session
    if NSApp.activationPolicy() != .regular {
      NSApp.setActivationPolicy(.regular)
    }
    NSApp.activate(ignoringOtherApps: true)
    session.show()
  }

  func isOpen(_ id: UUID) -> Bool {
    sessions[id] != nil
  }
}

@MainActor
private final class AutomationCanvasWindowSession: NSObject, NSWindowDelegate, NSToolbarDelegate, NSToolbarItemValidation, NSMenuItemValidation {
  let window: NSWindow
  private let model: AutomationCanvasEditorModel
  private let onOpenInList: ((Automation, Bool) -> Void)?
  private let onClosed: (UUID) -> Void
  private var observers = Set<AnyCancellable>()
  private var allowsClose = false

  init(
    automation: Automation,
    isNew: Bool,
    onOpenInList: ((Automation, Bool) -> Void)?,
    onClosed: @escaping (UUID) -> Void
  ) {
    model = AutomationCanvasEditorModel(automation: automation, isNew: isNew)
    self.onOpenInList = onOpenInList
    self.onClosed = onClosed
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    super.init()

    window.delegate = self
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenPrimary]
    window.contentMinSize = NSSize(width: 760, height: 480)
    window.tabbingMode = .disallowed
    window.isMovableByWindowBackground = false
    window.appearance = ThemeManager.shared.nsAppearance
    window.contentView = NSHostingView(rootView: AutomationCanvasRoot(
      model: model,
      onSave: { [weak self] in self?.save() }
    ))
    let toolbar = NSToolbar(identifier: "AutomationCanvasToolbar")
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = false
    window.toolbar = toolbar
    window.toolbarStyle = .unified
    updateChrome()

    // Title, subtitle and toolbar state follow the model, a run loop turn later
    // (objectWillChange fires before the change lands).
    model.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.updateChrome() }
      .store(in: &observers)
    ThemeManager.shared.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.window.appearance = ThemeManager.shared.nsAppearance }
      .store(in: &observers)
  }

  func show() {
    if !window.isVisible { window.center() }
    window.makeKeyAndOrderFront(nil)
  }

  // MARK: - Actions

  @discardableResult
  private func save() -> Bool {
    guard !model.issues.contains(where: \.blocksRun) else { return false }
    let saved = model.prepareSave()
    let store = AutomationStore.shared
    if model.isNew {
      guard store.add(saved) else {
        let alert = NSAlert()
        alert.messageText = L10n.Automations.limitReached(AutomationStore.maxAutomations)
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window)
        return false
      }
    } else {
      // Deleted in Settings while this window was open: nothing to update.
      guard saved.isSystemDefault || store.automation(id: saved.id) != nil else {
        let alert = NSAlert()
        alert.messageText = L10n.Automations.canvasDeletedTitle
        alert.informativeText = L10n.Automations.canvasDeletedMessage
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window)
        return false
      }
      store.update(saved)
    }
    model.didSave(store.automation(id: saved.id) ?? saved)
    return true
  }

  private func openInList() {
    guard let onOpenInList else { return }
    let draft = model.draft
    let isNew = model.isNew
    allowsClose = true
    window.close()
    onOpenInList(draft, isNew)
  }

  private func updateChrome() {
    let name = model.automation.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = name.isEmpty ? L10n.Automations.defaultName : name
    if window.title != title { window.title = title }
    let subtitle = model.hasUnsavedChanges ? L10n.Automations.canvasUnsaved : ""
    if window.subtitle != subtitle { window.subtitle = subtitle }
    window.toolbar?.validateVisibleItems()
  }

  // MARK: - Toolbar

  private enum Item {
    static let addStep = NSToolbarItem.Identifier("automationCanvas.addStep")
    static let tidyUp = NSToolbarItem.Identifier("automationCanvas.tidyUp")
    static let zoom = NSToolbarItem.Identifier("automationCanvas.zoom")
    static let zoomToFit = NSToolbarItem.Identifier("automationCanvas.zoomToFit")
    static let save = NSToolbarItem.Identifier("automationCanvas.save")
    static let more = NSToolbarItem.Identifier("automationCanvas.more")
    static let inspector = NSToolbarItem.Identifier("automationCanvas.inspector")
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [Item.addStep, Item.tidyUp, .flexibleSpace, Item.zoom, Item.zoomToFit, .space, Item.save, Item.more, Item.inspector]
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarDefaultItemIdentifiers(toolbar)
  }

  func toolbar(
    _ toolbar: NSToolbar,
    itemForItemIdentifier identifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    switch identifier {
    case Item.addStep:
      return button(identifier, symbol: "plus", label: L10n.Automations.addStep, help: L10n.Automations.canvasAddStepHelp, action: #selector(addStep))
    case Item.tidyUp:
      return button(identifier, symbol: "rectangle.3.group", label: L10n.Automations.canvasTidyUp, help: L10n.Automations.canvasTidyUp, action: #selector(tidyUp))
    case Item.zoomToFit:
      return button(
        identifier,
        symbol: "arrow.up.left.and.down.right.magnifyingglass",
        label: L10n.Automations.canvasZoomToFit,
        help: L10n.Automations.canvasZoomToFit,
        action: #selector(zoomToFit)
      )
    case Item.inspector:
      return button(identifier, symbol: "sidebar.right", label: L10n.Automations.canvasToggleInspector, help: L10n.Automations.canvasToggleInspector, action: #selector(toggleInspector))
    case Item.zoom:
      let images = ["minus.magnifyingglass", "plus.magnifyingglass"].compactMap {
        NSImage(systemSymbolName: $0, accessibilityDescription: nil)
      }
      let group = NSToolbarItemGroup(
        itemIdentifier: identifier,
        images: images,
        selectionMode: .momentary,
        labels: [L10n.Automations.canvasZoomOut, L10n.Automations.canvasZoomIn],
        target: self,
        action: #selector(zoomSegment(_:))
      )
      group.label = L10n.Automations.canvasZoomIn
      for (item, help) in zip(group.subitems, [L10n.Automations.canvasZoomOut, L10n.Automations.canvasZoomIn]) {
        item.toolTip = help
      }
      return group
    case Item.save:
      let item = NSToolbarItem(itemIdentifier: identifier)
      item.title = L10n.Common.save
      item.label = L10n.Common.save
      item.toolTip = L10n.Common.save
      item.isBordered = true
      item.target = self
      item.action = #selector(saveFromToolbar)
      return item
    case Item.more:
      let item = NSMenuToolbarItem(itemIdentifier: identifier)
      item.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: L10n.Automations.moreActions)
      item.label = L10n.Automations.moreActions
      item.toolTip = L10n.Automations.moreActions
      item.showsIndicator = false
      let menu = NSMenu()
      if onOpenInList != nil {
        menu.addItem(withTitle: L10n.Automations.canvasOpenInList, action: #selector(openInListFromMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
      }
      menu.addItem(withTitle: L10n.Automations.canvasShowMinimap, action: #selector(toggleMinimap), keyEquivalent: "").target = self
      item.menu = menu
      return item
    default:
      return nil
    }
  }

  private func button(
    _ identifier: NSToolbarItem.Identifier,
    symbol: String,
    label: String,
    help: String,
    action: Selector
  ) -> NSToolbarItem {
    let item = NSToolbarItem(itemIdentifier: identifier)
    item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
    item.label = label
    item.toolTip = help
    item.isBordered = true
    item.target = self
    item.action = action
    return item
  }

  func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
    switch item.itemIdentifier {
    case Item.addStep:
      return model.canAddStep
    case Item.save:
      return model.hasUnsavedChanges && !model.issues.contains(where: \.blocksRun)
    default:
      return true
    }
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(toggleMinimap) {
      menuItem.state = model.isMinimapVisible ? .on : .off
    }
    return true
  }

  @objc private func addStep() {
    model.openPicker(after: model.selection)
  }

  @objc private func tidyUp() {
    model.tidyUp()
  }

  @objc private func zoomToFit() {
    withAnimation(.easeOut(duration: 0.2)) { model.zoomToFit() }
  }

  @objc private func zoomSegment(_ sender: NSToolbarItemGroup) {
    let factor: CGFloat = sender.selectedIndex == 0 ? 1 / 1.25 : 1.25
    withAnimation(.easeOut(duration: 0.15)) { model.zoom(by: factor) }
  }

  @objc private func toggleInspector() {
    model.isInspectorVisible.toggle()
  }

  @objc private func toggleMinimap() {
    model.isMinimapVisible.toggle()
  }

  @objc private func saveFromToolbar() {
    save()
  }

  @objc private func openInListFromMenu() {
    openInList()
  }

  // MARK: - NSWindowDelegate

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard !allowsClose, model.hasUnsavedChanges else { return true }
    let alert = NSAlert()
    alert.messageText = L10n.Automations.canvasDiscardTitle(window.title)
    alert.informativeText = L10n.Automations.canvasDiscardMessage
    alert.alertStyle = .warning
    let canSave = !model.issues.contains(where: \.blocksRun)
    alert.addButton(withTitle: L10n.Common.save).isEnabled = canSave
    alert.addButton(withTitle: L10n.Common.cancel)
    alert.addButton(withTitle: L10n.Automations.canvasDiscard).hasDestructiveAction = true
    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self else { return }
      switch response {
      case .alertFirstButtonReturn:
        if self.save() { self.closeNow() }
      case .alertThirdButtonReturn:
        self.closeNow()
      default:
        break
      }
    }
    return false
  }

  func windowWillClose(_ notification: Notification) {
    observers.removeAll()
    let id = model.automation.id
    let closing = window
    DispatchQueue.main.async { [onClosed] in
      closing.contentView = nil
      closing.delegate = nil
      onClosed(id)
      if !PreferencesWindowController.shared.isVisible {
        NSApp.revertActivationPolicyToAccessoryIfNeeded(excluding: closing)
      }
    }
  }

  private func closeNow() {
    allowsClose = true
    window.close()
  }
}

/// Root view: injects the cloud state the inspectors need.
private struct AutomationCanvasRoot: View {
  @ObservedObject var model: AutomationCanvasEditorModel
  @ObservedObject private var cloudManager = CloudManager.shared
  let onSave: () -> Void

  var body: some View {
    AutomationCanvasEditorView(
      model: model,
      isCloudConfigured: cloudManager.isConfigured,
      onSave: onSave
    )
  }
}
