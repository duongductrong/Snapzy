//
//  InlineAreaAnnotateSession.swift
//  Snapzy
//
//  Coordinates direct area screenshot annotation before post-capture routing.
//

import AppKit
import Combine
import CoreGraphics
import Foundation

struct InlineAreaAnnotateDisplay: Identifiable {
  let displayID: CGDirectDisplayID
  let screenFrame: CGRect
  let localFrame: CGRect
  let controlInsets: InlineAreaControlInsets
  let backdropImage: NSImage

  var id: CGDirectDisplayID { displayID }
}

enum InlineAreaAnnotatePhase {
  case selecting
  case annotating
}

enum InlineAreaKeyEventSource {
  case local
  case global
}

enum InlineAreaKeyAction: Equatable {
  case passThrough
  case cancel
  case finish
  case copyCurrentImage
  case setMoveModifierActive(Bool)
  case resetMoveModifierAndPassThrough
}

@MainActor
final class InlineAreaAnnotateSession: ObservableObject {
  private struct InlineAreaCrop {
    let image: NSImage
    let localRect: CGRect
  }

  @Published var phase: InlineAreaAnnotatePhase = .selecting
  @Published var selectionRect: CGRect?
  @Published var isMoveModifierActive = false

  let state: AnnotateState
  let desktopFrame: CGRect
  let displays: [InlineAreaAnnotateDisplay]

  private let primaryDisplayID: CGDirectDisplayID
  private let screenFramesByDisplayID: [CGDirectDisplayID: CGRect]
  private let frozenSession: FrozenAreaCaptureSession
  private let saveDirectory: URL
  private let outputFormat: ImageFormat
  private let defaults: UserDefaults
  private let context: CaptureContext
  private let onComplete: (CaptureResult) -> Void
  private let windows = NSHashTable<NSWindow>.weakObjects()
  private var localKeyMonitor: Any?
  private var globalKeyMonitor: Any?
  private var selectionLocalMonitor: Any?
  private var selectionStartPoint: CGPoint?
  private var stateChangeCancellable: AnyCancellable?
  private var didComplete = false

  init(
    primaryDisplayID: CGDirectDisplayID,
    desktopFrame: CGRect,
    displays: [InlineAreaAnnotateDisplay],
    frozenSession: FrozenAreaCaptureSession,
    saveDirectory: URL,
    outputFormat: ImageFormat,
    defaults: UserDefaults = .standard,
    context: CaptureContext = .empty,
    onComplete: @escaping (CaptureResult) -> Void
  ) {
    self.primaryDisplayID = primaryDisplayID
    self.desktopFrame = desktopFrame
    self.displays = displays
    self.screenFramesByDisplayID = Dictionary(uniqueKeysWithValues: displays.map {
      ($0.displayID, $0.screenFrame)
    })
    self.frozenSession = frozenSession
    self.saveDirectory = saveDirectory
    self.outputFormat = outputFormat
    self.defaults = defaults
    self.context = context
    self.onComplete = onComplete
    self.state = AnnotateState(
      defaults: defaults,
      appliesDefaultCanvasPresetOnNewImages: false
    )
    self.state.onToolActivated = { tool in
      AnnotateToolPreference.remember(tool, userDefaults: defaults)
    }
    self.stateChangeCancellable = state.objectWillChange.sink { [weak self] _ in
      Task { @MainActor in
        self?.objectWillChange.send()
      }
    }
  }

  func attach(window: NSWindow) {
    windows.add(window)
    if localKeyMonitor == nil, globalKeyMonitor == nil {
      installKeyMonitors()
    }
  }

  func refreshCursor() {
    if phase == .selecting {
      NSCursor.vectorScreenshotCrosshairLight.set()
    }
    for window in windows.allObjects {
      if let hostingView = window.contentView {
        window.invalidateCursorRects(for: hostingView)
      }
    }
  }

  func beginSelection(at localPoint: CGPoint) {
    guard phase == .selecting else { return }
    guard selectionStartPoint == nil else { return }
    selectionStartPoint = localPoint
    installSelectionMonitorIfNeeded()
    updateSelection(to: localPoint)
  }

  func updateSelection(to localPoint: CGPoint) {
    guard phase == .selecting, let start = selectionStartPoint else { return }
    selectionRect = clampedSelectionRect(CGRect(
      x: min(start.x, localPoint.x),
      y: min(start.y, localPoint.y),
      width: abs(localPoint.x - start.x),
      height: abs(localPoint.y - start.y)
    ).standardized)
  }

  func endSelection(at localPoint: CGPoint) {
    guard phase == .selecting, selectionStartPoint != nil else { return }
    updateSelection(to: localPoint)
    removeSelectionMonitor()
    selectionStartPoint = nil

    guard let rect = selectionRect, rect.width > 5, rect.height > 5 else {
      selectionRect = nil
      return
    }
    beginAnnotating(with: rect)
  }

  func beginAnnotating(with localRect: CGRect) {
    let clampedRect = clampedSelectionRect(localRect.standardized)
    guard clampedRect.width > 5, clampedRect.height > 5,
          let crop = cropImage(for: clampedRect) else { return }

    selectionRect = crop.localRect
    state.loadImage(crop.image, url: nil)
    state.selectedTool = AnnotateToolPreference.initialTool(userDefaults: defaults)
    phase = .annotating
  }

  func moveSelection(to localRect: CGRect, refreshImage: Bool) {
    let clampedRect = clampedSelectionRect(localRect.standardized)
    guard refreshImage else {
      selectionRect = clampedRect
      return
    }
    guard let crop = cropImage(for: clampedRect) else { return }
    selectionRect = crop.localRect
    state.replaceSourceImagePreservingAnnotations(crop.image)
  }

  func resizeSelection(to localRect: CGRect, previousRect: CGRect) {
    let clampedRect = clampedSelectionRect(localRect.standardized)
    guard clampedRect.width > 5,
          clampedRect.height > 5,
          let crop = cropImage(for: clampedRect) else { return }

    let standardizedPreviousRect = previousRect.standardized
    let annotationOffset = CGPoint(
      x: standardizedPreviousRect.minX - crop.localRect.minX,
      y: standardizedPreviousRect.minY - crop.localRect.minY
    )

    selectionRect = crop.localRect
    state.replaceSourceImagePreservingAnnotations(crop.image, annotationOffset: annotationOffset)
  }

  func clampedSelectionPreview(for localRect: CGRect) -> CGRect {
    clampedSelectionRect(localRect.standardized)
  }

  func handleKeyEvent(_ event: NSEvent, source: InlineAreaKeyEventSource = .local) -> Bool {
    let action = Self.keyAction(
      for: event,
      source: source,
      phase: phase,
      hasTextResponder: windows.allObjects.contains { $0.firstResponder is NSTextView },
      hasKeyWindow: windows.allObjects.contains { $0.isKeyWindow }
    )

    if phase != .annotating {
      isMoveModifierActive = false
    }

    switch action {
    case .passThrough:
      return false
    case .cancel:
      cancel()
      return true
    case .finish:
      Task { await finish() }
      return true
    case .copyCurrentImage:
      copyCurrentImage()
      return true
    case .setMoveModifierActive(let active):
      isMoveModifierActive = active
      return true
    case .resetMoveModifierAndPassThrough:
      isMoveModifierActive = false
      return false
    }
  }

  func cancel() {
    complete(.failure(.cancelled))
  }

  func windowDidClose() {
    complete(.failure(.cancelled), closeWindow: false)
  }

  func controlDisplayID(for localRect: CGRect) -> CGDirectDisplayID {
    let bestMatch = displays
      .compactMap { display -> (displayID: CGDirectDisplayID, area: CGFloat)? in
        let intersection = display.localFrame.intersection(localRect)
        guard !intersection.isEmpty else { return nil }
        return (display.displayID, intersection.width * intersection.height)
      }
      .max { $0.area < $1.area }

    return bestMatch?.displayID ?? primaryDisplayID
  }

  func finish() async {
    await finish(pinToScreen: false)
  }

  func finishAndPin() async {
    await finish(pinToScreen: true)
  }

  private func finish(pinToScreen: Bool) async {
    guard phase == .annotating else { return }
    if let selectionRect, let crop = cropImage(for: selectionRect) {
      self.selectionRect = crop.localRect
      state.replaceSourceImagePreservingAnnotations(crop.image)
    }

    guard let renderedImage = AnnotateExporter.renderFinalImage(state: state),
          let cgImage = AnnotateExporter.bestCGImage(from: renderedImage) else {
      complete(.failure(.captureFailed(L10n.ScreenCapture.failedToCropCapturedImage)))
      return
    }

    let result = await ScreenCaptureManager.shared.saveProcessedImage(
      cgImage,
      to: saveDirectory,
      format: outputFormat,
      scaleFactor: Self.imageScale(renderedImage),
      emitCompletion: !pinToScreen,
      context: context
    )

    if case .success = result {
      SoundManager.playScreenshotCapture()
    }
    if case .success(let url) = result {
      persistCommittedSession(for: url)
    }
    complete(result)
    if pinToScreen, case .success(let url) = result {
      await PostCaptureActionHandler.shared.handleScreenshotCapture(url: url, pinToScreen: true)
    }
  }

  func copyCurrentImage() {
    guard let image = AnnotateExporter.renderFinalImage(state: state) else { return }
    ClipboardHelper.copyImage(image)
    SoundManager.play("Pop")
  }

  private func cropImage(for localRect: CGRect) -> InlineAreaCrop? {
    do {
      let screenRect = screenRect(for: localRect)
      let displayIDs = Self.displayIDsIntersecting(
        screenRect,
        screenFramesByDisplayID: screenFramesByDisplayID
      )
      guard let displayID = Self.primaryDisplayID(
        for: screenRect,
        screenFramesByDisplayID: screenFramesByDisplayID,
        fallback: primaryDisplayID
      ) else {
        throw CaptureError.captureFailed(L10n.ScreenCapture.selectionOutsideDisplayBounds)
      }

      let selection = AreaSelectionResult(
        target: .rect(screenRect),
        displayID: displayID,
        mode: .screenshot,
        displayIDs: displayIDs.isEmpty ? [displayID] : displayIDs
      )
      let outputScaleFactor = Self.preferredOutputScaleFactor
      let result = selection.spansMultipleDisplays
        ? try frozenSession.cropCompositeImage(
          for: selection,
          minimumOutputScaleFactor: outputScaleFactor
        )
        : try frozenSession.cropImage(
          for: selection,
          minimumOutputScaleFactor: outputScaleFactor
        )
      let image = NSImage(cgImage: result.image, size: result.screenRect.size)
      let localRect = Self.localRect(for: result.screenRect, in: desktopFrame)
      return InlineAreaCrop(image: image, localRect: clampedSelectionRect(localRect))
    } catch {
      DiagnosticLogger.shared.logError(.capture, error, "Inline area annotate crop failed")
      return nil
    }
  }

  private func screenRect(for localRect: CGRect) -> CGRect {
    Self.screenRect(for: localRect, in: desktopFrame)
  }

  private func clampedSelectionRect(_ rect: CGRect) -> CGRect {
    var result = rect
    result.size.width = min(max(result.width, 1), desktopFrame.width)
    result.size.height = min(max(result.height, 1), desktopFrame.height)
    result.origin.x = min(max(result.minX, 0), max(0, desktopFrame.width - result.width))
    result.origin.y = min(max(result.minY, 0), max(0, desktopFrame.height - result.height))
    return result
  }

  private func installKeyMonitors() {
    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
      guard self?.handleKeyEvent(event) == true else { return event }
      return nil
    }
    globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
      Task { @MainActor in
        _ = self?.handleKeyEvent(event, source: .global)
      }
    }
  }

  private func removeKeyMonitors() {
    if let localKeyMonitor {
      NSEvent.removeMonitor(localKeyMonitor)
      self.localKeyMonitor = nil
    }
    if let globalKeyMonitor {
      NSEvent.removeMonitor(globalKeyMonitor)
      self.globalKeyMonitor = nil
    }
  }

  private func installSelectionMonitorIfNeeded() {
    guard selectionLocalMonitor == nil else { return }
    selectionLocalMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDragged, .leftMouseUp]
    ) { [weak self] event in
      switch event.type {
      case .leftMouseDragged:
        MainActor.assumeIsolated {
          guard let self else { return }
          self.updateSelection(to: self.localDesktopPoint(for: NSEvent.mouseLocation))
        }
        return nil
      case .leftMouseUp:
        MainActor.assumeIsolated {
          guard let self else { return }
          self.endSelection(at: self.localDesktopPoint(for: NSEvent.mouseLocation))
        }
        return nil
      default:
        return event
      }
    }
  }

  private func removeSelectionMonitor() {
    if let selectionLocalMonitor {
      NSEvent.removeMonitor(selectionLocalMonitor)
      self.selectionLocalMonitor = nil
    }
  }

  private func localDesktopPoint(for screenPoint: CGPoint) -> CGPoint {
    CGPoint(
      x: screenPoint.x - desktopFrame.minX,
      y: desktopFrame.maxY - screenPoint.y
    )
  }

  private func complete(_ result: CaptureResult, closeWindow: Bool = true) {
    guard !didComplete else { return }
    didComplete = true
    isMoveModifierActive = false
    removeKeyMonitors()
    removeSelectionMonitor()
    frozenSession.invalidate()

    // Restore cursor before closing windows — the inline overlay uses a
    // transparent 1×1 cursor that could persist if window closure does not
    // trigger cursor rect re-evaluation.
    NSCursor.arrow.set()

    if closeWindow {
      for window in windows.allObjects {
        window.close()
      }
    }
    onComplete(result)
  }

  private func persistCommittedSession(for url: URL) {
    guard AnnotationSessionStore.shared.shouldPersist(for: url),
          let sourceImage = state.sourceImage,
          let originalImageData = AnnotateExporter.imageData(from: sourceImage, for: "png") else {
      return
    }
    let sessionData = AnnotationSessionData.snapshot(
      from: state,
      originalImageData: originalImageData
    )
    AnnotationSessionStore.shared.persist(sessionData, for: url)
  }

  private static func imageScale(_ image: NSImage) -> CGFloat {
    guard let rep = image.representations.first as? NSBitmapImageRep,
          image.size.width > 0,
          image.size.height > 0 else { return 1 }
    return max(CGFloat(rep.pixelsWide) / image.size.width, CGFloat(rep.pixelsHigh) / image.size.height, 1)
  }

  private static var preferredOutputScaleFactor: CGFloat {
    max(NSScreen.screens.map(\.backingScaleFactor).max() ?? 2.0, 2.0)
  }

  nonisolated static func matchesCommandSaveShortcut(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown else { return false }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard flags.contains(.command),
          !flags.contains(.control),
          !flags.contains(.option) else { return false }
    return event.keyCode == 1 || event.charactersIgnoringModifiers?.lowercased() == "s"
  }

  nonisolated static func matchesCommandCopyShortcut(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown else { return false }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard flags.contains(.command),
          !flags.contains(.control),
          !flags.contains(.option),
          !flags.contains(.shift) else { return false }
    return event.keyCode == 8 || event.charactersIgnoringModifiers?.lowercased() == "c"
  }

  nonisolated static func shouldHandleCommandCopyShortcut(
    _ event: NSEvent,
    isLocalEvent: Bool,
    hasTextResponder: Bool,
    hasKeyWindow: Bool
  ) -> Bool {
    matchesCommandCopyShortcut(event) && !hasTextResponder && (isLocalEvent || hasKeyWindow)
  }

  nonisolated static func keyAction(
    for event: NSEvent,
    source: InlineAreaKeyEventSource,
    phase: InlineAreaAnnotatePhase,
    hasTextResponder: Bool,
    hasKeyWindow: Bool
  ) -> InlineAreaKeyAction {
    guard phase == .annotating else {
      return matchesCancelShortcut(event) ? .cancel : .passThrough
    }

    if matchesCommandSaveShortcut(event) {
      return .finish
    }

    if hasTextResponder {
      return matchesMoveModifierKey(event) ? .resetMoveModifierAndPassThrough : .passThrough
    }

    if shouldHandleCommandCopyShortcut(
      event,
      isLocalEvent: source == .local,
      hasTextResponder: hasTextResponder,
      hasKeyWindow: hasKeyWindow
    ) {
      return .copyCurrentImage
    }

    if matchesMoveModifierKey(event) {
      return .setMoveModifierActive(event.type == .keyDown)
    }

    if matchesFinishShortcut(event) {
      return .finish
    }

    if matchesCancelShortcut(event) {
      return .cancel
    }

    return .passThrough
  }

  nonisolated static func matchesFinishShortcut(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown else { return false }
    return event.keyCode == 36 || event.keyCode == 76
  }

  nonisolated static func matchesCancelShortcut(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown else { return false }
    return event.keyCode == 53
  }

  nonisolated static func matchesMoveModifierKey(_ event: NSEvent) -> Bool {
    event.keyCode == 49 && (event.type == .keyDown || event.type == .keyUp)
  }

  nonisolated static func desktopFrame(for screenFrames: [CGRect]) -> CGRect {
    screenFrames.reduce(CGRect.null) { partialResult, frame in
      partialResult.union(frame)
    }
  }

  nonisolated static func localFrame(for screenFrame: CGRect, in desktopFrame: CGRect) -> CGRect {
    CGRect(
      x: screenFrame.minX - desktopFrame.minX,
      y: desktopFrame.maxY - screenFrame.maxY,
      width: screenFrame.width,
      height: screenFrame.height
    )
  }

  nonisolated static func screenRect(for localRect: CGRect, in desktopFrame: CGRect) -> CGRect {
    CGRect(
      x: desktopFrame.minX + localRect.minX,
      y: desktopFrame.maxY - localRect.maxY,
      width: localRect.width,
      height: localRect.height
    )
  }

  nonisolated static func localRect(for screenRect: CGRect, in desktopFrame: CGRect) -> CGRect {
    CGRect(
      x: screenRect.minX - desktopFrame.minX,
      y: desktopFrame.maxY - screenRect.maxY,
      width: screenRect.width,
      height: screenRect.height
    )
  }

  nonisolated static func displayIDsIntersecting(
    _ screenRect: CGRect,
    screenFramesByDisplayID: [CGDirectDisplayID: CGRect]
  ) -> Set<CGDirectDisplayID> {
    Set(screenFramesByDisplayID.compactMap { displayID, frame in
      frame.intersects(screenRect) ? displayID : nil
    })
  }

  nonisolated static func primaryDisplayID(
    for screenRect: CGRect,
    screenFramesByDisplayID: [CGDirectDisplayID: CGRect],
    fallback: CGDirectDisplayID?
  ) -> CGDirectDisplayID? {
    let bestMatch = screenFramesByDisplayID
      .compactMap { displayID, frame -> (displayID: CGDirectDisplayID, area: CGFloat)? in
        let intersection = frame.intersection(screenRect)
        guard !intersection.isEmpty else { return nil }
        return (displayID, intersection.width * intersection.height)
      }
      .max { $0.area < $1.area }

    return bestMatch?.displayID ?? fallback
  }
}
