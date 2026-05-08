//
//  SnapzyApp.swift
//  Snapzy
//
//  Main app entry point - Menu Bar App
//

import Carbon
import SwiftUI

// MARK: - Notification Names

extension Notification.Name {
  static let showOnboarding = Notification.Name("showOnboarding")
}

@main
struct SnapzyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @ObservedObject private var themeManager = ThemeManager.shared

  init() {
    AppIdentityManager.shared.refresh()
  }

  var body: some Scene {
    // Settings Window
    Settings {
      PreferencesView()
        .preferredColorScheme(themeManager.systemAppearance)
    }
  }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
  private var coordinator: AppCoordinator?
  private var pendingDeepLinkURLs: [URL] = []
  private var pendingOpenFileURLs: [URL] = []
  private var didFinishLaunching = false

  func applicationWillFinishLaunching(_ notification: Notification) {
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
      forEventClass: AEEventClass(kInternetEventClass),
      andEventID: AEEventID(kAEGetURL)
    )
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    AppIdentityManager.shared.refresh()

    // Cleanup orphaned temp capture files from previous sessions
    TempCaptureManager.shared.cleanupOrphanedFiles()

    let coordinator = AppCoordinator(environment: AppEnvironment.live())
    self.coordinator = coordinator
    coordinator.applicationDidFinishLaunching()
    didFinishLaunching = true
    flushPendingDeepLinks()
    flushPendingOpenFileURLs()
  }

  func applicationWillTerminate(_ notification: Notification) {
    NSAppleEventManager.shared().removeEventHandler(
      forEventClass: AEEventClass(kInternetEventClass),
      andEventID: AEEventID(kAEGetURL)
    )
    coordinator?.applicationWillTerminate()
  }

  @objc private func handleGetURLEvent(
    _ event: NSAppleEventDescriptor,
    withReplyEvent replyEvent: NSAppleEventDescriptor
  ) {
    guard
      let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
      let url = URL(string: urlString)
    else {
      DiagnosticLogger.shared.log(.warning, .action, "Received invalid URL event")
      return
    }

    guard let coordinator else {
      pendingDeepLinkURLs.append(url)
      return
    }

    coordinator.handleDeepLink(url)
  }

  private func flushPendingDeepLinks() {
    guard let coordinator, !pendingDeepLinkURLs.isEmpty else { return }

    let urls = pendingDeepLinkURLs
    pendingDeepLinkURLs.removeAll()
    urls.forEach { coordinator.handleDeepLink($0) }
  }

  // MARK: - Open With (Finder right-click → Open With → Snapzy)

  /// Called when the user opens one or more image files with Snapzy from
  /// Finder's "Open With" submenu, by double-clicking a file whose default
  /// app is Snapzy, or by drag-dropping files onto the app icon in the Dock.
  ///
  /// Files declared in `CFBundleDocumentTypes` (PNG/JPEG/HEIC/HEIF/TIFF/GIF/
  /// WebP/BMP) are routed straight into the annotation editor.
  ///
  /// Note: macOS 13+ prefers `application(_:open:)` over the legacy
  /// `application(_:openFiles:)`, and the latter is silently skipped on
  /// recent OS releases. We only act on file URLs here so that the existing
  /// Apple Event handler for `snapzy://` deep links keeps working.
  func application(_ application: NSApplication, open urls: [URL]) {
    let fileURLs = urls.filter { $0.isFileURL }
    guard !fileURLs.isEmpty else { return }

    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Received open-file request",
      context: ["count": "\(fileURLs.count)"]
    )

    if didFinishLaunching {
      openImageURLs(fileURLs)
    } else {
      // Files arriving before launch finishes (e.g. a cold launch via "Open With")
      // are queued and flushed once the coordinator is ready.
      pendingOpenFileURLs.append(contentsOf: fileURLs)
    }
  }

  private func openImageURLs(_ urls: [URL]) {
    for url in urls {
      AnnotateManager.shared.openAnnotation(url: url)
    }
  }

  private func flushPendingOpenFileURLs() {
    guard !pendingOpenFileURLs.isEmpty else { return }

    let urls = pendingOpenFileURLs
    pendingOpenFileURLs.removeAll()
    openImageURLs(urls)
  }
}
