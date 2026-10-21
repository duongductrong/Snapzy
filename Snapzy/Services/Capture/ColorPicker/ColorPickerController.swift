//
//  ColorPickerController.swift
//  Snapzy
//
//  Standalone Pick Color session: see-through overlays keep the screen live, the display
//  under the pointer is streamed for the loupe, and the picked pixel's sRGB hex value is
//  copied without taking a screenshot; a result window then offers the other formats.
//

import AppKit
import Carbon.HIToolbox

@MainActor
final class ColorPickerController {
  static let shared = ColorPickerController()

  private let makeCapture: () -> ColorPickerCapturing
  private let copyToPasteboard: (String) -> Void
  private let showToast: (String, AppToastStyle) -> Void
  private let presentResult: (ColorPickerColor, ColorPickerFormat, CGPoint) -> Void
  private let preferences: ColorPickerPreferences
  private let setsCursorHidden: Bool

  private var windows: [ColorPickerOverlayWindow] = []
  private var capture: ColorPickerCapturing?
  private var sources: [CGDirectDisplayID: ColorPickerPixelSource] = [:]
  private var streamingDisplayID: CGDirectDisplayID?
  private weak var activeView: ColorPickerOverlayView?
  private var localKeyMonitor: Any?
  private var globalKeyMonitor: Any?
  private var observers: [NSObjectProtocol] = []
  private let backgroundCursorControl = BackgroundCursorControl()
  private var cursorHider = LivePassthroughCursorHider()
  private var sessionID = UUID()

  /// True from the moment a session is requested — including while capture is starting —
  /// until it is committed or cancelled.
  private(set) var isActive = false

  init(
    makeCapture: (() -> ColorPickerCapturing)? = nil,
    copyToPasteboard: ((String) -> Void)? = nil,
    showToast: ((String, AppToastStyle) -> Void)? = nil,
    presentResult: ((ColorPickerColor, ColorPickerFormat, CGPoint) -> Void)? = nil,
    preferences: ColorPickerPreferences = ColorPickerPreferences(),
    setsCursorHidden: Bool = true
  ) {
    let copy = copyToPasteboard ?? { value in
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(value, forType: .string)
    }
    self.makeCapture = makeCapture ?? { ColorPickerScreenCapture() }
    self.copyToPasteboard = copy
    self.showToast = showToast ?? { message, style in
      AppToastManager.shared.show(message: message, style: style, duration: 1.5, variant: .compact)
    }
    self.preferences = preferences
    if let presentResult {
      self.presentResult = presentResult
    } else {
      let resultWindow = ColorPickerResultWindowController(
        copyToPasteboard: copy,
        onPickAgain: { ColorPickerController.shared.start() },
        preferences: preferences
      )
      self.presentResult = { color, format, point in
        resultWindow.show(color: color, copiedFormat: format, near: point)
      }
    }
    self.setsCursorHidden = setsCursorHidden
  }

  /// The global shortcut toggles: pressing it again while picking cancels.
  func toggle() {
    if isActive {
      cancel()
    } else {
      start()
    }
  }

  func start() {
    guard !isActive else { return }
    isActive = true
    let sessionID = UUID()
    self.sessionID = sessionID
    DiagnosticLogger.shared.log(.info, .capture, "Pick color started")

    // The overlays go up at once; they are see-through, so nothing on screen changes until
    // the loupe has live pixels to show.
    presentOverlays()
    let capture = makeCapture()
    self.capture = capture
    let windowNumbers = windows.map(\.windowNumber)

    Task { @MainActor [weak self] in
      do {
        try await capture.prepare(excludingWindowNumbers: windowNumbers)
      } catch {
        guard let self, self.isActive, self.sessionID == sessionID else { return }
        self.fail(error)
        return
      }
      guard let self, self.isActive, self.sessionID == sessionID else { return }
      for window in self.windows {
        guard let displayID = window.displayID, let screen = window.screen,
              let source = capture.source(for: screen) else { continue }
        self.sources[displayID] = source
      }
      guard !self.sources.isEmpty else {
        self.fail(nil)
        return
      }
      self.streamDisplay(under: NSEvent.mouseLocation)
    }
  }

  func cancel() {
    guard isActive else { return }
    finish()
    DiagnosticLogger.shared.log(.info, .capture, "Pick color cancelled")
  }

  // MARK: - Session

  private func presentOverlays() {
    windows = NSScreen.screens.map { screen in
      let window = ColorPickerOverlayWindow(screen: screen)
      window.overlayView.delegate = self
      return window
    }
    let mouseLocation = NSEvent.mouseLocation
    let keyWindow = windows.first { $0.frame.contains(mouseLocation) } ?? windows.first
    for window in windows {
      window.orderFrontRegardless()
    }
    // Non-activating panels take key input without activating Snapzy.
    keyWindow?.makeKey()
    keyWindow.map { _ = $0.makeFirstResponder($0.overlayView) }
    keyWindow?.overlayView.trackPointer(atScreenPoint: mouseLocation)
    installMonitors()
  }

  /// Streams only the display under the pointer: one native-resolution stream at a time.
  private func streamDisplay(under screenPoint: CGPoint) {
    guard let window = windows.first(where: { $0.frame.contains(screenPoint) }) ?? windows.first,
          let displayID = window.displayID else { return }
    streamDisplay(displayID)
  }

  private func streamDisplay(_ displayID: CGDirectDisplayID) {
    guard isActive, streamingDisplayID != displayID, let source = sources[displayID] else { return }
    if let previousID = streamingDisplayID {
      sources[previousID]?.stop()
      view(for: previousID)?.pixelSource = nil
    }
    streamingDisplayID = displayID
    let sessionID = sessionID

    Task { @MainActor [weak self] in
      do {
        try await source.start()
      } catch {
        guard let self, self.isActive, self.sessionID == sessionID else { return }
        self.fail(error)
        return
      }
      guard let self, self.isActive, self.sessionID == sessionID,
            self.streamingDisplayID == displayID else { return }
      self.view(for: displayID)?.pixelSource = source
      self.hideCursor()
      DiagnosticLogger.shared.log(.info, .capture, "Pick color streaming", context: ["displayID": "\(displayID)"])
    }
  }

  private func view(for displayID: CGDirectDisplayID) -> ColorPickerOverlayView? {
    windows.first { $0.displayID == displayID }?.overlayView
  }

  /// Copies the color right away in the user's chosen notation (HEX by default), so the common
  /// case needs no further click, then shows the result window next to the picked point.
  private func commit(_ color: ColorPickerColor) {
    guard isActive else { return }
    let pickedPoint = NSEvent.mouseLocation
    let format = preferences.copyFormat
    finish()
    copyToPasteboard(format.string(for: color))
    presentResult(color, format, pickedPoint)
    DiagnosticLogger.shared.log(.info, .capture, "Pick color copied")
  }

  private func fail(_ error: Error?) {
    DiagnosticLogger.shared.log(.warning, .capture, "Pick color capture failed", context: [
      "error": error?.localizedDescription ?? "no displays",
    ])
    finish()
    showToast(L10n.ScreenCapture.colorPickerUnavailable, .error)
  }

  private func finish() {
    isActive = false
    sessionID = UUID()
    removeMonitors()
    for source in sources.values {
      source.stop()
    }
    sources.removeAll()
    streamingDisplayID = nil
    capture = nil
    for window in windows {
      window.overlayView.delegate = nil
      window.overlayView.pixelSource = nil
      window.orderOut(nil)
      window.close()
    }
    windows.removeAll()
    showCursor()
  }

  // MARK: - Cursor

  /// The loupe is the cursor. Snapzy stays inactive, so background cursor control is what lets
  /// the hide take effect (the same mechanism live area capture uses).
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

  private func installMonitors() {
    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return event }
      return self.handleKeyDown(event) ? nil : event
    }
    // Fallback in case another app takes key focus while the overlay is up.
    globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == UInt16(kVK_Escape) else { return }
      Task { @MainActor in self?.cancel() }
    }
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

  /// Esc cancels; C and Return copy the color the loupe shows; arrow keys move the loupe one
  /// pixel (ten with ⇧).
  private func handleKeyDown(_ event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function])
    let step = modifiers == .shift ? 10 : 1
    switch Int(event.keyCode) {
    case kVK_Escape:
      cancel()
      return true
    case kVK_ANSI_C, kVK_Return, kVK_ANSI_KeypadEnter:
      guard modifiers.isEmpty else { return false }
      if let color = activeOverlayView()?.currentColor {
        commit(color)
      }
      return true
    case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
      guard modifiers.isEmpty || modifiers == .shift else { return false }
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

  /// The display the loupe is on: the last one that tracked the pointer, else the one under it.
  private func activeOverlayView() -> ColorPickerOverlayView? {
    if let activeView, windows.contains(where: { $0.overlayView === activeView }) {
      return activeView
    }
    let mouseLocation = NSEvent.mouseLocation
    return windows.first(where: { $0.frame.contains(mouseLocation) })?.overlayView
  }
}

extension ColorPickerController: ColorPickerOverlayViewDelegate {
  func colorPickerOverlayView(_ view: ColorPickerOverlayView, didPick color: ColorPickerColor) {
    commit(color)
  }

  func colorPickerOverlayViewDidCancel(_ view: ColorPickerOverlayView) {
    cancel()
  }

  func colorPickerOverlayViewDidReceivePointer(_ view: ColorPickerOverlayView) {
    guard activeView !== view else { return }
    activeView = view
    for window in windows where window.overlayView !== view {
      window.overlayView.hideLoupe()
    }
    if let displayID = windows.first(where: { $0.overlayView === view })?.displayID {
      streamDisplay(displayID)
    }
  }
}

#if DEBUG
extension ColorPickerController {
  var testWindows: [ColorPickerOverlayWindow] { windows }
  var testStreamingDisplayID: CGDirectDisplayID? { streamingDisplayID }
}
#endif
