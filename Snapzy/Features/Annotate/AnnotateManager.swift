//
//  AnnotateManager.swift
//  Snapzy
//
//  Singleton manager for opening and tracking annotation windows
//

import AppKit
import Foundation

enum AnnotateCanvasDefaults {
  static let cornerRadius: CGFloat = 0
}

/// In-memory annotation session data for re-editing annotations
struct AnnotationCanvasEffects {
  var backgroundStyle: BackgroundStyle = .none
  var isBlurredBackgroundEnabled: Bool = false
  var blurredBackgroundEffect: BlurredBackgroundEffect = .soft
  var padding: CGFloat = 0
  var inset: CGFloat = 0
  var autoBalance: Bool = true
  var shadowIntensity: CGFloat = 0.3
  var cornerRadius: CGFloat = AnnotateCanvasDefaults.cornerRadius
  var imageAlignment: ImageAlignment = .center
  var aspectRatio: AspectRatioOption = .auto
  var aspectRatioOrientation: AspectRatioOrientation = .horizontal
}

/// In-memory annotation session data for re-editing annotations
/// Preserved until the Quick Access card is dismissed
struct AnnotationSessionData {
  /// Compressed PNG data of the original image (before any annotations were baked)
  let originalImageData: Data
  var annotations: [AnnotationItem]
  var canvasEffects: AnnotationCanvasEffects
  /// Selected canvas preset id at the moment session was cached.
  var selectedCanvasPresetId: UUID?
  /// True when current canvas values diverged from selected preset at cache time.
  var isSelectedCanvasPresetDirty: Bool = false
  /// Applied crop rectangle in image coordinates (if any)
  var cropRect: CGRect?
  /// Whether background cutout was active in this editing session.
  var isCutoutApplied: Bool = false
  /// PNG data for the cutout source image (alpha preserved) when cutout is active.
  var cutoutImageData: Data? = nil
  /// True if current crop was auto-applied by cutout logic.
  var didCutoutAutoApplyCrop: Bool = false
  /// Stored auto-applied crop rect to preserve deterministic toggle-off behavior.
  var cutoutAutoAppliedCropRect: CGRect? = nil
  /// Imported image assets referenced by `.embeddedImage(assetId)` annotations.
  var embeddedImageAssetsData: [UUID: Data] = [:]
}

/// Manages annotation window instances
@MainActor
final class AnnotateManager {

  static let shared = AnnotateManager()

  private var windowControllers: [UUID: AnnotateWindowController] = [:]
  private var manualWindowControllers: [UUID: AnnotateWindowController] = [:]

  /// In-memory cache: original image + annotations, keyed by QuickAccessItem.id
  private var sessionCache: [UUID: AnnotationSessionData] = [:]

  private init() {}

  // MARK: - Activation Policy Management

  /// Switch to regular app mode (visible in Dock + Cmd+Tab)
  private func becomeRegularApp() {
    if NSApp.activationPolicy() != .regular {
      NSApp.setActivationPolicy(.regular)
    }
  }

  /// Switch back to accessory mode (menu bar only) if no windows open
  private func becomeAccessoryAppIfNeeded() {
    guard windowControllers.isEmpty && manualWindowControllers.isEmpty else { return }
    guard !VideoEditorManager.shared.hasOpenWindows else { return }
    NSApp.revertActivationPolicyToAccessoryIfNeeded()
  }

  /// Check if any annotate windows are open
  var hasOpenWindows: Bool {
    !windowControllers.isEmpty || !manualWindowControllers.isEmpty
  }

  /// Open annotation window for a quick access item
  func openAnnotation(for item: QuickAccessItem) {
    // Check if already open for this item
    if let existing = windowControllers[item.id] {
      existing.showWindow()
      DiagnosticLogger.shared.log(.info, .action, "Annotate window reused for item \(item.id)")
      return
    }

    guard NSScreen.screens.isEmpty == false else {
      DiagnosticLogger.shared.log(.error, .action, "Annotate open failed: no screens available")
      return
    }

    // Switch to regular app mode for Cmd+Tab visibility
    becomeRegularApp()

    let sessionData = sessionCache[item.id] ?? AnnotationSessionStore.shared.load(for: item.url)
    if let sessionData, sessionCache[item.id] == nil {
      sessionCache[item.id] = sessionData
    }
    let controller = AnnotateWindowController(item: item, sessionData: sessionData)
    windowControllers[item.id] = controller
    DiagnosticLogger.shared.log(.info, .action, "Annotate window opened for item \(item.id)")

    // Pause Quick Access countdown for this item + newer items
    QuickAccessManager.shared.pauseCountdownForEditingItem(item.id)

    // Remove from tracking when window closes
    let itemId = item.id
    if let window = controller.window {
      NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.windowControllers.removeValue(forKey: itemId)
          self?.becomeAccessoryAppIfNeeded()

          // Resume Quick Access countdown
          QuickAccessManager.shared.resumeCountdownForEditingItem(itemId)
        }
      }
    }

    controller.showWindow()
    QuickAccessManager.shared.setWindowOpen(id: item.id, isOpen: true)
  }

  /// Close all annotation windows
  func closeAll() {
    for controller in Array(windowControllers.values) {
      controller.window?.close()
    }
    windowControllers.removeAll()

    for controller in Array(manualWindowControllers.values) {
      controller.window?.close()
    }
    manualWindowControllers.removeAll()

    becomeAccessoryAppIfNeeded()
  }

  /// Check if annotation window is open for item
  func isOpen(for itemId: UUID) -> Bool {
    windowControllers[itemId] != nil
  }

  /// Open annotation window directly from a file URL (used by post-capture auto-open)
  func openAnnotation(url: URL, sessionData: AnnotationSessionData? = nil) {
    guard NSScreen.screens.isEmpty == false else {
      DiagnosticLogger.shared.log(.error, .action, "Annotate open failed: no screens available")
      return
    }

    // If Quick Access has this item, reuse it to link the annotation window
    if let existingItem = QuickAccessManager.shared.items.first(where: { $0.url == url }) {
      openAnnotation(for: existingItem)
      return
    }

    // Switch to regular app mode for Cmd+Tab visibility
    becomeRegularApp()

    let restoredSessionData = sessionData ?? AnnotationSessionStore.shared.load(for: url)
    let controller = AnnotateWindowController(url: url, sessionData: restoredSessionData)
    let controllerId = UUID()
    windowControllers[controllerId] = controller
    DiagnosticLogger.shared.log(.info, .action, "Annotate window opened for URL \(url.lastPathComponent)")

    // Remove from tracking when window closes
    if let window = controller.window {
      NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.windowControllers.removeValue(forKey: controllerId)
          self?.becomeAccessoryAppIfNeeded()
        }
      }
    }

    controller.showWindow()
  }

  /// Open empty annotation window for drag-drop workflow
  func openEmptyAnnotation() {
    guard NSScreen.screens.isEmpty == false else {
      DiagnosticLogger.shared.log(.error, .action, "Annotate open failed: no screens available")
      return
    }

    // Switch to regular app mode for Cmd+Tab visibility
    becomeRegularApp()

    let controller = AnnotateWindowController()
    let controllerId = UUID()
    manualWindowControllers[controllerId] = controller
    DiagnosticLogger.shared.log(.info, .action, "Annotate manual window opened")

    // Clear reference when window closes
    if let window = controller.window {
      NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.manualWindowControllers.removeValue(forKey: controllerId)
          self?.becomeAccessoryAppIfNeeded()
        }
      }
    }

    controller.showWindow()
    controller.handleManualOpenClipboardImageBehavior()
  }

  func openCombineImages(urls: [URL]) {
    guard urls.count >= 2, NSScreen.screens.isEmpty == false else { return }
    becomeRegularApp()

    let controller = AnnotateWindowController(combineImageURLs: urls)
    let controllerID = UUID()
    manualWindowControllers[controllerID] = controller

    if let window = controller.window {
      NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.manualWindowControllers.removeValue(forKey: controllerID)
          self?.becomeAccessoryAppIfNeeded()
        }
      }
    }

    controller.showWindow()
  }

  // MARK: - Session Cache

  /// Save annotation session data for re-editing
  func saveSessionData(
    for itemId: UUID,
    originalImageData: Data,
    annotations: [AnnotationItem],
    canvasEffects: AnnotationCanvasEffects,
    selectedCanvasPresetId: UUID? = nil,
    isSelectedCanvasPresetDirty: Bool = false,
    cropRect: CGRect?,
    isCutoutApplied: Bool = false,
    cutoutImageData: Data? = nil,
    didCutoutAutoApplyCrop: Bool = false,
    cutoutAutoAppliedCropRect: CGRect? = nil,
    embeddedImageAssetsData: [UUID: Data] = [:]
  ) {
    sessionCache[itemId] = AnnotationSessionData(
      originalImageData: originalImageData,
      annotations: annotations,
      canvasEffects: canvasEffects,
      selectedCanvasPresetId: selectedCanvasPresetId,
      isSelectedCanvasPresetDirty: isSelectedCanvasPresetDirty,
      cropRect: cropRect,
      isCutoutApplied: isCutoutApplied,
      cutoutImageData: cutoutImageData,
      didCutoutAutoApplyCrop: didCutoutAutoApplyCrop,
      cutoutAutoAppliedCropRect: cutoutAutoAppliedCropRect,
      embeddedImageAssetsData: embeddedImageAssetsData
    )
  }

  func saveSessionData(_ sessionData: AnnotationSessionData, for itemId: UUID) {
    sessionCache[itemId] = sessionData
  }

  /// Get cached session data for an item
  func getSessionData(for itemId: UUID) -> AnnotationSessionData? {
    sessionCache[itemId]
  }

  /// Clear session data when QA card is dismissed
  func clearSessionData(for itemId: UUID) {
    sessionCache.removeValue(forKey: itemId)
  }

  func makeSessionData(for state: AnnotateState, originalImageData: Data? = nil) -> AnnotationSessionData? {
    let resolvedOriginalImageData = originalImageData
      ?? state.quickAccessItemId.flatMap { sessionCache[$0]?.originalImageData }
      ?? state.sourceURL.flatMap { Self.readFileData(from: $0) }

    guard let resolvedOriginalImageData else { return nil }
    return AnnotationSessionData.snapshot(from: state, originalImageData: resolvedOriginalImageData)
  }

  private static func readFileData(from url: URL) -> Data? {
    SandboxFileAccessManager.shared.withScopedAccess(to: url) {
      try? Data(contentsOf: url)
    }
  }
}

extension AnnotationSessionData {
  static func snapshot(from state: AnnotateState, originalImageData: Data) -> AnnotationSessionData {
    let cutoutSnapshot = state.cutoutSnapshot()
    return AnnotationSessionData(
      originalImageData: originalImageData,
      annotations: state.annotations,
      canvasEffects: state.canvasEffectsSnapshot,
      selectedCanvasPresetId: state.selectedCanvasPresetId,
      isSelectedCanvasPresetDirty: state.isSelectedCanvasPresetDirty,
      cropRect: state.cropRect,
      isCutoutApplied: cutoutSnapshot.isApplied,
      cutoutImageData: cutoutSnapshot.cutoutImageData,
      didCutoutAutoApplyCrop: cutoutSnapshot.didAutoApplyCrop,
      cutoutAutoAppliedCropRect: cutoutSnapshot.autoAppliedCropRect,
      embeddedImageAssetsData: state.embeddedImageAssetsSnapshotData()
    )
  }
}
