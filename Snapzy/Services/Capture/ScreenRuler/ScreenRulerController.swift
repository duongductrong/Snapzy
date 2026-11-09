//
//  ScreenRulerController.swift
//  Snapzy
//
//  Standalone Measure Screen session: every display is frozen, one overlay per display shows
//  its snapshot, and the pointer measures the space between the edges around it. Measurements
//  can be pinned, copied as text, or saved as a screenshot with the measurements drawn on.
//

import AppKit
import Carbon.HIToolbox
import SnapzyMeasureCore

@MainActor
final class ScreenRulerController {
  static let shared = ScreenRulerController()

  typealias SnapshotProvider = () async throws -> [FrozenDisplaySnapshot]
  /// Saves a rendered display image at the given pixels-per-point scale.
  typealias SaveHandler = (CGImage, CGFloat) -> Void

  private let copyToPasteboard: (String) -> Void
  private let showToast: (String, AppToastStyle) -> Void
  private let setProcessing: (Bool) -> Void
  private let preferences: ScreenRulerPreferences
  private let setsCursorHidden: Bool
  // Not `nonisolated(nonsending)` on purpose: storing a nonsending async closure type
  // generically needs `swift_getExtendedFunctionTypeMetadata` (macOS 15+ runtime), which
  // Release builds call without a fallback -> launch crash on macOS 13/14 (#725).
  private let buildRaster: @MainActor (CGImage) async -> ScreenRulerRaster?

  private var windows: [ScreenRulerOverlayWindow] = []
  private var saveHandler: SaveHandler?
  private weak var activeView: ScreenRulerOverlayView?
  private var rasterDisplayID: CGDirectDisplayID?
  private var localKeyMonitor: Any?
  private var globalKeyMonitor: Any?
  private var observers: [NSObjectProtocol] = []
  private let backgroundCursorControl = BackgroundCursorControl()
  private var cursorHider = LivePassthroughCursorHider()
  private var sessionID = UUID()
  private var axis: ScreenRulerAxis = .both

  /// True from the moment a session is requested — including while the displays are being
  /// frozen — until it is saved or cancelled.
  private(set) var isActive = false

  init(
    copyToPasteboard: ((String) -> Void)? = nil,
    showToast: ((String, AppToastStyle) -> Void)? = nil,
    setProcessing: ((Bool) -> Void)? = nil,
    preferences: ScreenRulerPreferences = ScreenRulerPreferences(),
    setsCursorHidden: Bool = true,
    buildRaster: (@MainActor (CGImage) async -> ScreenRulerRaster?)? = nil
  ) {
    self.copyToPasteboard = copyToPasteboard ?? { value in
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(value, forType: .string)
    }
    self.showToast = showToast ?? { message, style in
      AppToastManager.shared.show(message: message, style: style, duration: 1.5, variant: .compact)
    }
    self.setProcessing = setProcessing ?? { AppStatusBarController.shared.setProcessing($0) }
    self.preferences = preferences
    self.setsCursorHidden = setsCursorHidden
    self.buildRaster = buildRaster ?? { image in
      await Task.detached(priority: .userInitiated) { ScreenRulerRaster(image: image) }.value
    }
  }

  /// Freezes the displays through `snapshots` and opens the overlays. `save` receives the
  /// image when the user saves.
  func start(snapshots: @escaping SnapshotProvider, save: @escaping SaveHandler) {
    guard !isActive else { return }
    isActive = true
    let sessionID = UUID()
    self.sessionID = sessionID
    saveHandler = save
    axis = .both
    setProcessing(true)
    // Up before the freeze finishes, so Esc already cancels while the displays are captured.
    installKeyMonitors()
    DiagnosticLogger.shared.log(.info, .capture, "Measure screen started")

    Task { @MainActor [weak self] in
      let result: Result<[FrozenDisplaySnapshot], Error>
      do {
        result = .success(try await snapshots())
      } catch {
        result = .failure(error)
      }
      guard let self, self.isActive, self.sessionID == sessionID else { return }
      self.setProcessing(false)
      switch result {
      case .success(let snapshots) where !snapshots.isEmpty:
        self.presentOverlays(snapshots)
      case .success:
        self.fail(nil)
      case .failure(let error):
        self.fail(error)
      }
    }
  }

  func cancel() {
    guard isActive else { return }
    finish()
    DiagnosticLogger.shared.log(.info, .capture, "Measure screen cancelled")
  }

  // MARK: - Session

  private func presentOverlays(_ snapshots: [FrozenDisplaySnapshot]) {
    let byDisplay = Dictionary(snapshots.map { ($0.displayID, $0) }, uniquingKeysWith: { first, _ in first })
    let unit = preferences.unit
    let tolerance = preferences.edgeTolerance
    windows = NSScreen.screens.compactMap { screen in
      guard let displayID = screen.displayID, let snapshot = byDisplay[displayID] else { return nil }
      let window = ScreenRulerOverlayWindow(screen: screen, snapshot: snapshot)
      let view = window.overlayView
      view.delegate = self
      view.unit = unit
      view.tolerance = tolerance
      view.hint = L10n.ScreenCapture.screenRulerHint
      return window
    }
    guard !windows.isEmpty else {
      fail(nil)
      return
    }

    let mouseLocation = NSEvent.mouseLocation
    let keyWindow = windows.first { $0.frame.contains(mouseLocation) } ?? windows.first
    for window in windows {
      window.orderFrontRegardless()
    }
    keyWindow?.makeKey()
    keyWindow.map { _ = $0.makeFirstResponder($0.overlayView) }
    installSessionObservers()
    hideCursor()
    keyWindow?.overlayView.trackPointer(atScreenPoint: mouseLocation)
  }

  /// Keeps pixels only for the display under the pointer: a 5K raster is ~59 MB.
  private func loadRaster(for view: ScreenRulerOverlayView) {
    guard let window = windows.first(where: { $0.overlayView === view }),
          rasterDisplayID != window.displayID else { return }
    if let previousID = rasterDisplayID {
      windows.first { $0.displayID == previousID }?.overlayView.raster = nil
    }
    rasterDisplayID = window.displayID
    let displayID = window.displayID
    let sessionID = sessionID
    let image = view.snapshot.image

    Task { @MainActor [weak self] in
      let raster = await self?.buildRaster(image)
      guard let self, self.isActive, self.sessionID == sessionID,
            self.rasterDisplayID == displayID else { return }
      guard let raster else {
        self.fail(nil)
        return
      }
      self.windows.first { $0.displayID == displayID }?.overlayView.raster = raster
    }
  }

  private func fail(_ error: Error?) {
    DiagnosticLogger.shared.log(.warning, .capture, "Measure screen failed", context: [
      "error": error?.localizedDescription ?? "no displays",
    ])
    finish()
    showToast(L10n.ScreenCapture.screenRulerUnavailable, .error)
  }

  private func finish() {
    if isActive {
      setProcessing(false)
    }
    isActive = false
    sessionID = UUID()
    saveHandler = nil
    rasterDisplayID = nil
    removeMonitors()
    for window in windows {
      window.overlayView.delegate = nil
      window.overlayView.raster = nil
      window.orderOut(nil)
      window.close()
    }
    windows.removeAll()
    showCursor()
  }

  // MARK: - Actions

  private func setAxis(_ requested: ScreenRulerAxis) {
    axis = axis == requested ? .both : requested
    for window in windows {
      window.overlayView.axis = axis
    }
  }

  private func toggleUnit() {
    let unit = preferences.unit.toggled
    preferences.unit = unit
    for window in windows {
      window.overlayView.unit = unit
    }
  }

  private static let toleranceStep = 2

  /// `[` / `]`: how different a pixel must be to count as an edge. Remembered for next time.
  private func adjustTolerance(by delta: Int) {
    let range = ScreenRulerEdgeScanner.toleranceRange
    let tolerance = min(max(preferences.edgeTolerance + delta, range.lowerBound), range.upperBound)
    preferences.edgeTolerance = tolerance
    for window in windows {
      window.overlayView.tolerance = tolerance
    }
    activeOverlayView()?.showFeedback(L10n.ScreenCapture.screenRulerTolerance(tolerance))
  }

  private func copyCurrent() {
    guard let view = activeOverlayView(), let measurement = view.currentMeasurement else { return }
    let text = ScreenRulerFormatter.copyText(for: measurement, scaleX: view.scaleX, scaleY: view.scaleY, unit: view.unit)
    copyToPasteboard(text)
    view.showFeedback(L10n.ScreenCapture.screenRulerCopied(text))
    DiagnosticLogger.shared.log(.info, .capture, "Measure screen copied")
  }

  /// Ends the session and hands the active display's snapshot, with its measurements drawn
  /// on, to the save handler. If rendering fails the session stays open, so nothing is lost.
  private func saveCurrent() {
    guard let view = activeOverlayView(), let saveHandler else { return }
    guard let image = ScreenRulerRenderer.renderImage(view.snapshot.image, drawing: view.drawing(forExport: true)) else {
      DiagnosticLogger.shared.log(.warning, .capture, "Measure screen render failed")
      view.showFeedback(L10n.ScreenCapture.screenRulerUnavailable)
      return
    }
    let scale = view.snapshot.pixelScaleFactor
    finish()
    DiagnosticLogger.shared.log(.info, .capture, "Measure screen saved")
    saveHandler(image, scale)
  }

  // MARK: - Cursor

  /// The reticle stands in for the cursor so it never covers the measured pixel.
  private func hideCursor() {
    guard setsCursorHidden, !cursorHider.isHidden else { return }
    backgroundCursorControl.enableOnce()
    cursorHider.hide(displayIDs: Set(NSScreen.screens.compactMap(\.displayID)))
  }

  private func showCursor() {
    guard setsCursorHidden else { return }
    cursorHider.showAll()
  }

  // MARK: - Input

  private func installKeyMonitors() {
    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return event }
      return self.handleKeyDown(event) ? nil : event
    }
    // Fallback in case another app takes key focus while the overlay is up.
    globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == UInt16(kVK_Escape) else { return }
      Task { @MainActor in self?.cancel() }
    }
  }

  /// Installed once the overlays are up: activation changes while the displays are still
  /// being frozen (e.g. the app that was frontmost settling) must not cancel the session.
  private func installSessionObservers() {
    let workspaceCenter = NSWorkspace.shared.notificationCenter
    observers.append(workspaceCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.cancel() }
    })
    observers.append(NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.cancel() }
    })
  }

  private func removeMonitors() {
    if let localKeyMonitor {
      NSEvent.removeMonitor(localKeyMonitor)
      self.localKeyMonitor = nil
    }
    if let globalKeyMonitor {
      NSEvent.removeMonitor(globalKeyMonitor)
      self.globalKeyMonitor = nil
    }
    for observer in observers {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      NotificationCenter.default.removeObserver(observer)
    }
    observers.removeAll()
  }

  /// Esc cancels; H/V lock an axis; U switches pt/px; [ / ] change the edge tolerance;
  /// C or ⌘C copies; Return saves;
  /// Delete or ⌘Z removes the last pin; arrows move one pixel (ten with ⇧).
  func handleKeyDown(_ event: NSEvent) -> Bool {
    guard isActive else { return false }
    if event.keyCode == UInt16(kVK_Escape) {
      cancel()
      return true
    }
    // Everything else needs the overlays, which appear once the displays are frozen.
    guard !windows.isEmpty else { return false }
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function])
    switch Int(event.keyCode) {
    case kVK_ANSI_H where modifiers.isEmpty:
      setAxis(.horizontal)
      return true
    case kVK_ANSI_V where modifiers.isEmpty:
      setAxis(.vertical)
      return true
    case kVK_ANSI_U where modifiers.isEmpty:
      toggleUnit()
      return true
    case kVK_ANSI_LeftBracket where modifiers.isEmpty:
      adjustTolerance(by: -Self.toleranceStep)
      return true
    case kVK_ANSI_RightBracket where modifiers.isEmpty:
      adjustTolerance(by: Self.toleranceStep)
      return true
    case kVK_ANSI_C where modifiers.isEmpty || modifiers == .command:
      copyCurrent()
      return true
    case kVK_Return, kVK_ANSI_KeypadEnter:
      guard modifiers.isEmpty else { return false }
      saveCurrent()
      return true
    case kVK_Delete, kVK_ForwardDelete:
      guard modifiers.isEmpty else { return false }
      activeOverlayView()?.removeLastPin()
      return true
    case kVK_ANSI_Z where modifiers == .command:
      activeOverlayView()?.removeLastPin()
      return true
    case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
      guard modifiers.isEmpty || modifiers == .shift else { return false }
      let step = modifiers == .shift ? 10 : 1
      let (dx, dy): (Int, Int) = switch Int(event.keyCode) {
      case kVK_LeftArrow: (-step, 0)
      case kVK_RightArrow: (step, 0)
      case kVK_UpArrow: (0, -step)
      default: (0, step)
      }
      activeOverlayView()?.nudge(dx: dx, dy: dy)
      return true
    default:
      return false
    }
  }

  /// The display being measured: the last one that tracked the pointer, else the one under it.
  private func activeOverlayView() -> ScreenRulerOverlayView? {
    if let activeView, windows.contains(where: { $0.overlayView === activeView }) {
      return activeView
    }
    let mouseLocation = NSEvent.mouseLocation
    return windows.first(where: { $0.frame.contains(mouseLocation) })?.overlayView
  }
}

extension ScreenRulerController: ScreenRulerOverlayViewDelegate {
  func screenRulerOverlayViewDidReceivePointer(_ view: ScreenRulerOverlayView) {
    if activeView !== view {
      activeView = view
      for window in windows where window.overlayView !== view {
        window.overlayView.pointerLeft()
      }
    }
    loadRaster(for: view)
  }

  func screenRulerOverlayViewDidCancel(_ view: ScreenRulerOverlayView) {
    cancel()
  }
}

#if DEBUG
extension ScreenRulerController {
  var testWindows: [ScreenRulerOverlayWindow] { windows }
}
#endif
