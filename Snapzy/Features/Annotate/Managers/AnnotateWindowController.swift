//
//  AnnotateWindowController.swift
//  Snapzy
//
//  Controller managing annotation window lifecycle
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum AnnotateDragCompletionAction: Equatable {
  case closeAndDismiss
  case restore(presentation: AnnotateDragRestorePresentation)
}

enum AnnotateDragRestorePresentation: Equatable {
  case background
  case foreground
}

enum AnnotateDragCompletionPolicy {
  static func action(
    success: Bool,
    closeAfterDrag: Bool,
    bringForwardAfterDrag: Bool
  ) -> AnnotateDragCompletionAction {
    guard success else { return .restore(presentation: .foreground) }
    if closeAfterDrag {
      return .closeAndDismiss
    }
    return .restore(presentation: bringForwardAfterDrag ? .foreground : .background)
  }
}

/// Manages annotation window lifecycle and content
@MainActor
final class AnnotateWindowController: NSWindowController, NSWindowDelegate {

  private let fileAccessManager = SandboxFileAccessManager.shared
  private var sourceFileAccess: SandboxFileAccessManager.ScopedAccess?
  private let state: AnnotateState
  private let quickAccessItemId: UUID?
  private var cancellables = Set<AnyCancellable>()

  /// Compressed PNG data of the original source image (before annotations are baked).
  /// Captured on first open, reused across saves for session caching.
  private var originalImageData: Data?

  init(item: QuickAccessItem, sessionData: AnnotationSessionData? = nil) {
    self.quickAccessItemId = item.id
    self.sourceFileAccess = fileAccessManager.beginAccessingURL(item.url)

    if let sessionData = sessionData {
      // Restore from cache: decompress original image + editable annotations
      let image = NSImage(data: sessionData.originalImageData)
        .flatMap({ img in Self.applyRetinaScaling(to: img) })
        ?? item.thumbnail
      self.originalImageData = sessionData.originalImageData
      self.state = AnnotateState(
        image: image,
        url: item.url,
        quickAccessItemId: item.id,
        cloudURL: item.cloudURL,
        cloudKey: item.cloudKey,
        isCloudStale: item.isCloudStale,
        appliesDefaultCanvasPresetOnNewImages: false
      )
      self.state.restoreEmbeddedImageAssets(from: sessionData.embeddedImageAssetsData)
      self.state.annotations = sessionData.annotations
      self.state.applyCanvasEffects(
        sessionData.canvasEffects,
        preferredSelectedCanvasPresetId: sessionData.selectedCanvasPresetId,
        preferredPresetDirtyState: sessionData.isSelectedCanvasPresetDirty
      )
      self.state.cropRect = sessionData.cropRect
      self.state.isCropActive = false
      self.state.restoreBackgroundCutout(
        isApplied: sessionData.isCutoutApplied,
        cutoutImageData: sessionData.cutoutImageData,
        didAutoApplyCrop: sessionData.didCutoutAutoApplyCrop,
        autoAppliedCropRect: sessionData.cutoutAutoAppliedCropRect
      )
    } else {
      // First open: load image from disk and capture raw file bytes (fast, no re-encoding)
      let image = Self.loadImageWithCorrectScale(from: item.url) ?? item.thumbnail
      self.originalImageData = Self.readFileData(from: item.url)
      self.state = AnnotateState(image: image, url: item.url, quickAccessItemId: item.id, cloudURL: item.cloudURL, cloudKey: item.cloudKey, isCloudStale: item.isCloudStale)
    }

    // Fixed window size for consistent experience
    let windowWidth: CGFloat = 1200
    let windowHeight: CGFloat = 768

    let screenFrame = NSScreen.main?.frame ?? NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

    let origin = NSPoint(
      x: (screenFrame.width - windowWidth) / 2,
      y: (screenFrame.height - windowHeight) / 2
    )

    let window = AnnotateWindow(
      contentRect: NSRect(origin: origin, size: NSSize(width: windowWidth, height: windowHeight))
    )

    super.init(window: window)

    window.delegate = self
    window.interactionState = state
    setupContent()
    setupKeyboardShortcutObservers()
    setupSourceURLObservation()
  }

  /// Empty initializer for drag-drop workflow
  init() {
    self.quickAccessItemId = nil
    self.originalImageData = nil
    self.state = AnnotateState()

    // Default window size for empty canvas
    let defaultWidth: CGFloat = 1200
    let defaultHeight: CGFloat = 768

    let screenFrame = NSScreen.main?.frame ?? NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

    let origin = NSPoint(
      x: (screenFrame.width - defaultWidth) / 2,
      y: (screenFrame.height - defaultHeight) / 2
    )

    let window = AnnotateWindow(
      contentRect: NSRect(origin: origin, size: NSSize(width: defaultWidth, height: defaultHeight))
    )

    super.init(window: window)

    window.delegate = self
    window.interactionState = state
    setupContent()
    setupKeyboardShortcutObservers()
    setupSourceURLObservation()
  }

  /// URL-only initializer for post-capture auto-open flow
  init(url: URL, sessionData: AnnotationSessionData? = nil) {
    self.quickAccessItemId = nil
    self.sourceFileAccess = SandboxFileAccessManager.shared.beginAccessingURL(url)

    if let sessionData {
      let image = NSImage(data: sessionData.originalImageData)
        .flatMap({ img in Self.applyRetinaScaling(to: img) })
        ?? Self.loadImageWithCorrectScale(from: url)
        ?? NSImage(size: NSSize(width: 400, height: 300))
      self.originalImageData = sessionData.originalImageData
      self.state = AnnotateState(
        image: image,
        url: url,
        appliesDefaultCanvasPresetOnNewImages: false
      )
      self.state.restoreEmbeddedImageAssets(from: sessionData.embeddedImageAssetsData)
      self.state.annotations = sessionData.annotations
      self.state.applyCanvasEffects(
        sessionData.canvasEffects,
        preferredSelectedCanvasPresetId: sessionData.selectedCanvasPresetId,
        preferredPresetDirtyState: sessionData.isSelectedCanvasPresetDirty
      )
      self.state.cropRect = sessionData.cropRect
      self.state.isCropActive = false
      self.state.restoreBackgroundCutout(
        isApplied: sessionData.isCutoutApplied,
        cutoutImageData: sessionData.cutoutImageData,
        didAutoApplyCrop: sessionData.didCutoutAutoApplyCrop,
        autoAppliedCropRect: sessionData.cutoutAutoAppliedCropRect
      )
    } else {
      let image = Self.loadImageWithCorrectScale(from: url)
        ?? NSImage(size: NSSize(width: 400, height: 300))
      self.originalImageData = Self.readFileData(from: url)
      self.state = AnnotateState(image: image, url: url)
    }

    let windowWidth: CGFloat = 1200
    let windowHeight: CGFloat = 768

    let screenFrame = NSScreen.main?.frame ?? NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

    let origin = NSPoint(
      x: (screenFrame.width - windowWidth) / 2,
      y: (screenFrame.height - windowHeight) / 2
    )

    let window = AnnotateWindow(
      contentRect: NSRect(origin: origin, size: NSSize(width: windowWidth, height: windowHeight))
    )

    super.init(window: window)

    window.delegate = self
    window.interactionState = state
    setupContent()
    setupKeyboardShortcutObservers()
    setupSourceURLObservation()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    sourceFileAccess?.stop()
    cancellables.removeAll()
  }

  private func setupContent() {
    let capturedState = self.state
    let mainView = AnnotateMainView(state: capturedState)
    window?.contentView = NSHostingView(rootView: mainView)
    (window as? AnnotateWindow)?.onEscape = { [weak self] in
      self?.discardEditsAndClose() ?? false
    }
  }

  private func discardEditsAndClose() -> Bool {
    guard let quickAccessItemId else { return false }
    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Annotate window closed via Esc, discarding edits",
      context: ["itemId": quickAccessItemId.uuidString]
    )
    forceClose()
    return true
  }



  func showWindow() {
    window?.makeKeyAndOrderFront(nil)
    window?.makeMain()
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowDidBecomeKey(_ notification: Notification) {
    (notification.object as? AnnotateWindow)?.syncLevelWithFocusState()
  }

  func windowDidResignKey(_ notification: Notification) {
    (notification.object as? AnnotateWindow)?.syncLevelWithFocusState()
  }

  func windowDidBecomeMain(_ notification: Notification) {
    (notification.object as? AnnotateWindow)?.syncLevelWithFocusState()
  }

  func windowDidResignMain(_ notification: Notification) {
    (notification.object as? AnnotateWindow)?.syncLevelWithFocusState()
  }

  // MARK: - Image Loading

  /// Load image and adjust size for Retina displays
  private static func loadImageWithCorrectScale(from url: URL) -> NSImage? {
    guard let image = SandboxFileAccessManager.shared.withScopedAccess(to: url, {
      NSImage(contentsOf: url)
    }) else { return nil }

    let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
    if let normalizedSize = normalizedRetinaLogicalSizeIfNeeded(for: image, scaleFactor: scaleFactor) {
      image.size = normalizedSize
    }

    return image
  }

  /// Apply Retina scaling to an image loaded from Data (same logic as loadImageWithCorrectScale)
  private static func applyRetinaScaling(to image: NSImage) -> NSImage {
    let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
    if let normalizedSize = normalizedRetinaLogicalSizeIfNeeded(for: image, scaleFactor: scaleFactor) {
      image.size = normalizedSize
    }
    return image
  }

  private static func normalizedRetinaLogicalSizeIfNeeded(
    for image: NSImage,
    scaleFactor: CGFloat
  ) -> NSSize? {
    guard scaleFactor > 1 else { return nil }
    guard let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 else {
      return nil
    }

    let pixelWidth = CGFloat(rep.pixelsWide)
    let pixelHeight = CGFloat(rep.pixelsHigh)
    let currentSize = image.size
    let expectedSize = NSSize(
      width: pixelWidth / scaleFactor,
      height: pixelHeight / scaleFactor
    )

    let isAlreadyScaled =
      abs(currentSize.width - expectedSize.width) < 0.5 &&
      abs(currentSize.height - expectedSize.height) < 0.5
    if isAlreadyScaled {
      return nil
    }

    let isUnscaledLogicalSize =
      abs(currentSize.width - pixelWidth) < 0.5 &&
      abs(currentSize.height - pixelHeight) < 0.5
    return isUnscaledLogicalSize ? expectedSize : nil
  }

  /// Read raw file bytes from disk (fast: no image decoding or re-encoding)
  private static func readFileData(from url: URL) -> Data? {
    SandboxFileAccessManager.shared.withScopedAccess(to: url) {
      try? Data(contentsOf: url)
    }
  }

  private func setupSourceURLObservation() {
    state.$sourceURL
      .sink { [weak self] url in
        self?.refreshSourceAccess(for: url)
      }
      .store(in: &cancellables)
  }

  private func refreshSourceAccess(for url: URL?) {
    sourceFileAccess?.stop()
    sourceFileAccess = nil

    guard let url = url else { return }
    sourceFileAccess = fileAccessManager.beginAccessingURL(url)
  }

  private var requiresCloudOverwriteConfirmation: Bool {
    state.cloudURL != nil && (state.requiresRenderedOutputForSharing || state.isCloudStale)
  }

  private var shouldCloseAfterDrag: Bool {
    UserDefaults.standard.object(forKey: PreferencesKeys.annotateCloseAfterDrag) as? Bool ?? true
  }

  private var shouldBringForwardAfterDrag: Bool {
    UserDefaults.standard.object(forKey: PreferencesKeys.annotateBringForwardAfterDrag) as? Bool ?? false
  }

  private enum PasteboardImageCandidate {
    case file(URL)
    case data(NSImage, Data)
    case image(NSImage)
  }

  private static let pasteboardRawImageTypes: [NSPasteboard.PasteboardType] = [
    .png,
    .tiff,
    NSPasteboard.PasteboardType(UTType.jpeg.identifier),
    NSPasteboard.PasteboardType(UTType.gif.identifier),
    NSPasteboard.PasteboardType(UTType.bmp.identifier),
    NSPasteboard.PasteboardType(UTType.heic.identifier),
    NSPasteboard.PasteboardType(UTType.webP.identifier),
  ]

  private static func hasPasteboardImage(_ pasteboard: NSPasteboard) -> Bool {
    !pasteboardImageCandidates(from: pasteboard).isEmpty
  }

  private static func pasteboardImageCandidates(from pasteboard: NSPasteboard) -> [PasteboardImageCandidate] {
    if let firstItem = pasteboard.pasteboardItems?.first {
      let directCandidates = pasteboardImageCandidates(from: firstItem)
      if !directCandidates.isEmpty {
        return directCandidates
      }
    }

    var candidates: [PasteboardImageCandidate] = []
    let pastedURLs = pasteboard.readObjects(
      forClasses: [NSURL.self],
      options: [.urlReadingFileURLsOnly: true]
    )

    if let imageURLs = (pastedURLs as? [URL]) ?? (pastedURLs as? [NSURL])?.map({ $0 as URL }) {
      for imageURL in imageURLs where AnnotateCanvasView.isValidImageFile(url: imageURL) {
        candidates.append(.file(imageURL))
      }
    }

    if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
       let image = images.first {
      candidates.append(.image(image))
    }

    return candidates
  }

  private static func pasteboardImageCandidates(from item: NSPasteboardItem) -> [PasteboardImageCandidate] {
    var candidates: [PasteboardImageCandidate] = []

    if let fileURL = fileURL(from: item),
       AnnotateCanvasView.isValidImageFile(url: fileURL) {
      candidates.append(.file(fileURL))
    }

    for rawType in pasteboardRawImageTypes {
      guard let data = item.data(forType: rawType),
            let image = NSImage(data: data) else { continue }
      candidates.append(.data(image, data))
    }

    return candidates
  }

  private static func fileURL(from item: NSPasteboardItem) -> URL? {
    guard let value = item.string(forType: .fileURL) else { return nil }
    if let url = URL(string: value), url.isFileURL {
      return url
    }
    guard value.hasPrefix("/") else { return nil }
    return URL(fileURLWithPath: value)
  }

  // MARK: - Manual Open Clipboard Import

  func handleManualOpenClipboardImageBehavior() {
    let behavior = AnnotateClipboardImageBehavior.stored()
    guard behavior != .doNothing else { return }
    guard Self.hasPasteboardImage(NSPasteboard.general) else { return }

    switch behavior {
    case .ask:
      showClipboardImagePrompt()
    case .loadAutomatically:
      performPasteImage(beepOnFailure: false)
    case .doNothing:
      break
    }
  }

  private func showClipboardImagePrompt() {
    guard let window = self.window else { return }

    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = L10n.AnnotateUI.clipboardImagePromptTitle
    alert.informativeText = L10n.AnnotateUI.clipboardImagePromptMessage

    let loadButton = alert.addButton(withTitle: L10n.AnnotateUI.loadImageButton)
    loadButton.keyEquivalent = "\r"

    let notNowButton = alert.addButton(withTitle: L10n.AnnotateUI.notNowButton)
    notNowButton.keyEquivalent = "\u{1B}"

    alert.showsSuppressionButton = true
    alert.suppressionButton?.title = L10n.AnnotateUI.dontAskAgain

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self else { return }

      let shouldRemember = alert.suppressionButton?.state == .on
      switch response {
      case .alertFirstButtonReturn:
        if shouldRemember {
          AnnotateClipboardImageBehavior.loadAutomatically.persist()
        }
        self.performPasteImage()
      case .alertSecondButtonReturn:
        if shouldRemember {
          AnnotateClipboardImageBehavior.doNothing.persist()
        }
      default:
        break
      }
    }
  }

  // MARK: - NSWindowDelegate

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard state.hasUnsavedChanges else {
      forceClose()
      return false
    }

    showUnsavedChangesAlert(for: sender)
    return false
  }

  private func showUnsavedChangesAlert(for window: NSWindow) {
    let alert = NSAlert()
    alert.messageText = L10n.AnnotateUI.unsavedChangesTitle
    alert.informativeText = L10n.AnnotateUI.unsavedChangesMessage
    alert.alertStyle = .warning

    alert.addButton(withTitle: L10n.VideoEditor.save)
    alert.addButton(withTitle: L10n.AnnotateUI.dontSave)
    alert.addButton(withTitle: L10n.Common.cancel)

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self = self else { return }

      switch response {
      case .alertFirstButtonReturn:
        self.performSaveAndClose()

      case .alertSecondButtonReturn:
        self.forceClose()

      default:
        break
      }
    }
  }

  private func performSaveAndClose() {
    // Cloud gate: if the rendered output differs from the uploaded file, require overwrite confirmation.
    if requiresCloudOverwriteConfirmation {
      showCloudOverwriteAlert { [weak self] in
        self?.performCloudReUploadAndClose()
      }
      return
    }
    executeSaveAndClose()
  }

  private func executeSaveAndClose() {
    if state.sourceURL != nil {
      // Render once, update thumbnail instantly, close, save in background
      let sourceURL = state.sourceURL
      let sessionSnapshot = makeSessionSnapshot()
      state.markAsSaved()
      saveSessionCache(sessionSnapshot)
      let renderedImage = AnnotateExporter.renderFinalImage(state: state)
      if let renderedImage = renderedImage, let itemId = quickAccessItemId {
        QuickAccessManager.shared.updateItemThumbnail(id: itemId, image: renderedImage)
        QuickAccessManager.shared.markCloudStale(id: itemId)
      }
      let capturedState = state
      forceClose()
      Task.detached(priority: .userInitiated) {
        guard await AnnotateExporter.saveToFile(image: renderedImage, state: capturedState),
              let sourceURL else { return }
        await Self.persistCommittedSession(sessionSnapshot, for: sourceURL)
        await PostCaptureActionHandler.shared.copyEditedCaptureToClipboardIfEnabled(
          for: .screenshot,
          url: sourceURL
        )
      }
    } else {
      AnnotateExporter.saveAs(state: state, closeWindow: true)
    }
  }



  private func forceClose() {
    state.hasUnsavedChanges = false
    guard let window = self.window else { return }
    
    // Hide window instantly
    window.alphaValue = 0
    
    if let itemId = quickAccessItemId {
      QuickAccessManager.shared.setWindowOpen(id: itemId, isOpen: false)
    }
    
    window.close()
  }

  // MARK: - Keyboard Shortcuts

  private func setupKeyboardShortcutObservers() {
    guard let window = self.window else { return }

    NotificationCenter.default.addObserver(
      forName: .annotateSave,
      object: window,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.performSave()
      }
    }

    NotificationCenter.default.addObserver(
      forName: .annotateSaveAs,
      object: window,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.performSaveAs()
      }
    }

    NotificationCenter.default.addObserver(
      forName: .annotateCopyAndClose,
      object: window,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.performCopy()
      }
    }

    NotificationCenter.default.addObserver(
      forName: .annotateTogglePin,
      object: window,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.togglePin()
      }
    }

    NotificationCenter.default.addObserver(
      forName: .annotatePasteImage,
      object: window,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        _ = self?.performPasteImage()
      }
    }

    NotificationCenter.default.addObserver(
      forName: .annotateAutoRedactSensitiveData,
      object: window,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.state.autoRedactSensitiveData()
      }
    }

    // Drag-to-app: hide window when drag starts
    NotificationCenter.default.addObserver(
      forName: .annotateDragStarted,
      object: window,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.handleDragStarted()
      }
    }

    // Drag-to-app: restore or close window when drag ends
    NotificationCenter.default.addObserver(
      forName: .annotateDragEnded,
      object: window,
      queue: .main
    ) { [weak self] notification in
      MainActor.assumeIsolated {
        let success = (notification.userInfo?["success"] as? Bool) ?? false
        self?.handleDragEnded(success: success)
      }
    }
  }

  // MARK: - Drag-to-App Window Management

  private var savedWindowFrame: NSRect?

  private func handleDragStarted() {
    guard let window = self.window else { return }
    savedWindowFrame = window.frame
    window.orderOut(nil) // Hide without closing
    print("[AnnotateDrag] Window hidden for drag session")
  }

  private func handleDragEnded(success: Bool) {
    switch AnnotateDragCompletionPolicy.action(
      success: success,
      closeAfterDrag: shouldCloseAfterDrag,
      bringForwardAfterDrag: shouldBringForwardAfterDrag
    ) {
    case .closeAndDismiss:
      commitDragSuccessChangesIfNeeded()
      forceClose()
      // Also dismiss the Quick Access card (without deleting the file)
      if let itemId = quickAccessItemId {
        QuickAccessManager.shared.dismissCard(id: itemId)
      }
      print("[AnnotateDrag] Drag succeeded — window + QA card dismissed")

    case .restore(let presentation):
      restoreWindowAfterDrag(presentation: presentation)
      if success {
        print("[AnnotateDrag] Drag succeeded — editor preserved")
      } else {
        print("[AnnotateDrag] Drag cancelled — window restored")
      }
    }
    savedWindowFrame = nil
  }

  private func restoreWindowAfterDrag(presentation: AnnotateDragRestorePresentation) {
    guard let window = self.window else { return }
    if let frame = savedWindowFrame {
      window.setFrame(frame, display: true)
    }

    switch presentation {
    case .foreground:
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    case .background:
      window.orderBack(nil)
    }
  }

  private func commitDragSuccessChangesIfNeeded() {
    guard state.requiresRenderedOutputForSharing else {
      state.markAsSaved()
      return
    }

    guard let sourceURL = state.sourceURL else {
      state.markAsSaved()
      return
    }

    let renderedImage = AnnotateExporter.renderFinalImage(state: state)
    guard let renderedImage else {
      DiagnosticLogger.shared.log(
        .error,
        .annotate,
        "Annotate drag success save skipped; render returned nil",
        context: ["fileName": sourceURL.lastPathComponent]
      )
      state.markAsSaved()
      return
    }

    let sessionSnapshot = makeSessionSnapshot()
    state.markAsSaved()
    saveSessionCache(sessionSnapshot)
    if let itemId = quickAccessItemId {
      QuickAccessManager.shared.updateItemThumbnail(id: itemId, image: renderedImage)
      QuickAccessManager.shared.markCloudStale(id: itemId)
    }

    let capturedState = state
    Task.detached(priority: .userInitiated) {
      guard await AnnotateExporter.saveToFile(image: renderedImage, state: capturedState) else {
        DiagnosticLogger.shared.log(
          .error,
          .annotate,
          "Annotate drag success save failed",
          context: ["fileName": sourceURL.lastPathComponent]
        )
        return
      }
      await Self.persistCommittedSession(sessionSnapshot, for: sourceURL)
      await PostCaptureActionHandler.shared.copyEditedCaptureToClipboardIfEnabled(
        for: .screenshot,
        url: sourceURL
      )
    }
  }

  private func togglePin() {
    guard let window = self.window else { return }
    let newPinned = !state.isPinned
    if let annotateWindow = window as? AnnotateWindow {
      annotateWindow.setRestingLevel(newPinned ? .floating : .normal)
    } else {
      window.level = newPinned ? .floating : .normal
    }
    state.isPinned = newPinned
  }

  @discardableResult
  private func performPasteImage(beepOnFailure: Bool = true) -> Bool {
    for candidate in Self.pasteboardImageCandidates(from: NSPasteboard.general) {
      if importPasteboardImage(candidate) {
        return true
      }
    }

    if beepOnFailure {
      NSSound.beep()
    }
    return false
  }

  private func importPasteboardImage(_ candidate: PasteboardImageCandidate) -> Bool {
    switch candidate {
    case .file(let url):
      return state.importImage(from: url)
    case .data(let image, let data):
      return state.importImage(image, sourceURL: nil, sourceData: data)
    case .image(let image):
      return state.importImage(image, sourceURL: nil)
    }
  }

  /// Silent save — renders once, updates thumbnail instantly, closes window, saves in background
  /// If previously uploaded to cloud, gate behind overwrite confirmation.
  private func performSave() {
    guard state.hasImage else { return }

    // Cloud gate: if the rendered output differs from the uploaded file, require overwrite confirmation.
    if requiresCloudOverwriteConfirmation {
      showCloudOverwriteAlert { [weak self] in
        self?.performCloudReUploadAndClose()
      }
      return
    }
    executeSave()
  }

  private func executeSave() {
    guard state.hasImage else { return }

    if state.sourceURL != nil {
      if let targetURL = state.sourceURL {
        guard AnnotateExporter.confirmTransparencyLossIfNeeded(state: state, targetURL: targetURL) else {
          return
        }
      }

      // Render the annotated image once
      let sourceURL = state.sourceURL
      let sessionSnapshot = makeSessionSnapshot()
      let renderedImage = AnnotateExporter.renderFinalImage(state: state)

      // Update QA thumbnail instantly (synchronous, no file I/O)
      state.markAsSaved()
      saveSessionCache(sessionSnapshot)
      if let renderedImage = renderedImage, let itemId = quickAccessItemId {
        QuickAccessManager.shared.updateItemThumbnail(id: itemId, image: renderedImage)
        QuickAccessManager.shared.markCloudStale(id: itemId)
      }

      // Close window instantly
      let capturedState = state
      forceClose()

      // Save to disk in background
      Task.detached(priority: .userInitiated) {
        guard await AnnotateExporter.saveToFile(image: renderedImage, state: capturedState),
              let sourceURL else { return }
        await Self.persistCommittedSession(sessionSnapshot, for: sourceURL)
        await PostCaptureActionHandler.shared.copyEditedCaptureToClipboardIfEnabled(
          for: .screenshot,
          url: sourceURL
        )
      }
    } else {
      performSaveAs()
    }
  }

  private func performSaveAs() {
    guard state.hasImage else { return }

    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png, .jpeg, .webP]
    panel.nameFieldStringValue = generateFileName()
    panel.canCreateDirectories = true

    guard let window = self.window else { return }

    panel.beginSheetModal(for: window) { [weak self] response in
      guard let self = self, response == .OK, let url = panel.url else { return }
      guard AnnotateExporter.confirmTransparencyLossIfNeeded(state: self.state, targetURL: url) else {
        return
      }
      if AnnotateExporter.save(state: self.state, to: url) {
        self.state.markAsSaved()
        // Dismiss Quick Access card if present
        if let itemId = self.quickAccessItemId {
          QuickAccessManager.shared.dismissCard(id: itemId)
        }
        // Close annotate window
        self.forceClose()
      } else {
        self.showSaveErrorAlert()
      }
    }
  }

  private func showSaveErrorAlert() {
    guard let window = self.window else { return }

    let alert = NSAlert()
    alert.messageText = L10n.AnnotateUI.saveFailedTitle
    alert.informativeText = L10n.AnnotateUI.saveFailedMessage
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.Common.ok)
    alert.beginSheetModal(for: window)
  }

  private func generateFileName() -> String {
    guard let url = state.sourceURL else { return L10n.AnnotateUI.defaultAnnotatedFileName }
    let baseName = url.deletingPathExtension().lastPathComponent
    // Use the source file's extension so the default matches the configured format
    let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
    return "\(baseName)_annotated.\(ext)"
  }

  /// Copy = render once, copy to clipboard, update thumbnail, close, save in background.
  /// If previously uploaded to cloud and output changed, gate behind overwrite confirmation.
  private func performCopy() {
    guard state.hasImage else { return }

    // Cloud gate: if the rendered output differs from the uploaded file, require overwrite confirmation.
    if requiresCloudOverwriteConfirmation {
      showCloudOverwriteAlert { [weak self] in
        self?.performCloudReUploadCopyAndClose()
      }
      return
    }
    executeCopy()
  }

  private func executeCopy() {
    guard state.hasImage else { return }

    // Render once, use for everything
    let renderedImage = AnnotateExporter.renderFinalImage(state: state)

    // Copy to clipboard — cloud link (text) if available, otherwise image
    if let cloudURL = state.cloudURL {
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(cloudURL.absoluteString, forType: .string)
      SoundManager.play("Pop")
    } else if let renderedImage = renderedImage {
      ClipboardHelper.copyImage(renderedImage)
      SoundManager.play("Pop")
    }

    // Update QA thumbnail instantly + cache
    let sessionSnapshot = makeSessionSnapshot()
    if let _ = state.sourceURL {
      state.markAsSaved()
      saveSessionCache(sessionSnapshot)
    }
    if let renderedImage = renderedImage, let itemId = quickAccessItemId {
      QuickAccessManager.shared.updateItemThumbnail(id: itemId, image: renderedImage)
      QuickAccessManager.shared.markCloudStale(id: itemId)
    }

    // Close instantly, save in background
    let capturedState = state
    let sourceURL = state.sourceURL
    forceClose()
    Task.detached(priority: .userInitiated) {
      guard await AnnotateExporter.saveToFile(image: renderedImage, state: capturedState),
            let sourceURL else { return }
      await Self.persistCommittedSession(sessionSnapshot, for: sourceURL)
    }
  }

  // MARK: - Cloud Overwrite

  /// Show alert asking user to confirm overwrite of cloud file.
  /// "Overwrite" → executes onOverwrite closure. "Cancel" → does nothing (window stays open).
  private func showCloudOverwriteAlert(onOverwrite: @escaping () -> Void) {
    guard let window = self.window else {
      onOverwrite()
      return
    }

    let alert = NSAlert()
    alert.messageText = L10n.AnnotateUI.overwriteCloudFileTitle
    alert.informativeText = L10n.AnnotateUI.overwriteCloudFileOnSaveMessage
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.Common.overwrite)
    alert.addButton(withTitle: L10n.Common.cancel)

    alert.beginSheetModal(for: window) { response in
      if response == .alertFirstButtonReturn {
        onOverwrite()
      }
      // Cancel: do nothing — window stays open, changes preserved but not committed
    }
  }

  /// Save locally + re-upload to cloud + update QA card + close window.
  /// Used when user confirms overwrite on Save or Close-Save.
  private func performCloudReUploadAndClose() {
    guard let sourceURL = state.sourceURL else { return }

    // Render once
    let sessionSnapshot = makeSessionSnapshot()
    let renderedImage = AnnotateExporter.renderFinalImage(state: state)

    // Save to disk first (so cloud upload reads the updated file)
    if let renderedImage = renderedImage {
      let didSaveRenderedImage = AnnotateExporter.saveToFile(image: renderedImage, state: state)
      if didSaveRenderedImage {
        Self.persistCommittedSession(sessionSnapshot, for: sourceURL)
      }
    }

    let oldCloudKey = state.cloudKey
    let capturedState = state
    let itemId = quickAccessItemId

    // Re-upload to cloud
    Task {
      do {
        let fileAccess = SandboxFileAccessManager.shared.beginAccessingURL(sourceURL)
        defer { fileAccess.stop() }
        DiagnosticLogger.shared.log(
          .info,
          .cloud,
          "Annotate cloud re-upload started",
          context: ["fileName": sourceURL.lastPathComponent, "mode": "save"]
        )

        let result = try await CloudManager.shared.upload(fileURL: sourceURL)

        // Delete old cloud file in background
        if let oldKey = oldCloudKey {
          Task.detached(priority: .utility) {
            do {
              try await CloudManager.shared.deleteByKey(key: oldKey)
            } catch {
              DiagnosticLogger.shared.logError(.cloud, error, "Annotate old cloud object cleanup failed")
            }
          }
        }

        // Update state
        capturedState.cloudURL = result.publicURL
        capturedState.cloudKey = result.key
        capturedState.markAsSaved()
        capturedState.isCloudStale = false

        // Update QuickAccess item: thumbnail first, then setCloudURL to reset stale
        if let itemId = itemId {
          if let renderedImage = renderedImage {
            QuickAccessManager.shared.updateItemThumbnail(id: itemId, image: renderedImage)
          }
          QuickAccessManager.shared.setCloudURL(id: itemId, url: result.publicURL, key: result.key)
        }

        // Auto-copy cloud link
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.publicURL.absoluteString, forType: .string)

        SoundManager.play("Pop")
        DiagnosticLogger.shared.log(
          .info,
          .cloud,
          "Annotate cloud re-upload completed",
          context: ["fileName": sourceURL.lastPathComponent, "mode": "save"]
        )
        self.forceClose()
      } catch {
        DiagnosticLogger.shared.logError(
          .cloud,
          error,
          "Annotate cloud re-upload failed; falling back to local save",
          context: ["fileName": sourceURL.lastPathComponent, "mode": "save"]
        )
        // Fall back to local save only
        capturedState.markAsSaved()
        if let renderedImage = renderedImage, let itemId = itemId {
          QuickAccessManager.shared.updateItemThumbnail(id: itemId, image: renderedImage)
        }
        await PostCaptureActionHandler.shared.copyEditedCaptureToClipboardIfEnabled(
          for: .screenshot,
          url: sourceURL
        )
        self.forceClose()
      }
    }
  }

  /// Save locally + re-upload to cloud + copy cloud URL + close window.
  /// Used when user confirms overwrite on Copy (⌘⇧C).
  private func performCloudReUploadCopyAndClose() {
    guard let sourceURL = state.sourceURL else { return }

    // Render once
    let sessionSnapshot = makeSessionSnapshot()
    let renderedImage = AnnotateExporter.renderFinalImage(state: state)

    // Save to disk first
    if let renderedImage = renderedImage {
      let didSaveRenderedImage = AnnotateExporter.saveToFile(image: renderedImage, state: state)
      if didSaveRenderedImage {
        Self.persistCommittedSession(sessionSnapshot, for: sourceURL)
      }
    }

    let oldCloudKey = state.cloudKey
    let capturedState = state
    let itemId = quickAccessItemId

    // Re-upload to cloud
    Task {
      do {
        let fileAccess = SandboxFileAccessManager.shared.beginAccessingURL(sourceURL)
        defer { fileAccess.stop() }
        DiagnosticLogger.shared.log(
          .info,
          .cloud,
          "Annotate cloud re-upload started",
          context: ["fileName": sourceURL.lastPathComponent, "mode": "copy"]
        )

        let result = try await CloudManager.shared.upload(fileURL: sourceURL)

        // Delete old cloud file
        if let oldKey = oldCloudKey {
          Task.detached(priority: .utility) {
            do {
              try await CloudManager.shared.deleteByKey(key: oldKey)
            } catch {
              DiagnosticLogger.shared.logError(.cloud, error, "Annotate old cloud object cleanup failed")
            }
          }
        }

        // Update state
        capturedState.cloudURL = result.publicURL
        capturedState.cloudKey = result.key
        capturedState.markAsSaved()
        capturedState.isCloudStale = false

        // Update QuickAccess item: thumbnail first, then setCloudURL to reset stale
        if let itemId = itemId {
          if let renderedImage = renderedImage {
            QuickAccessManager.shared.updateItemThumbnail(id: itemId, image: renderedImage)
          }
          QuickAccessManager.shared.setCloudURL(id: itemId, url: result.publicURL, key: result.key)
        }

        // Copy cloud link to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.publicURL.absoluteString, forType: .string)

        SoundManager.play("Pop")
        DiagnosticLogger.shared.log(
          .info,
          .cloud,
          "Annotate cloud re-upload completed",
          context: ["fileName": sourceURL.lastPathComponent, "mode": "copy"]
        )
        self.forceClose()
      } catch {
        DiagnosticLogger.shared.logError(
          .cloud,
          error,
          "Annotate cloud re-upload failed; falling back to image clipboard",
          context: ["fileName": sourceURL.lastPathComponent, "mode": "copy"]
        )
        // Fall back: copy image to clipboard, close
        if let renderedImage = renderedImage {
          ClipboardHelper.copyImage(renderedImage)
        }
        capturedState.markAsSaved()
        if let renderedImage = renderedImage, let itemId = itemId {
          QuickAccessManager.shared.updateItemThumbnail(id: itemId, image: renderedImage)
        }
        SoundManager.play("Pop")
        self.forceClose()
      }
    }
  }

  // MARK: - Session Cache

  private func makeSessionSnapshot() -> AnnotationSessionData? {
    AnnotateManager.shared.makeSessionData(for: state, originalImageData: originalImageData)
  }

  /// Save current annotation state to session cache for re-editing
  private func saveSessionCache(_ snapshot: AnnotationSessionData?) {
    guard let itemId = quickAccessItemId,
          let snapshot else { return }
    let startedAt = CFAbsoluteTimeGetCurrent()
    let snapshotDurationMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000)
    let embeddedBytes = snapshot.embeddedImageAssetsData.values.reduce(0) { $0 + $1.count }

    AnnotateManager.shared.saveSessionData(snapshot, for: itemId)

    let totalDurationMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000)
    DiagnosticLogger.shared.log(.debug, .annotate, "Session cache updated", context: [
      "itemId": itemId.uuidString,
      "annotations": "\(snapshot.annotations.count)",
      "embeddedAssets": "\(snapshot.embeddedImageAssetsData.count)",
      "embeddedBytes": "\(embeddedBytes)",
      "snapshotMs": "\(snapshotDurationMs)",
      "totalMs": "\(totalDurationMs)"
    ])
  }

  @MainActor
  private static func persistCommittedSession(_ snapshot: AnnotationSessionData?, for sourceURL: URL) {
    guard let snapshot,
          AnnotationSessionStore.shared.shouldPersist(for: sourceURL) else { return }
    AnnotationSessionStore.shared.persist(snapshot, for: sourceURL)
  }
}
