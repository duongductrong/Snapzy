import AppKit
import Combine
import SwiftUI

@MainActor
final class HistoryHangingManager: ObservableObject {
  static let shared = HistoryHangingManager()

  @Published private(set) var isVisible = false
  @Published private(set) var isRevealed = false
  @Published private(set) var pinnedIDs: Set<UUID> = []
  @Published var keepOpen = false

  private var panel: HistoryHangingPanel?
  private var cablePanel: HistoryHangingPanel?
  private var screen: NSScreen?
  private var timer: Timer?
  private var observations: Set<AnyCancellable> = []
  private var localMonitor: Any?
  private var globalMonitor: Any?
  private var hoverState = HistoryEdgeHoverState()
  private var lastEdgeScreen: NSScreen?
  private var awaitingPointer = false
  private var isMenuTracking = false
  private var isSuspendedForCapture = false
  private var isDismissing = false
  private var isStarted = false
  private var presentationID = UUID()
  private var pinWindowIDs: [UUID: UUID] = [:]
  private var pinTasks: [UUID: Task<Void, Never>] = [:]
  private let previewController = HistoryHangingPreviewController()
  private var hoveredRecordID: UUID?

  func start() {
    guard !isStarted else { return }
    isStarted = true
    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.updateConfiguration() }
      .store(in: &observations)
    NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
      .sink { [weak self] _ in self?.hide(animated: false) }
      .store(in: &observations)
    NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
      .sink { [weak self] _ in self?.hide(animated: false) }
      .store(in: &observations)
    NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
      .sink { [weak self] _ in self?.isMenuTracking = true }
      .store(in: &observations)
    NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
      .sink { [weak self] _ in self?.isMenuTracking = false }
      .store(in: &observations)
    CaptureHistoryStore.shared.$records
      .sink { [weak self] records in self?.closeRemovedPins(keeping: Set(records.map(\.id))) }
      .store(in: &observations)
    updateConfiguration()
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    observations.removeAll()
    isStarted = false
    hide(animated: false)
    pinTasks.values.forEach { $0.cancel() }
    pinTasks.removeAll()
    for id in pinWindowIDs.values {
      QuickAccessPinWindowManager.shared.close(id: id)
    }
    pinWindowIDs.removeAll()
    pinnedIDs.removeAll()
  }

  func updateConfiguration() {
    guard isStarted, HistoryDisplayStyle.stored() == .hanging else {
      timer?.invalidate()
      timer = nil
      hide(animated: false)
      return
    }
    for window in [panel, cablePanel].compactMap({ $0 }) {
      window.appearance = ThemeManager.shared.nsAppearance
      CaptureChromeWindowRegistry.configureAppWindow(window)
    }
    if UserDefaults.standard.snapzyHistoryEnabled || panel != nil {
      startPointerMonitoring()
    } else {
      timer?.invalidate()
      timer = nil
    }
  }

  var isMonitoring: Bool {
    timer != nil
  }

  private func startPointerMonitoring() {
    guard timer == nil else { return }
    let timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.checkPointer() }
    }
    timer.tolerance = 0.015
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  func toggle() {
    panel != nil ? hide() : show()
  }

  func show(on requestedScreen: NSScreen? = nil, fromEdge: Bool = false) {
    guard HistoryDisplayStyle.stored() == .hanging, !captureInteractionIsActive else { return }
    guard let targetScreen = requestedScreen ?? NSScreen.screens.first(where: {
      $0.frame.contains(NSEvent.mouseLocation)
    }) ?? NSScreen.main else { return }
    if isVisible, screen?.frame == targetScreen.frame, isRevealed {
      if !fromEdge {
        panel?.makeKeyAndOrderFront(nil)
      }
      return
    }
    hide(animated: false)
    let frame = HistoryHangingLayout.frame(screenFrame: targetScreen.frame, visibleFrame: targetScreen.visibleFrame,
                                           safeAreaTop: targetScreen.safeAreaInsets.top)
    let cableLayout = HistoryHangingCableLayout(panelFrame: frame, screenFrame: targetScreen.frame)
    let cableWindow = HistoryHangingPanel(contentRect: cableLayout.frame, isCable: true)
    cableWindow.appearance = ThemeManager.shared.nsAppearance
    let cableHosting = NSHostingView(rootView: HistoryHangingCableView(manager: self, layout: cableLayout))
    cableHosting.sizingOptions = []
    cableHosting.frame = CGRect(origin: .zero, size: cableLayout.frame.size)
    cableWindow.contentView = cableHosting
    cablePanel = cableWindow
    let window = HistoryHangingPanel(contentRect: frame)
    window.appearance = ThemeManager.shared.nsAppearance
    window.onEscape = { [weak self] in self?.hide() }
    let hosting = HistoryHangingHostingView(rootView: HistoryHangingView(manager: self, size: frame.size,
                                                                         cableLayout: cableLayout))
    hosting.sizingOptions = []
    hosting.frame = CGRect(origin: .zero, size: frame.size)
    window.contentView = hosting
    panel = window
    screen = targetScreen
    isDismissing = false
    isVisible = true
    startPointerMonitoring()
    awaitingPointer = !fromEdge
    keepOpen = false
    hoverState = HistoryEdgeHoverState()
    presentationID = UUID()
    let id = presentationID
    installEventMonitors()
    cableWindow.orderFrontRegardless()
    if fromEdge {
      window.orderFrontRegardless()
    } else {
      window.makeKeyAndOrderFront(nil)
    }
    DispatchQueue.main.async { [weak self] in
      guard let self, presentationID == id else { return }
      isRevealed = true
    }
  }

  func hide() {
    hide(animated: true)
  }

  func hide(animated: Bool) {
    isSuspendedForCapture = false
    dismissPreview()
    hoverState.dismiss()
    guard let window = panel else { return }
    isDismissing = true
    presentationID = UUID()
    let id = presentationID
    isRevealed = false
    keepOpen = false
    awaitingPointer = false
    removeEventMonitors()
    let delay = animated && isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.5 : 0
    if delay == 0 {
      finishHiding(window)
    } else {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        guard let self, presentationID == id else { return }
        finishHiding(window)
      }
    }
  }

  func toggleKeepOpen() {
    keepOpen.toggle()
    awaitingPointer = false
  }

  func browseAll() {
    hide(animated: false)
    HistoryFloatingManager.shared.showExpanded()
  }

  func open(_ record: CaptureHistoryRecord) {
    hide(animated: false)
    HistoryWindowController.shared.openItem(record)
  }

  func copy(_ record: CaptureHistoryRecord) {
    HistoryWindowController.shared.copyToClipboard([record])
  }

  func preview(_ record: CaptureHistoryRecord, anchor: CGRect) {
    guard isRevealed, !captureInteractionIsActive, NSEvent.pressedMouseButtons == 0,
          let panel, let screen else { return }
    guard hoveredRecordID != record.id else { return }
    hoveredRecordID = record.id
    let screenAnchor = CGRect(x: panel.frame.minX + anchor.minX, y: panel.frame.maxY - anchor.maxY,
                              width: anchor.width, height: anchor.height)
    previewController.request(record, anchor: screenAnchor, shelfFrame: panel.frame, screen: screen)
  }

  func dismissPreview(for recordID: UUID? = nil) {
    guard recordID == nil || recordID == hoveredRecordID else { return }
    hoveredRecordID = nil
    previewController.dismiss()
  }

  func pin(_ record: CaptureHistoryRecord) {
    if let windowID = pinWindowIDs.removeValue(forKey: record.id) {
      QuickAccessPinWindowManager.shared.close(id: windowID)
      pinnedIDs.remove(record.id)
      return
    }
    if let pending = pinTasks.removeValue(forKey: record.id) {
      pending.cancel()
      return
    }
    guard record.captureType == .screenshot, record.fileExists else { return }
    pinTasks[record.id] = Task { [weak self] in
      let thumbnail = await HistoryThumbnailGenerator.shared.loadThumbnailImage(for: record)
      guard let self, !Task.isCancelled else { return }
      pinTasks[record.id] = nil
      guard let thumbnail, record.fileExists else { return }
      let item = QuickAccessItem(url: record.fileURL, thumbnail: thumbnail)
      let shown = QuickAccessPinWindowManager.shared.show(item: item, owner: .history) { [weak self] _ in
        self?.pinWindowIDs[record.id] = nil
        self?.pinnedIDs.remove(record.id)
      }
      if shown {
        pinWindowIDs[record.id] = item.id
        pinnedIDs.insert(record.id)
      }
    }
  }

  private var captureInteractionIsActive: Bool {
    ScreenCaptureManager.shared.isCapturing
      || !CaptureChromeWindowRegistry.shared.windowIDs(
        roles: [.captureOverlay], visibleOnly: true
      ).isEmpty
  }

  private func checkPointer() {
    let point = NSEvent.mouseLocation
    let screens = NSScreen.screens
    let edgeScreen = HistoryHangingLayout.edgeScreenIndex(at: point, frames: screens.map(\.frame)).map { screens[$0] }
    if captureInteractionIsActive {
      if !isSuspendedForCapture {
        if isDismissing {
          hide(animated: false)
        }
        isSuspendedForCapture = true
        dismissPreview()
        removeEventMonitors()
        panel?.orderOut(nil)
        cablePanel?.orderOut(nil)
        isVisible = false
      }
      lastEdgeScreen = edgeScreen
      hoverState.suspend(atEdge: edgeScreen != nil)
      return
    }
    if isSuspendedForCapture {
      isSuspendedForCapture = false
      if let panel, let cablePanel {
        cablePanel.orderFrontRegardless()
        panel.orderFrontRegardless()
        isVisible = true
        installEventMonitors()
      }
    }
    if NSEvent.pressedMouseButtons != 0 || isMenuTracking {
      dismissPreview()
    }
    if let edgeScreen, let screen, edgeScreen.frame != screen.frame, isVisible, !keepOpen {
      hide(animated: false)
      hoverState = HistoryEdgeHoverState()
    }
    if !isVisible, lastEdgeScreen?.frame != edgeScreen?.frame {
      hoverState = HistoryEdgeHoverState()
    }
    lastEdgeScreen = edgeScreen
    let inside: Bool
    if let panel, let screen {
      inside = HistoryHangingLayout.containsPointer(point, panelFrame: panel.frame, screenFrame: screen.frame)
      if panel.frame.contains(point) {
        awaitingPointer = false
      }
    } else {
      inside = false
    }
    let suppressed = NSApp.modalWindow != nil
      || (!isVisible && (!UserDefaults.standard.snapzyHistoryEnabled || isMenuTracking
          || NSEvent.pressedMouseButtons != 0 || HistoryFloatingManager.shared.isTraditionalPanelVisible))
    let action = hoverState.update(
      atEdge: edgeScreen != nil,
      insideShelf: inside,
      visible: isVisible,
      keepOpen: keepOpen || awaitingPointer || isMenuTracking || NSEvent.pressedMouseButtons != 0,
      suppressed: suppressed,
      now: ProcessInfo.processInfo.systemUptime
    )
    switch action {
    case .none: break
    case .reveal:
      show(on: edgeScreen, fromEdge: true)
    case .dismiss:
      if suppressed || isRevealed {
        hide(animated: !suppressed)
      }
    }
  }

  private func finishHiding(_ window: HistoryHangingPanel) {
    if let cablePanel {
      cablePanel.orderOut(nil)
      CaptureChromeWindowRegistry.shared.unregister(cablePanel)
      cablePanel.close()
    }
    cablePanel = nil
    window.orderOut(nil)
    CaptureChromeWindowRegistry.shared.unregister(window)
    window.close()
    panel = nil
    screen = nil
    isVisible = false
    isDismissing = false
    if !isStarted || !UserDefaults.standard.snapzyHistoryEnabled || HistoryDisplayStyle.stored() != .hanging {
      timer?.invalidate()
      timer = nil
    }
  }

  private func installEventMonitors() {
    removeEventMonitors()
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) {
      [weak self] event in
      guard let self else { return event }
      if event.type == .keyDown {
        if event.keyCode == 53, event.window === panel {
          hide()
          return nil
        }
      } else {
        handleOutsideClick()
      }
      return event
    }
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
      Task { @MainActor in self?.handleOutsideClick() }
    }
  }

  private func handleOutsideClick() {
    guard !captureInteractionIsActive, !keepOpen, !isMenuTracking,
          let panel, !panel.frame.contains(NSEvent.mouseLocation) else { return }
    hide()
  }

  private func removeEventMonitors() {
    if let localMonitor {
      NSEvent.removeMonitor(localMonitor)
    }
    if let globalMonitor {
      NSEvent.removeMonitor(globalMonitor)
    }
    localMonitor = nil
    globalMonitor = nil
  }

  private func closeRemovedPins(keeping ids: Set<UUID>) {
    for recordID in Set(pinTasks.keys).subtracting(ids) {
      pinTasks.removeValue(forKey: recordID)?.cancel()
    }
    for recordID in Set(pinWindowIDs.keys).subtracting(ids) {
      if let windowID = pinWindowIDs.removeValue(forKey: recordID) {
        QuickAccessPinWindowManager.shared.close(id: windowID)
      }
      pinnedIDs.remove(recordID)
    }
  }
}

@MainActor
private final class HistoryHangingPanel: NSPanel {
  var onEscape: (() -> Void)?
  private let isCable: Bool

  override var canBecomeKey: Bool {
    !isCable
  }

  override var canBecomeMain: Bool {
    false
  }

  init(contentRect: CGRect, isCable: Bool = false) {
    self.isCable = isCable
    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    isReleasedWhenClosed = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    hidesOnDeactivate = false
    isMovableByWindowBackground = false
    acceptsMouseMovedEvents = !isCable
    ignoresMouseEvents = isCable
    level = isCable ? NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1) : .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    title = isCable ? "Snapzy History Cable" : "Snapzy History"
    identifier = NSUserInterfaceItemIdentifier(isCable ? "SnapzyHistoryCable" : "SnapzyHistoryHanging")
    if isCable {
      setAccessibilityElement(false)
    } else {
      setAccessibilityLabel(L10n.HistoryHanging.shelfTitle)
    }
    CaptureChromeWindowRegistry.configureAppWindow(self)
  }

  override func cancelOperation(_: Any?) {
    onEscape?()
  }
}

@MainActor
private final class HistoryHangingHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
    true
  }
}
