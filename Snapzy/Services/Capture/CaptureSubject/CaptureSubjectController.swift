//
//  CaptureSubjectController.swift
//  Snapzy
//
//  PixelSnap-style Capture Subject session: drag an area, snap to the
//  object, lock a preview, then capture when the camera button is clicked.
//

import AppKit
import Carbon.HIToolbox

@MainActor
final class CaptureSubjectController: NSObject {
  static let shared = CaptureSubjectController()

  private let capturePerformer: CaptureSubjectCapturePerforming
  private let previewCapturer: CaptureSubjectPreviewCapturing
  private let windowFactory: (NSScreen) -> CaptureSubjectOverlayWindowProviding

  private var windows: [CGDirectDisplayID: CaptureSubjectOverlayWindowProviding] = [:]
  private var screenChangeObserver: NSObjectProtocol?
  private var localKeyMonitor: Any?
  private var globalKeyMonitor: Any?
  private var previouslyActiveApplication: NSRunningApplication?
  private var sourceContext: CaptureContext?
  private var isActive = false
  private var isCommitting = false
  private var lockedPreview: CaptureSubjectSnappedPreview?
  private var dragOrigin: CGPoint?
  private var isDragging = false

  private static let dragThreshold: CGFloat = 4

  var isSessionActive: Bool { isActive }

  init(
    capturePerformer: CaptureSubjectCapturePerforming? = nil,
    previewCapturer: CaptureSubjectPreviewCapturing? = nil,
    windowFactory: ((NSScreen) -> CaptureSubjectOverlayWindowProviding)? = nil
  ) {
    self.capturePerformer = capturePerformer ?? CaptureSubjectPerformer()
    self.previewCapturer = previewCapturer ?? CaptureSubjectPreviewCapturer()
    self.windowFactory = windowFactory ?? { CaptureSubjectOverlayWindow(screen: $0) }
    super.init()
  }

  func startCapture() {
    guard !isActive else { return }

    isActive = true
    isCommitting = false
    lockedPreview = nil
    dragOrigin = nil
    isDragging = false
    previouslyActiveApplication = NSWorkspace.shared.frontmostApplication
    sourceContext = CaptureContext.fromFrontmostApp()
    buildWindowPool()
    observeScreenChanges()
    installEscapeMonitors()
    showWindows()
    NSCursor.vectorScreenshotCrosshairHighContrast.set()

    DiagnosticLogger.shared.log(
      .info,
      .capture,
      "Capture subject started",
      context: ["screenCount": "\(windows.count)"]
    )
  }

  func cancel() {
    guard isActive else { return }
    dismiss()
    restorePreviousApplication()
    DiagnosticLogger.shared.log(.info, .capture, "Capture subject cancelled")
  }

  private func buildWindowPool() {
    for screen in NSScreen.screens {
      guard let displayID = screen.displayID else { continue }
      let window = windowFactory(screen)
      window.eventDelegate = self
      window.setFrame(screen.frame, display: true)
      window.updateBounds(screen.frame)
      windows[displayID] = window
    }
  }

  private func showWindows() {
    let cursor = NSEvent.mouseLocation
    let keyboardDisplayID = NSScreen.screens.first(where: { $0.frame.contains(cursor) })?.displayID
      ?? NSScreen.main?.displayID

    for (displayID, window) in windows {
      window.updatePreview(nil)
      window.updateDragRect(nil)
      window.orderFrontRegardless()
      if displayID == keyboardDisplayID {
        window.makeKey()
        _ = window.makeFirstResponder(nil)
      }
    }
  }

  private func routeDragRect(_ rect: CGRect?) {
    for window in windows.values {
      window.updateDragRect(rect)
    }
  }

  private func routePreview(_ preview: CaptureSubjectSnappedPreview?) {
    for window in windows.values {
      window.updateDragRect(nil)
      window.updatePreview(preview)
    }
  }

  private func observeScreenChanges() {
    screenChangeObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refreshWindowPool()
      }
    }
  }

  private func refreshWindowPool() {
    guard isActive else { return }
    let currentDisplayIDs = Set(NSScreen.screens.compactMap(\.displayID))
    for displayID in Set(windows.keys).subtracting(currentDisplayIDs) {
      windows[displayID]?.close()
      windows.removeValue(forKey: displayID)
    }

    for screen in NSScreen.screens {
      guard let displayID = screen.displayID else { continue }
      let window = windows[displayID] ?? windowFactory(screen)
      window.eventDelegate = self
      window.setFrame(screen.frame, display: true)
      window.updateBounds(screen.frame)
      window.orderFrontRegardless()
      windows[displayID] = window
    }
    routePreview(lockedPreview)
  }

  private func installEscapeMonitors() {
    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == UInt16(kVK_Escape) else { return event }
      Task { @MainActor in self?.handleEscape() }
      return nil
    }
    globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == UInt16(kVK_Escape) else { return }
      Task { @MainActor in self?.handleEscape() }
    }
  }

  private func handleEscape() {
    if lockedPreview != nil {
      unlockPreview()
      return
    }
    cancel()
  }

  private func lockPreview(for rect: CGRect) {
    guard isActive, !isCommitting else { return }
    let integral = rect.integral
    guard integral.width >= 1, integral.height >= 1 else { return }

    let preview = makeSnappedPreview(for: integral, context: sourceContext)
    lockedPreview = preview
    isDragging = false
    dragOrigin = nil
    routePreview(preview)

    DiagnosticLogger.shared.log(
      .info,
      .capture,
      "Capture subject preview locked",
      context: [
        "width": "\(Int(preview.rect.width.rounded()))",
        "height": "\(Int(preview.rect.height.rounded()))",
        "hasImage": "\(preview.image != nil)",
      ]
    )
  }

  private func makeSnappedPreview(
    for rect: CGRect,
    context: CaptureContext?
  ) -> CaptureSubjectSnappedPreview {
    let padded = rect.insetBy(dx: -CaptureSubjectSnapper.snapPadding, dy: -CaptureSubjectSnapper.snapPadding)
    let captureRect = CGRect(
      x: min(padded.minX, rect.minX),
      y: min(padded.minY, rect.minY),
      width: max(padded.width, rect.width),
      height: max(padded.height, rect.height)
    )

    let sessionWindows = Array(windows.values)
    let keyboardWindow = sessionWindows.first { $0.frame.contains(NSEvent.mouseLocation) }
    sessionWindows.forEach { $0.orderOut(nil) }
    let captured = previewCapturer.capturePreview(of: captureRect)
    sessionWindows.forEach { $0.orderFrontRegardless() }
    keyboardWindow?.makeKey()
    _ = keyboardWindow?.makeFirstResponder(nil)
    NSCursor.vectorScreenshotCrosshairHighContrast.set()

    guard let captured else {
      return CaptureSubjectSnappedPreview(
        rect: rect,
        image: nil,
        pixelSize: rect.size,
        displayID: 0,
        selectionContext: context
      )
    }

    let snapped = CaptureSubjectSnapper.snap(
      selectionRect: rect,
      in: captured.image,
      capturedScreenRect: captured.rect
    )
    return CaptureSubjectSnappedPreview(
      rect: snapped.screenRect,
      image: snapped.image,
      pixelSize: snapped.pixelSize,
      displayID: captured.displayID,
      selectionContext: context
    )
  }

  private func unlockPreview() {
    lockedPreview = nil
    for window in windows.values {
      window.updatePreview(nil)
      window.updateDragRect(nil)
    }
    NSCursor.vectorScreenshotCrosshairHighContrast.set()
  }

  private func commit(_ preview: CaptureSubjectSnappedPreview) {
    guard isActive, !isCommitting else { return }
    isCommitting = true
    dismiss()
    Task { @MainActor in
      await capturePerformer.captureSubject(preview: preview)
      restorePreviousApplication()
    }
  }

  private func dismiss() {
    lockedPreview = nil
    dragOrigin = nil
    isDragging = false
    for window in windows.values {
      window.updatePreview(nil)
      window.updateDragRect(nil)
      window.orderOut(nil)
      window.close()
      window.eventDelegate = nil
    }
    windows.removeAll()
    removeEscapeMonitors()
    if let screenChangeObserver {
      NotificationCenter.default.removeObserver(screenChangeObserver)
      self.screenChangeObserver = nil
    }
    isActive = false
    sourceContext = nil
    NSCursor.arrow.set()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
      guard self?.isActive == false else { return }
      NSCursor.arrow.set()
    }
  }

  private func removeEscapeMonitors() {
    if let localKeyMonitor {
      NSEvent.removeMonitor(localKeyMonitor)
      self.localKeyMonitor = nil
    }
    if let globalKeyMonitor {
      NSEvent.removeMonitor(globalKeyMonitor)
      self.globalKeyMonitor = nil
    }
  }

  private func restorePreviousApplication() {
    previouslyActiveApplication?.activate(options: [])
    previouslyActiveApplication = nil
  }

  static func rect(from origin: CGPoint, to point: CGPoint) -> CGRect {
    CGRect(
      x: min(origin.x, point.x),
      y: min(origin.y, point.y),
      width: abs(point.x - origin.x),
      height: abs(point.y - origin.y)
    )
  }
}

extension CaptureSubjectController: CaptureSubjectOverlayWindowDelegate {
  func captureSubjectOverlayWindow(_ window: CaptureSubjectOverlayWindowProviding, mouseMovedAt point: CGPoint) {
    window.setPointer(point)
  }

  func captureSubjectOverlayWindow(_ window: CaptureSubjectOverlayWindowProviding, mouseDownAt point: CGPoint) {
    if let preview = lockedPreview {
      if window.isCameraHovered {
        commit(preview)
        return
      }
      if preview.rect.contains(point) {
        return
      }
      unlockPreview()
      return
    }
    dragOrigin = point
    isDragging = false
  }

  func captureSubjectOverlayWindowDidRequestCapture(_ window: CaptureSubjectOverlayWindowProviding) {
    guard let preview = lockedPreview else { return }
    commit(preview)
  }

  func captureSubjectOverlayWindow(_ window: CaptureSubjectOverlayWindowProviding, mouseDraggedAt point: CGPoint) {
    guard lockedPreview == nil, let origin = dragOrigin else { return }
    let distance = hypot(point.x - origin.x, point.y - origin.y)
    if !isDragging, distance >= Self.dragThreshold {
      isDragging = true
    }
    guard isDragging else { return }
    routeDragRect(Self.rect(from: origin, to: point))
  }

  func captureSubjectOverlayWindow(_ window: CaptureSubjectOverlayWindowProviding, mouseUpAt point: CGPoint) {
    guard isActive, lockedPreview == nil else { return }
    if isDragging, let origin = dragOrigin {
      let rect = Self.rect(from: origin, to: point)
      if rect.width >= 1, rect.height >= 1 {
        lockPreview(for: rect)
        return
      }
    }
    isDragging = false
    dragOrigin = nil
    routeDragRect(nil)
  }

  func captureSubjectOverlayWindowDidCancel(_ window: CaptureSubjectOverlayWindowProviding) {
    handleEscape()
  }
}
