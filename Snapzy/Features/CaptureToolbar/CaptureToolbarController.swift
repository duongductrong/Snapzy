//
//  CaptureToolbarController.swift
//  Snapzy
//
//  Milestone 6 (#498): runs one capture-toolbar session.
//
//  1. `beginSession()` returns a `.captureToolbar` routing; the area capture
//     runs as usual (frozen / live, window picking, magnifier) but saves to
//     the temp folder and skips the after-capture steps.
//  2. `noteSelection(_:routing:)` records the selected rect (screen coords).
//  3. When the file arrives (`present(url:sessionID:)`), an outline marks the
//     selection and the toolbar appears under it (above when there is no room).
//  4. A button, its accelerator, Return (first button) or a double-click
//     inside the outline runs the action; Esc or a click elsewhere cancels
//     and deletes the unused capture.
//
//  Still-image actions run automation steps on the capture (one
//  implementation, principle 3); Screenshot runs the default after-capture
//  automation; Record / GIF / Scroll discard the still and start their own
//  flow on the same rect.
//

import AppKit
import SwiftUI

/// Starts the flows that need the rect instead of the still capture.
@MainActor
protocol CaptureToolbarRectStarting: AnyObject {
  /// `false` when the flow could not start (permission, another session).
  func startRecording(in rect: CGRect, routing: PostCaptureRouting) -> Bool
  func startScrollingCapture(in rect: CGRect) -> Bool
}

@MainActor
final class CaptureToolbarController {
  static let shared = CaptureToolbarController()

  weak var rectStarter: CaptureToolbarRectStarting?

  private struct Session {
    let id: UUID
    var rect: CGRect?
    var fileURL: URL?
  }

  private var session: Session?
  private var toolbarPanel: ToolbarPanel?
  private var outlineWindow: OutlineWindow?
  private var keyMonitor: Any?
  private var clickMonitor: Any?
  private var localClickMonitor: Any?
  private var entries: [CaptureToolbarEntry] = []

  private let configurationStore: CaptureToolbarConfigurationStore
  private let automationStore: AutomationStore

  init(configurationStore: CaptureToolbarConfigurationStore = .shared, automationStore: AutomationStore = .shared) {
    self.configurationStore = configurationStore
    self.automationStore = automationStore
  }

  var isActive: Bool { session != nil }

  // MARK: - Session

  /// A new session; the area capture carries the returned routing.
  func beginSession() -> PostCaptureRouting {
    dismiss(deleteCapture: true)
    let id = UUID()
    session = Session(id: id)
    DiagnosticLogger.shared.log(.info, .capture, "Capture toolbar session started", context: ["session": id.uuidString])
    return .captureToolbar(sessionID: id)
  }

  /// The selection the capture used (rect, or the picked window's frame).
  func noteSelection(_ rect: CGRect, routing: PostCaptureRouting) {
    guard case .captureToolbar(let id) = routing, session?.id == id else { return }
    session?.rect = rect
  }

  /// The capture behind the session was cancelled before a file was saved.
  func abandon(routing: PostCaptureRouting) {
    guard case .captureToolbar(let id) = routing, session?.id == id else { return }
    session = nil
  }

  /// The capture was saved: show the toolbar for it.
  func present(url: URL, sessionID: UUID) {
    guard session?.id == sessionID else {
      // A stale session (another one started): never lose the capture.
      DiagnosticLogger.shared.log(.warning, .capture, "Capture toolbar session unknown; running standard routing")
      Task { await PostCaptureActionHandler.shared.handleScreenshotCapture(url: Self.applyDefaultSave(url)) }
      return
    }
    session?.fileURL = url
    let rect = session?.rect ?? Self.fallbackRect()
    session?.rect = rect
    show(around: rect)
  }

  // MARK: - Items

  /// Visible buttons, automations resolved (missing ones dropped).
  func currentEntries() -> [CaptureToolbarEntry] {
    let automations = CaptureToolbarConfigurationStore.toolbarAutomations(automationStore)
    return configurationStore.configuration.visibleEntries(available: automations.map(\.id))
  }

  func title(for item: CaptureToolbarItem) -> String {
    switch item {
    case .builtin(let builtin): builtin.displayName
    case .automation(let id): automationStore.automation(id: id)?.displayName ?? L10n.Automations.unknownAutomation
    }
  }

  func symbol(for item: CaptureToolbarItem) -> String {
    switch item {
    case .builtin(let builtin): builtin.symbol
    case .automation(let id):
      automationStore.automation(id: id).map { $0.symbol ?? $0.sourceSymbol } ?? "bolt"
    }
  }

  // MARK: - Actions

  func perform(_ item: CaptureToolbarItem) {
    guard let session, let url = session.fileURL, let rect = session.rect else { return }
    hideUI()
    self.session = nil
    DiagnosticLogger.shared.log(.info, .capture, "Capture toolbar action", context: ["item": item.token])

    switch item {
    case .builtin(let builtin):
      run(builtin, url: url, rect: rect)
    case .automation(let id):
      guard let automation = automationStore.automation(id: id), automation.isEnabled, !automation.needsReview else {
        Task { await PostCaptureActionHandler.shared.handleScreenshotCapture(url: Self.applyDefaultSave(url)) }
        return
      }
      // The automation's own Save choice, applied now (the capture waited in temp).
      let finalURL = Self.applySave(url, save: automation.captureSpec?.saveToExportDirectory ?? false)
      Task {
        await AutomationRunner.shared.run(automation, files: [finalURL], invocation: .captureToolbar)
      }
    }
  }

  private func run(_ builtin: CaptureToolbarBuiltin, url: URL, rect: CGRect) {
    switch builtin {
    case .screenshot:
      // The default after-capture automation, with its Save choice applied now.
      Task {
        let finalURL = Self.applyDefaultSave(url)
        await PostCaptureActionHandler.shared.handleScreenshotCapture(url: finalURL)
      }
    case .record:
      startFromRect(still: url) { $0.startRecording(in: rect, routing: .standard) }
    case .gif:
      let routing = AutomationRunner.shared.begin(Self.gifAutomation(), invocation: .captureToolbar)
      startFromRect(still: url) { starter in
        let started = starter.startRecording(in: rect, routing: routing)
        if !started { AutomationRunner.shared.abandon(routing: routing) }
        return started
      }
    case .scroll:
      startFromRect(still: url) { $0.startScrollingCapture(in: rect) }
    case .copy, .save, .upload, .pin, .annotate, .ocr:
      let automation = Self.pipeline(for: builtin)
      Task {
        await AutomationRunner.shared.run(automation, files: [url], invocation: .captureToolbar, quiet: builtin.isQuiet)
      }
    }
  }

  /// Record / GIF / Scroll: the still is dropped only once the new flow started;
  /// otherwise it goes the standard way so nothing is lost.
  private func startFromRect(still url: URL, _ start: (CaptureToolbarRectStarting) -> Bool) {
    if let rectStarter, start(rectStarter) {
      Self.discard(url)
    } else {
      Task { await PostCaptureActionHandler.shared.handleScreenshotCapture(url: Self.applyDefaultSave(url)) }
    }
  }

  /// The system pipeline behind a still-image built-in.
  static func pipeline(for builtin: CaptureToolbarBuiltin) -> Automation {
    Automation(
      id: UUID(),
      name: builtin.displayName,
      symbol: builtin.symbol,
      source: .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false)),
      steps: (builtin.steps ?? []).map { AutomationStep($0) }
    )
  }

  /// GIF: a recording of the rect handed to the default recording steps.
  static func gifAutomation() -> Automation {
    let recordingDefault = AutomationStore.shared.defaultAutomation(for: .recording)
    return Automation(
      name: CaptureToolbarBuiltin.gif.displayName,
      symbol: CaptureToolbarBuiltin.gif.symbol,
      source: .capture(AutomationCaptureSpec(
        mode: .recordingArea,
        saveToExportDirectory: recordingDefault.captureSpec?.saveToExportDirectory ?? true,
        recordingOutput: .gif
      )),
      steps: recordingDefault.steps
    )
  }

  /// Moves a temp toolbar capture into the export folder when the default
  /// screenshot automation saves; returns where the file now is.
  private static func applyDefaultSave(_ url: URL) -> URL {
    applySave(url, save: AutomationStore.shared.defaultAutomation(for: .screenshot).captureSpec?.saveToExportDirectory == true)
  }

  private static func applySave(_ url: URL, save: Bool) -> URL {
    guard save,
          TempCaptureManager.shared.isTempFile(url),
          let saved = TempCaptureManager.shared.saveToExportLocation(tempURL: url)
    else { return url }
    return saved
  }

  private static func discard(_ url: URL) {
    guard TempCaptureManager.shared.isTempFile(url) else { return }
    try? FileManager.default.removeItem(at: url)
  }

  /// Without a known selection (unusual): the main screen's center.
  private static func fallbackRect() -> CGRect {
    let frame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    return CGRect(x: frame.midX - 200, y: frame.midY - 120, width: 400, height: 240)
  }

  // MARK: - Dismiss

  func cancel() {
    dismiss(deleteCapture: true)
  }

  private func dismiss(deleteCapture: Bool) {
    if deleteCapture, let url = session?.fileURL {
      Self.discard(url)
      DiagnosticLogger.shared.log(.info, .capture, "Capture toolbar cancelled")
    }
    session = nil
    hideUI()
  }

  // MARK: - UI

  private func show(around rect: CGRect) {
    hideUI()
    entries = currentEntries()
    let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main

    let outline = OutlineWindow(rect: rect) { [weak self] in self?.handleDoubleClick() }
    outline.orderFrontRegardless()
    outlineWindow = outline

    let view = CaptureToolbarView(
      entries: entries,
      title: { [weak self] in self?.title(for: $0) ?? "" },
      symbol: { [weak self] in self?.symbol(for: $0) ?? "circle" },
      onSelect: { [weak self] in self?.perform($0) },
      onCancel: { [weak self] in self?.cancel() }
    )
    let hosting = NSHostingView(rootView: view)
    let size = hosting.fittingSize
    let panel = ToolbarPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .popUpMenu
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.becomesKeyOnlyIfNeeded = false
    panel.contentView = hosting
    panel.setFrame(Self.toolbarFrame(size: size, selection: rect, screen: screen), display: true)
    panel.makeKeyAndOrderFront(nil)
    toolbarPanel = panel
    installMonitors()
    NSAccessibility.post(element: panel, notification: .focusedWindowChanged)
  }

  /// Centered under the selection; above it when there's no room; inside the
  /// screen's visible frame either way.
  static func toolbarFrame(size: NSSize, selection: CGRect, screen: NSScreen?) -> NSRect {
    let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let gap: CGFloat = 10
    var origin = NSPoint(x: selection.midX - size.width / 2, y: selection.minY - gap - size.height)
    if origin.y < visible.minY + 8 {
      origin.y = selection.maxY + gap
    }
    if origin.y + size.height > visible.maxY - 8 {
      // Selection fills the screen: float inside it, near the bottom.
      origin.y = max(visible.minY + 8, selection.minY + gap)
    }
    origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
    return NSRect(origin: origin, size: size)
  }

  private func handleDoubleClick() {
    guard let action = configurationStore.configuration.doubleClickAction else { return }
    if case .automation(let id) = action,
       !CaptureToolbarConfigurationStore.toolbarAutomations(automationStore).contains(where: { $0.id == id }) {
      return
    }
    perform(action)
  }

  private func installMonitors() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.toolbarPanel?.isKeyWindow == true else { return event }
      switch CaptureToolbarKeyResolver.resolve(
        keyCode: event.keyCode,
        characters: event.charactersIgnoringModifiers,
        hasCommandModifiers: !event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
        entries: self.entries
      ) {
      case .perform(let item):
        self.perform(item)
        return nil
      case .cancel:
        self.cancel()
        return nil
      case .ignored:
        return event
      }
    }
    clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
      Task { @MainActor in self?.cancel() }
    }
    // Clicks in Snapzy's own other windows (Settings, Quick Access) cancel too.
    localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      guard let self else { return event }
      if event.window !== self.toolbarPanel, event.window !== self.outlineWindow {
        self.cancel()
      }
      return event
    }
  }

  private func hideUI() {
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
    keyMonitor = nil
    clickMonitor = nil
    localClickMonitor = nil
    toolbarPanel?.orderOut(nil)
    toolbarPanel = nil
    outlineWindow?.orderOut(nil)
    outlineWindow = nil
  }

  /// Borderless panels can't become key by default; the toolbar must (accelerators).
  private final class ToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
  }

  /// Dashed frame around the selection; double-click inside runs the configured action.
  private final class OutlineWindow: NSPanel {
    init(rect: CGRect, onDoubleClick: @escaping () -> Void) {
      super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      isReleasedWhenClosed = false
      isOpaque = false
      backgroundColor = .clear
      hasShadow = false
      level = .popUpMenu
      collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
      let view = OutlineView(frame: NSRect(origin: .zero, size: rect.size))
      view.onDoubleClick = onDoubleClick
      contentView = view
      setFrame(rect, display: true)
      // Never in captures started from here (recording / scrolling on this rect).
      CaptureChromeWindowRegistry.shared.register(self, role: .captureOverlay)
    }

    override var canBecomeKey: Bool { false }
  }

  private final class OutlineView: NSView {
    var onDoubleClick: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
      NSColor.black.withAlphaComponent(0.04).setFill()
      bounds.fill()
      let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
      path.lineWidth = 2
      path.setLineDash([6, 4], count: 2, phase: 0)
      NSColor.controlAccentColor.setStroke()
      path.stroke()
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
      if event.clickCount == 2 { onDoubleClick?() }
    }
  }
}

/// Key handling, kept free of AppKit events so it can be tested.
enum CaptureToolbarKeyResolver {
  enum Result: Equatable {
    case perform(CaptureToolbarItem)
    case cancel
    case ignored
  }

  static func resolve(
    keyCode: UInt16,
    characters: String?,
    hasCommandModifiers: Bool,
    entries: [CaptureToolbarEntry]
  ) -> Result {
    switch keyCode {
    case 53: return .cancel  // Esc
    case 36, 76:  // Return / Enter: the first button
      return entries.first.map { .perform($0.item) } ?? .ignored
    default:
      guard !hasCommandModifiers,
            let key = CaptureToolbarEntry.normalizedAccelerator(characters),
            let entry = entries.first(where: { $0.accelerator == key })
      else { return .ignored }
      return .perform(entry.item)
    }
  }
}

extension CaptureToolbarBuiltin {
  var displayName: String {
    switch self {
    case .screenshot: L10n.CaptureToolbar.screenshot
    case .copy: L10n.CaptureToolbar.copy
    case .save: L10n.CaptureToolbar.save
    case .upload: L10n.CaptureToolbar.upload
    case .pin: L10n.CaptureToolbar.pin
    case .annotate: L10n.CaptureToolbar.annotate
    case .ocr: L10n.CaptureToolbar.text
    case .record: L10n.CaptureToolbar.record
    case .gif: "GIF"
    case .scroll: L10n.CaptureToolbar.scroll
    }
  }

  var symbol: String {
    switch self {
    case .screenshot: "camera.viewfinder"
    case .copy: "doc.on.clipboard"
    case .save: "square.and.arrow.down"
    case .upload: "icloud.and.arrow.up"
    case .pin: "pin"
    case .annotate: "pencil.and.scribble"
    case .ocr: "text.viewfinder"
    case .record: "record.circle"
    case .gif: "photo.stack"
    case .scroll: "arrow.up.and.down.text.horizontal"
    }
  }

  /// Instant local actions don't need the run HUD or a log entry.
  var isQuiet: Bool {
    self == .copy || self == .pin || self == .annotate
  }
}
