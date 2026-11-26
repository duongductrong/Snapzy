//
//  AutomationCanvasWindowController.swift
//  Snapzy
//
//  Opens the canvas editor in its own resizable window, one per automation.
//  The canvas fills the window under a transparent title bar: only the traffic
//  lights stay, and the name, actions, zoom and inspector float over the canvas
//  (see AutomationCanvasEditorView). The window title is still set, for the
//  Window menu and Mission Control. Save writes to the store and keeps the
//  window open; closing with unsaved edits asks first.
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
private final class AutomationCanvasWindowSession: NSObject, NSWindowDelegate {
  let window: NSWindow
  private let model: AutomationCanvasEditorModel
  private let onOpenInList: ((Automation, Bool) -> Void)?
  private let onClosed: (UUID) -> Void
  private let titlebar = AutomationCanvasTitlebarMetrics()
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
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
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
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.backgroundColor = .underPageBackgroundColor
    // An empty unified toolbar only makes the title bar as tall as a toolbar
    // window's, so the traffic lights sit centered in the row the floating
    // actions share. It has no items and, with the transparent title bar, no bar.
    let toolbar = NSToolbar(identifier: "AutomationCanvasToolbar")
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = false
    window.toolbar = toolbar
    window.toolbarStyle = .unified
    window.titlebarSeparatorStyle = .none
    let hostingView = NSHostingView(rootView: AutomationCanvasRoot(
      model: model,
      titlebar: titlebar,
      onSave: { [weak self] in self?.save() },
      onOpenInList: onOpenInList == nil ? nil : { [weak self] in self?.openInList() }
    ))
    if #available(macOS 14.0, *) {
      // The window's toolbar and title are managed here, not by SwiftUI.
      hostingView.sceneBridgingOptions = []
    }
    window.contentView = hostingView
    updateChrome()

    // The title follows the model, a run loop turn later (objectWillChange fires
    // before the change lands).
    model.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.updateChrome() }
      .store(in: &observers)
    ThemeManager.shared.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.window.appearance = ThemeManager.shared.nsAppearance }
      .store(in: &observers)
    let center = NotificationCenter.default
    for name in [
      NSWindow.didResizeNotification,
      NSWindow.didEnterFullScreenNotification,
      NSWindow.didExitFullScreenNotification,
    ] {
      center.publisher(for: name, object: window)
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.updateTitlebarMetrics() }
        .store(in: &observers)
    }
  }

  func show() {
    if !window.isVisible { window.center() }
    window.makeKeyAndOrderFront(nil)
    updateTitlebarMetrics()
    DispatchQueue.main.async { [weak self] in self?.updateTitlebarMetrics() }
  }

  /// Where the traffic lights are, from the top-left of the content, so the
  /// floating header lines up with them. In full screen they are hidden with
  /// the menu bar and the header takes their place.
  private func updateTitlebarMetrics() {
    guard
      !window.styleMask.contains(.fullScreen),
      let close = window.standardWindowButton(.closeButton),
      let zoom = window.standardWindowButton(.zoomButton),
      !close.isHidden,
      let content = window.contentView
    else {
      titlebar.update(centerY: nil, trailingX: nil)
      return
    }
    let closeRect = content.convert(close.convert(close.bounds, to: nil), from: nil)
    let zoomRect = content.convert(zoom.convert(zoom.bounds, to: nil), from: nil)
    let centerY = content.isFlipped ? closeRect.midY : content.bounds.height - closeRect.midY
    titlebar.update(centerY: centerY, trailingX: zoomRect.maxX)
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
    window.isDocumentEdited = model.hasUnsavedChanges
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
  @ObservedObject var titlebar: AutomationCanvasTitlebarMetrics
  @ObservedObject private var cloudManager = CloudManager.shared
  let onSave: () -> Void
  let onOpenInList: (() -> Void)?

  var body: some View {
    AutomationCanvasEditorView(
      model: model,
      titlebar: titlebar,
      isCloudConfigured: cloudManager.isConfigured,
      onSave: onSave,
      onOpenInList: onOpenInList
    )
  }
}

/// Position of the window's traffic lights, for lining the floating header up
/// with them. `nil` when they are hidden (full screen).
@MainActor
final class AutomationCanvasTitlebarMetrics: ObservableObject {
  /// Vertical center of the traffic lights, from the top of the content.
  @Published private(set) var buttonsCenterY: CGFloat?
  /// Right edge of the zoom button, from the leading edge of the content.
  @Published private(set) var buttonsTrailingX: CGFloat?

  func update(centerY: CGFloat?, trailingX: CGFloat?) {
    let centerY = centerY.map { $0.rounded() }
    let trailingX = trailingX.map { $0.rounded() }
    if buttonsCenterY != centerY { buttonsCenterY = centerY }
    if buttonsTrailingX != trailingX { buttonsTrailingX = trailingX }
  }
}
