//
//  VideoEditorManager.swift
//  Snapzy
//
//  Singleton manager for video editor windows (placeholder)
//

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Manages video editor window instances
@MainActor
final class VideoEditorManager {
  static let shared = VideoEditorManager()

  private var windowControllers: [UUID: VideoEditorWindowController] = [:]
  private var urlWindowControllers: [URL: VideoEditorWindowController] = [:]
  private var projectWindowControllers: [URL: VideoEditorWindowController] = [:]
  private var openingProjectKeys: Set<URL> = []
  private var emptyWindowController: VideoEditorWindowController?
  private var observers: [UUID: NSObjectProtocol] = [:]
  private var urlObservers: [URL: NSObjectProtocol] = [:]
  private var projectObservers: [URL: NSObjectProtocol] = [:]
  private var emptyWindowObserver: NSObjectProtocol?
  private var sessionCache: [UUID: VideoEditorSessionData] = [:]
  private var urlSessionCache: [URL: VideoEditorSessionData] = [:]

  private init() {}

  // MARK: - Activation Policy Management

  /// Check if any video editor windows are open
  var hasOpenWindows: Bool {
    !windowControllers.isEmpty
      || !urlWindowControllers.isEmpty
      || !projectWindowControllers.isEmpty
      || emptyWindowController != nil
  }

  /// Switch to regular app mode (visible in Dock + Cmd+Tab)
  private func becomeRegularApp() {
    if NSApp.activationPolicy() != .regular {
      NSApp.setActivationPolicy(.regular)
    }
  }

  /// Switch back to accessory mode (menu bar only) if no windows open
  private func becomeAccessoryAppIfNeeded() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      guard !hasOpenWindows else { return }
      guard !AnnotateManager.shared.hasOpenWindows else { return }
      NSApp.revertActivationPolicyToAccessoryIfNeeded()
    }
  }

  /// Open video editor for a quick access item
  func openEditor(for item: QuickAccessItem) {
    guard item.isVideo else { return }

    // Reuse existing window if open
    if let existing = windowControllers[item.id] {
      DiagnosticLogger.shared.log(.debug, .editor, "Video editor reused", context: ["itemId": item.id.uuidString])
      existing.showWindow()
      return
    }

    // Switch to regular app mode for Cmd+Tab visibility
    becomeRegularApp()

    DiagnosticLogger.shared.log(.info, .editor, "Opening video editor", context: ["itemId": item.id.uuidString])

    let sessionData = sessionCache[item.id] ?? VideoEditorSessionStore.shared.load(for: item.url)
    if let sessionData, sessionCache[item.id] == nil {
      sessionCache[item.id] = sessionData
    }
    let controller = VideoEditorWindowController(item: item, sessionData: sessionData)
    windowControllers[item.id] = controller

    // Pause Quick Access countdown for this item + newer items
    QuickAccessManager.shared.pauseCountdownForEditingItem(item.id)

    // Remove from tracking when window closes
    let itemId = item.id
    if let window = controller.window {
      let observer = NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.cleanupWindow(for: itemId)
          self?.becomeAccessoryAppIfNeeded()

          // Resume Quick Access countdown
          QuickAccessManager.shared.resumeCountdownForEditingItem(itemId)
        }
      }
      observers[itemId] = observer
    }

    controller.showWindow()
    QuickAccessManager.shared.setWindowOpen(id: item.id, isOpen: true)
  }

  /// Open a self-contained `.snapzy` project package asynchronously off the main thread.
  func openProject(at packageURL: URL) {
    let projectKey = SnapzyProjectPackage.normalizedPackageURL(packageURL)

    if let existing = projectWindowControllers[projectKey] {
      DiagnosticLogger.shared.log(
        .debug,
        .editor,
        "Video editor project reused",
        context: ["project": projectKey.lastPathComponent]
      )
      existing.showWindow()
      return
    }

    guard !openingProjectKeys.contains(projectKey) else { return }
    openingProjectKeys.insert(projectKey)

    Task { @MainActor [weak self] in
      guard let self else { return }
      defer { openingProjectKeys.remove(projectKey) }

      do {
        let loadedProject = try await SnapzyProjectPackage.loadAsync(from: projectKey)
        presentLoadedProject(loadedProject, key: projectKey)
      } catch {
        DiagnosticLogger.shared.logError(
          .editor,
          error,
          "Failed to open .snapzy project package",
          context: ["project": projectKey.lastPathComponent]
        )
        presentOpenProjectError(error)
      }
    }
  }

  /// Synchronous project open helper for deterministic unit tests.
  @discardableResult
  func openProjectSync(at packageURL: URL) -> VideoEditorWindowController? {
    let projectKey = SnapzyProjectPackage.normalizedPackageURL(packageURL)
    if let existing = projectWindowControllers[projectKey] {
      existing.showWindow()
      return existing
    }
    do {
      let loaded = try SnapzyProjectPackage.load(from: projectKey)
      return presentLoadedProject(loaded, key: projectKey)
    } catch {
      DiagnosticLogger.shared.logError(
        .editor,
        error,
        "Failed to open .snapzy project package",
        context: ["project": projectKey.lastPathComponent]
      )
      presentOpenProjectError(error)
      return nil
    }
  }

  @discardableResult
  private func presentLoadedProject(
    _ loadedProject: SnapzyProjectPackage.LoadedProject,
    key projectKey: URL
  ) -> VideoEditorWindowController {
    if let existing = projectWindowControllers[projectKey] {
      existing.showWindow()
      return existing
    }
    becomeRegularApp()
    DiagnosticLogger.shared.log(
      .info,
      .editor,
      "Opening .snapzy video project",
      context: ["project": projectKey.lastPathComponent]
    )
    let controller = VideoEditorWindowController(project: loadedProject)
    registerProjectAssociation(controller: controller, packageURL: projectKey)
    controller.showWindow()
    return controller
  }

  /// Associate an already-open `VideoEditorWindowController` with a newly saved or renamed `.snapzy` package.
  func registerProjectAssociation(
    controller: VideoEditorWindowController,
    packageURL: URL,
    previousPackageURL: URL? = nil
  ) {
    let key = SnapzyProjectPackage.normalizedPackageURL(packageURL)
    if let previousPackageURL {
      let prevKey = SnapzyProjectPackage.normalizedPackageURL(previousPackageURL)
      if prevKey != key {
        cleanupProjectWindow(for: prevKey)
      }
    }
    guard projectWindowControllers[key] !== controller else { return }

    cleanupProjectWindow(for: key)
    projectWindowControllers[key] = controller

    if let window = controller.window {
      let observer = NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.cleanupProjectWindow(for: key)
          self?.becomeAccessoryAppIfNeeded()
        }
      }
      projectObservers[key] = observer
    }
  }

  /// Present a native Open panel allowing `.snapzy` projects alongside video and GIF files (`⌘O`).
  func promptOpenVideoOrProject(from parentWindow: NSWindow? = nil) {
    let panel = NSOpenPanel()
    panel.title = L10n.VideoEditor.projectOpenPanelTitle
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.treatsFilePackagesAsDirectories = false
    panel.allowedContentTypes = [
      SnapzyProjectPackage.projectUTType,
      .movie,
      .video,
      .quickTimeMovie,
      .mpeg4Movie,
      .gif,
    ]

    let handleSelection: (NSApplication.ModalResponse) -> Void = { [weak self] response in
      guard let self, response == .OK, let selectedURL = panel.url else { return }
      if let emptyWindow = emptyWindowController?.window, emptyWindow === parentWindow {
        emptyWindowController = nil
        emptyWindow.close()
      }
      if SnapzyProjectPackage.isProjectURL(selectedURL) {
        openProject(at: selectedURL)
      } else {
        openEditor(for: selectedURL)
      }
    }

    if let parentWindow {
      panel.beginSheetModal(for: parentWindow, completionHandler: handleSelection)
    } else {
      panel.begin(completionHandler: handleSelection)
    }
  }

  private func presentOpenProjectError(_ error: Error) {
    guard AppLaunchPolicy().shouldStartInteractiveApplication,
          ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    else { return }
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = L10n.VideoEditor.projectOpenFailedTitle
    alert.informativeText = error.localizedDescription
    alert.addButton(withTitle: L10n.Common.ok)
    alert.runModal()
  }

  /// Open video editor for a video URL directly
  func openEditor(for url: URL, originalURL: URL? = nil) {
    if let originalURL, SnapzyProjectPackage.isProjectURL(originalURL) {
      openProject(at: originalURL)
      return
    }
    if SnapzyProjectPackage.isProjectURL(url) {
      openProject(at: url)
      return
    }
    // Validate it's a video file
    guard isVideoFile(url) else { return }

    // If Quick Access has this item, reuse it to link the video editor window
    if let existingItem = QuickAccessManager.shared.items
      .first(where: { $0.url.standardizedFileURL.path == url.standardizedFileURL.path }) {
      openEditor(for: existingItem)
      return
    }

    // Reuse existing window if open
    let sessionKey = url.standardizedFileURL
    if let existing = urlWindowControllers[sessionKey] {
      DiagnosticLogger.shared.log(.debug, .editor, "Video editor reused", context: ["file": url.lastPathComponent])
      existing.showWindow()
      return
    }

    // Switch to regular app mode for Cmd+Tab visibility
    becomeRegularApp()

    DiagnosticLogger.shared.log(
      .info,
      .editor,
      "Opening video editor for URL",
      context: ["file": url.lastPathComponent]
    )

    let sessionLookupURL = originalURL ?? url
    let sessionData = urlSessionCache[sessionKey]
      ?? VideoEditorSessionStore.shared.load(for: sessionLookupURL)
    if let sessionData, urlSessionCache[sessionKey] == nil {
      urlSessionCache[sessionKey] = sessionData
    }
    let controller = VideoEditorWindowController(
      url: url,
      originalURL: originalURL,
      sessionData: sessionData
    )
    urlWindowControllers[sessionKey] = controller

    // Remove from tracking when window closes
    if let window = controller.window {
      let observer = NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.cleanupURLWindow(for: sessionKey)
          self?.becomeAccessoryAppIfNeeded()
        }
      }
      urlObservers[sessionKey] = observer
    }

    controller.showWindow()
  }

  /// Open video editor with empty state for drag & drop
  func openEmptyEditor() {
    // Reuse existing empty window if open
    if let existing = emptyWindowController {
      DiagnosticLogger.shared.log(.debug, .editor, "Empty video editor reused")
      existing.showWindow()
      return
    }

    // Switch to regular app mode for Cmd+Tab visibility
    becomeRegularApp()

    DiagnosticLogger.shared.log(.info, .editor, "Opening empty video editor")

    let controller = VideoEditorWindowController()
    controller.onVideoLoaded = { [weak self] url, originalURL in
      self?.handleVideoLoaded(url: url, originalURL: originalURL, from: controller)
    }
    emptyWindowController = controller

    if let previousObserver = emptyWindowObserver {
      NotificationCenter.default.removeObserver(previousObserver)
      emptyWindowObserver = nil
    }
    if let window = controller.window {
      emptyWindowObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          if let obs = self?.emptyWindowObserver {
            NotificationCenter.default.removeObserver(obs)
            self?.emptyWindowObserver = nil
          }
          self?.emptyWindowController = nil
          self?.becomeAccessoryAppIfNeeded()
        }
      }
    }

    controller.showWindow()
  }

  /// Validate if URL is a video or GIF file
  private func isVideoFile(_ url: URL) -> Bool {
    guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
      // Fallback: check extension directly for GIF
      return url.pathExtension.lowercased() == "gif"
    }
    return type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .gif)
  }

  /// Handle video or `.snapzy` project loaded in empty editor
  private func handleVideoLoaded(url: URL, originalURL: URL?, from controller: VideoEditorWindowController) {
    // Close empty window and open proper editor
    emptyWindowController = nil
    controller.window?.close()
    if let originalURL, SnapzyProjectPackage.isProjectURL(originalURL) {
      openProject(at: originalURL)
    } else if SnapzyProjectPackage.isProjectURL(url) {
      openProject(at: url)
    } else {
      openEditor(for: url, originalURL: originalURL)
    }
  }

  private func cleanupURLWindow(for url: URL) {
    if let observer = urlObservers[url] {
      NotificationCenter.default.removeObserver(observer)
      urlObservers.removeValue(forKey: url)
    }
    urlWindowControllers.removeValue(forKey: url)
  }

  private func cleanupProjectWindow(for packageURL: URL) {
    if let observer = projectObservers[packageURL] {
      NotificationCenter.default.removeObserver(observer)
      projectObservers.removeValue(forKey: packageURL)
    }
    projectWindowControllers.removeValue(forKey: packageURL)
  }

  // MARK: - Session Cache

  func saveSessionData(_ sessionData: VideoEditorSessionData, for itemId: UUID) {
    sessionCache[itemId] = sessionData
  }

  func getSessionData(for itemId: UUID) -> VideoEditorSessionData? {
    sessionCache[itemId]
  }

  func clearSessionData(for itemId: UUID) {
    sessionCache.removeValue(forKey: itemId)
  }

  func saveSessionData(_ sessionData: VideoEditorSessionData, for url: URL) {
    urlSessionCache[url.standardizedFileURL] = sessionData
  }

  func getSessionData(for url: URL) -> VideoEditorSessionData? {
    urlSessionCache[url.standardizedFileURL]
  }

  func clearSessionData(for url: URL) {
    urlSessionCache.removeValue(forKey: url.standardizedFileURL)
  }

  /// Close all video editor windows
  func closeAll() {
    // Remove all observers
    for (_, observer) in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers.removeAll()

    for (_, observer) in urlObservers {
      NotificationCenter.default.removeObserver(observer)
    }
    urlObservers.removeAll()

    for (_, observer) in projectObservers {
      NotificationCenter.default.removeObserver(observer)
    }
    projectObservers.removeAll()

    // Close all windows
    for controller in windowControllers.values {
      controller.window?.close()
    }
    windowControllers.removeAll()

    for controller in urlWindowControllers.values {
      controller.window?.close()
    }
    urlWindowControllers.removeAll()

    for controller in projectWindowControllers.values {
      controller.window?.close()
    }
    projectWindowControllers.removeAll()

    emptyWindowController?.window?.close()
    emptyWindowController = nil

    becomeAccessoryAppIfNeeded()
  }

  private func cleanupWindow(for itemId: UUID) {
    if let observer = observers[itemId] {
      NotificationCenter.default.removeObserver(observer)
      observers.removeValue(forKey: itemId)
    }
    windowControllers.removeValue(forKey: itemId)
    DiagnosticLogger.shared.log(.debug, .editor, "Video editor window closed", context: ["itemId": itemId.uuidString])
  }
}
