//
//  QuickAccessOptimizePanelController.swift
//  Snapzy
//
//  Hosts the Optimize list and the Custom editor in a borderless child panel. The
//  Quick Access panel only accepts the mouse inside the card stack, so anything that
//  spills past the card has to live in a separate window anchored to the card.
//

import AppKit
import Combine
import SwiftUI

/// Remembers the AppKit view behind a card so callers can ask for its screen frame.
@MainActor
final class QuickAccessCardAnchor {
  weak var view: NSView?

  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  var screenFrame: NSRect? {
    guard let view, let window = view.window else { return nil }
    return window.convertToScreen(view.convert(view.bounds, to: nil))
  }
}

struct QuickAccessCardAnchorView: NSViewRepresentable {
  let anchor: QuickAccessCardAnchor

  func makeNSView(context _: Context) -> NSView {
    let view = PassthroughView()
    anchor.view = view
    return view
  }

  func updateNSView(_ nsView: NSView, context _: Context) {
    anchor.view = nsView
  }

  private final class PassthroughView: NSView {
    override func hitTest(_: NSPoint) -> NSView? { nil }
  }
}

/// Borderless panel that can take keyboard focus without activating Snapzy.
final class QuickAccessOptimizePanel: NSPanel {
  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    isFloatingPanel = true
    becomesKeyOnlyIfNeeded = false
    hidesOnDeactivate = false
    isOpaque = false
    backgroundColor = .clear
    // The SwiftUI view draws its own shadow so it can scale with the bubble animation.
    hasShadow = false
    isReleasedWhenClosed = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    animationBehavior = .utilityWindow
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickAccessOptimizePanelController {
  static let shared = QuickAccessOptimizePanelController()

  private var panel: QuickAccessOptimizePanel?
  private var menuModel: QuickAccessOptimizeMenuModel?
  private var customModel: QuickAccessOptimizeCustomModel?
  /// Hides whichever view is up with the bubble animation.
  private var setShown: ((Bool) -> Void)?
  private var presentedItemID: UUID?
  private var estimateTask: Task<Void, Never>?
  private var eventMonitors: [Any] = []
  private var itemsCancellable: AnyCancellable?
  private var heldItemID: UUID?
  /// A click on the card's Optimize button first dismisses the open list through the
  /// click monitor; remembering that lets the button act as a toggle.
  private var lastOutsideDismissal: (itemID: UUID, date: Date)?

  private init() {}

  var isPresented: Bool { panel != nil }

  /// Opens the list like a native pop-up menu: the current level lands right over
  /// `buttonFrame` (screen coordinates), or over the card's centre when the menu was
  /// opened without the button (e.g. from a shortcut).
  func present(for item: QuickAccessItem, buttonFrame: NSRect?, cardFrame: NSRect?) {
    if presentedItemID == item.id {
      dismiss()
      return
    }
    if let lastOutsideDismissal,
       lastOutsideDismissal.itemID == item.id,
       Date().timeIntervalSince(lastOutsideDismissal.date) < 0.4 {
      self.lastOutsideDismissal = nil
      return
    }
    dismiss()

    let store = QuickAccessOptimizeStore.shared
    guard !store.isOptimizing(item.id) else { return }
    guard let plan = store.plan(for: item) else {
      reportUnavailable()
      return
    }

    let anchor = buttonFrame ?? cardFrame
    let model = QuickAccessOptimizeMenuModel(
      itemID: item.id,
      plan: plan,
      presets: QuickAccessOptimizePresetStore.shared.presets
    )
    model.onChoose = { [weak self] row in
      self?.dismiss()
      switch row.kind {
      case let .level(level):
        store.applyReportingFailure(.level(level, encodedData: row.encodedData), to: item.id)
      case let .preset(preset):
        store.applyReportingFailure(.custom(preset.settings), to: item.id)
      case .custom:
        // Wait for the menu's close animation so the editor does not pop over it.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeDuration) {
          guard let current = QuickAccessManager.shared.items.first(where: { $0.id == item.id }) else { return }
          self?.presentCustom(for: current, anchor: anchor)
        }
      }
    }
    menuModel = model

    let hostingView = NSHostingView(rootView: QuickAccessOptimizeMenuView(model: model))
    hostingView.layoutSubtreeIfNeeded()
    let size = hostingView.fittingSize
    let rowCenter = QuickAccessOptimizeMenuView.rowCenterOffset(at: model.anchorIndex, in: model.rows)
    show(
      hostingView,
      frame: Self.frame(for: size, anchor: anchor, anchorOffsetFromTop: rowCenter, shadowPadding: QuickAccessOptimizeMenuView.shadowPadding),
      itemID: item.id,
      setShown: { [weak model] in model?.isShown = $0 }
    )

    estimateTask = store.estimate(plan: plan, for: item) { [weak model] level, data in
      model?.record(level, data: data)
    }
  }

  /// Opens the Custom editor centred on `anchor` (screen coordinates), starting from
  /// the settings used last time.
  func presentCustom(for item: QuickAccessItem, anchor: NSRect?) {
    dismiss()
    let store = QuickAccessOptimizeStore.shared
    guard !store.isOptimizing(item.id) else { return }
    guard let source = store.customSource(for: item) else {
      reportUnavailable()
      return
    }

    let model = QuickAccessOptimizeCustomModel(
      itemID: item.id,
      source: source,
      settings: QuickAccessOptimizePresetStore.shared.lastCustomSettings
    )
    model.onApply = { [weak self] settings, rendering in
      self?.dismiss()
      store.applyReportingFailure(.custom(settings, rendering: rendering), to: item.id)
    }
    model.onCancel = { [weak self] in self?.dismiss() }
    customModel = model

    let hostingView = NSHostingView(rootView: QuickAccessOptimizeCustomView(model: model))
    hostingView.layoutSubtreeIfNeeded()
    let size = hostingView.fittingSize
    show(
      hostingView,
      frame: Self.frame(for: size, anchor: anchor, anchorOffsetFromTop: size.height / 2, shadowPadding: QuickAccessOptimizeCustomView.shadowPadding),
      itemID: item.id,
      setShown: { [weak model] in model?.isShown = $0 }
    )
    model.start()
  }

  func dismiss() {
    estimateTask?.cancel()
    estimateTask = nil
    customModel?.stop()
    eventMonitors.forEach(NSEvent.removeMonitor)
    eventMonitors.removeAll()
    itemsCancellable = nil

    if let heldItemID {
      QuickAccessManager.shared.resumeCountdownForActivity(heldItemID)
      self.heldItemID = nil
    }

    if let panel {
      // Let the bubble shrink back before the window goes away.
      panel.ignoresMouseEvents = true
      let setShown = setShown
      withAnimation(Self.closeAnimation) { setShown?(false) }
      if Self.fadesWindow {
        NSAnimationContext.runAnimationGroup { context in
          context.duration = Self.closeDuration
          panel.animator().alphaValue = 0
        }
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeDuration) {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.close()
      }
    }
    panel = nil
    menuModel = nil
    customModel = nil
    setShown = nil
    presentedItemID = nil
  }

  private func show(_ hostingView: NSView, frame: NSRect, itemID: UUID, setShown: @escaping (Bool) -> Void) {
    let panel = QuickAccessOptimizePanel(contentRect: NSRect(origin: .zero, size: frame.size))
    panel.contentView = hostingView
    panel.setFrame(frame, display: false)

    if let parent = NSApp.windows.first(where: { $0 is QuickAccessPanel && $0.isVisible }) {
      panel.level = parent.level
      parent.addChildWindow(panel, ordered: .above)
    } else {
      panel.level = .statusBar
    }
    let fadesWindow = Self.fadesWindow
    if fadesWindow { panel.alphaValue = 0 }
    panel.makeKeyAndOrderFront(nil)
    self.panel = panel
    self.setShown = setShown
    presentedItemID = itemID
    DispatchQueue.main.async { [weak panel] in
      withAnimation(Self.openAnimation) { setShown(true) }
      if fadesWindow, let panel {
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.16
          panel.animator().alphaValue = 1
        }
      }
    }

    QuickAccessManager.shared.pauseCountdownForActivity(itemID)
    heldItemID = itemID
    installEventMonitors()
    observeItemRemoval(itemID: itemID)
  }

  private func reportUnavailable() {
    QuickAccessSound.failed.play()
    AppToastManager.shared.show(message: L10n.QuickAccess.optimizeFailed, style: .error)
  }

  // MARK: - Animation

  private static var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  private static var openAnimation: Animation {
    reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.72)
  }

  private static let closeDuration: TimeInterval = 0.16

  /// On macOS 13–15 the backdrop is an `NSVisualEffectView`, which does not always
  /// honour SwiftUI opacity; fading the window too keeps open/close smooth there.
  private static var fadesWindow: Bool {
    !LiquidGlassCapabilities.usesNativeGlass(for: .system)
  }

  private static var closeAnimation: Animation {
    .easeIn(duration: reduceMotion ? 0.1 : closeDuration)
  }

  // MARK: - Placement

  /// Centres the panel on the anchor horizontally and puts the point
  /// `anchorOffsetFromTop` below its top edge (the current row, for the menu) on the
  /// anchor's centre, then clamps the result into the visible screen.
  static func frame(
    for size: NSSize,
    anchor: NSRect?,
    anchorOffsetFromTop: CGFloat,
    shadowPadding pad: CGFloat
  ) -> NSRect {
    let anchorPoint = anchor.map { NSPoint(x: $0.midX, y: $0.midY) } ?? NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(anchorPoint) } ?? NSScreen.main
    let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)

    var origin = NSPoint(
      x: (anchorPoint.x - size.width / 2).rounded(),
      y: (anchorPoint.y + anchorOffsetFromTop - size.height).rounded()
    )
    // The view's shadow padding may hang off screen; the glass itself may not.
    origin.x = min(max(origin.x, visible.minX - pad), visible.maxX - size.width + pad)
    origin.y = min(max(origin.y, visible.minY - pad), visible.maxY - size.height + pad)
    return NSRect(origin: origin, size: size)
  }

  // MARK: - Events

  private func installEventMonitors() {
    let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let panel = self.panel, event.window === panel else { return event }
      return self.handleKey(event) ? nil : event
    }
    let localClickMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
      guard let self, let panel = self.panel else { return event }
      if event.window !== panel {
        if let itemID = self.presentedItemID {
          self.lastOutsideDismissal = (itemID, Date())
        }
        self.dismiss()
      }
      return event
    }
    let globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] _ in
      Task { @MainActor in self?.dismiss() }
    }
    eventMonitors = [keyMonitor, localClickMonitor, globalClickMonitor].compactMap { $0 }
  }

  /// Menu navigation only; the Custom editor's own controls handle its keys.
  private func handleKey(_ event: NSEvent) -> Bool {
    guard let menuModel else { return false }
    switch Int(event.keyCode) {
    case 53: // Escape
      dismiss()
    case 125: // Down
      menuModel.moveHighlight(by: 1)
    case 126: // Up
      menuModel.moveHighlight(by: -1)
    case 36, 76, 49: // Return, Enter, Space
      menuModel.chooseHighlighted()
    default:
      return false
    }
    return true
  }

  private func observeItemRemoval(itemID: UUID) {
    itemsCancellable = QuickAccessManager.shared.$items
      .receive(on: DispatchQueue.main)
      .sink { [weak self] items in
        guard !items.contains(where: { $0.id == itemID }) else { return }
        self?.dismiss()
      }
  }
}
