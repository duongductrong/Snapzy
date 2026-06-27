//
//  SnapzyApp.swift
//  Snapzy
//
//  Main app entry point - Menu Bar App
//

import AppKit
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

struct AppLaunchPolicy {
  private let environment: [String: String]
  private let screenCountProvider: () -> Int

  init(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    screenCountProvider: @escaping () -> Int = { NSScreen.screens.count }
  ) {
    self.environment = environment
    self.screenCountProvider = screenCountProvider
  }

  var shouldStartInteractiveApplication: Bool {
    if isRunningUnderXCTest && !allowsInteractiveXCTestHost {
      return false
    }

    return !isHeadlessDisplaySession
  }

  var isRunningUnderXCTest: Bool {
    environment["XCTestConfigurationFilePath"] != nil
  }

  var isHeadlessDisplaySession: Bool {
    screenCountProvider() == 0
  }

  private var allowsInteractiveXCTestHost: Bool {
    environment["SNAPZY_ALLOW_INTERACTIVE_XCTEST_HOST"] == "1"
  }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
  private let launchPolicyProvider: () -> AppLaunchPolicy
  private var coordinator: AppCoordinator?
  private var pendingDeepLinkURLs: [URL] = []
  private var pendingOpenFileURLs: [URL] = []
  private var didFinishLaunching = false

  override init() {
    self.launchPolicyProvider = { AppLaunchPolicy() }
    super.init()
  }

  init(launchPolicyProvider: @escaping () -> AppLaunchPolicy) {
    self.launchPolicyProvider = launchPolicyProvider
    super.init()
  }

  func applicationWillFinishLaunching(_ notification: Notification) {
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
      forEventClass: AEEventClass(kInternetEventClass),
      andEventID: AEEventID(kAEGetURL)
    )
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard launchPolicyProvider().shouldStartInteractiveApplication else {
      return
    }

    AppIdentityManager.shared.refresh()

    guard ensureSandboxOffDataMigrationReadyForLaunch() else {
      return
    }

    guard ensureDatabaseReadyForLaunch() else {
      return
    }

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

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    guard didFinishLaunching else { return true }
    let showsMenuBarIcon = UserDefaults.standard.object(forKey: PreferencesKeys.showMenuBarIcon) as? Bool ?? true
    guard !showsMenuBarIcon else { return true }

    AppStatusBarController.shared.openPreferencesWindow(tab: .general)
    return false
  }

  private enum DatabaseLaunchRecoveryAction {
    case repair
    case reset
    case quit
  }

  private enum SandboxOffMigrationRecoveryAction {
    case retry
    case startFresh
    case quit
  }

  private func ensureSandboxOffDataMigrationReadyForLaunch() -> Bool {
    var note: String?

    while true {
      do {
        let result = try SandboxOffDataMigrationService.shared.runIfNeeded()
        if result.didRun {
          DiagnosticLogger.shared.log(
            .info,
            .lifecycle,
            "Sandbox-off data migration completed",
            context: [
              "appSupportCopied": "\(result.copiedApplicationSupportItems)",
              "appSupportSkipped": "\(result.skippedApplicationSupportItems)",
              "appSupportErrorSkipped": "\(result.errorSkippedApplicationSupportItems)",
              "preferencesImported": "\(result.importedPreferenceKeys)",
              "preferencesSkipped": "\(result.skippedPreferenceKeys)",
              "logsCopied": "\(result.copiedLogItems)",
            ]
          )
        }
        return true
      } catch {
        switch presentSandboxOffMigrationRecoveryAlert(error: error, note: note) {
        case .retry:
          note = "Previous attempt also failed. If this keeps happening, Start Fresh will let you use Snapzy without old data."
          continue

        case .startFresh:
          guard confirmMigrationSkip(error: error) else {
            note = nil
            continue
          }
          do {
            try SandboxOffDataMigrationService.shared.skipMigration()
            DiagnosticLogger.shared.log(
              .warning,
              .lifecycle,
              "Sandbox-off data migration skipped by user (Start Fresh)"
            )
            return true
          } catch {
            note = "Could not mark migration as skipped: \(error.localizedDescription)"
            continue
          }

        case .quit:
          NSApp.terminate(nil)
          return false
        }
      }
    }
  }

  private func presentSandboxOffMigrationRecoveryAlert(
    error: Error,
    note: String? = nil
  ) -> SandboxOffMigrationRecoveryAction {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "Snapzy could not migrate your existing data."

    var informativeText = """
      Snapzy needs to move data from the old sandboxed storage before opening the unsandboxed version.

      No new database was opened yet, so your existing data has not been replaced.

      Error:
      \(error.localizedDescription)
      """
    if let note {
      informativeText += "\n\n\(note)"
    }
    informativeText += "\n\nTry again if the error is temporary. Start Fresh launches Snapzy with default settings — your old data stays in the sandbox container and is not deleted."
    alert.informativeText = informativeText

    alert.addButton(withTitle: "Try Again")
    alert.addButton(withTitle: "Start Fresh…")
    alert.addButton(withTitle: "Quit Snapzy")

    switch alert.runModal() {
    case .alertFirstButtonReturn:
      return .retry
    case .alertSecondButtonReturn:
      return .startFresh
    default:
      return .quit
    }
  }

  private func confirmMigrationSkip(error: Error) -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "Start Fresh Without Old Data?"
    alert.informativeText = """
      Snapzy will launch with default settings and an empty capture history.

      Your old data remains in the sandbox container and is not deleted. You can access it manually at:
      ~/Library/Containers/\(Bundle.main.bundleIdentifier ?? "com.duongductrong.Snapzy")

      Current error:
      \(error.localizedDescription)
      """
    alert.addButton(withTitle: "Start Fresh")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }

  private func ensureDatabaseReadyForLaunch() -> Bool {
    switch DatabaseManager.prepare() {
    case .success:
      return true
    case let .failure(error):
      return presentDatabaseRecoveryFlow(startingWith: error)
    }
  }

  private func presentDatabaseRecoveryFlow(startingWith error: Error) -> Bool {
    var currentError: Error = error
    var note: String?

    while true {
      switch presentDatabaseRecoveryAlert(error: currentError, note: note) {
      case .repair:
        do {
          try DatabaseManager.attemptRepair()
          return true
        } catch {
          currentError = error
          note = "Repair did not succeed. You can reset the database after backing up the current files, or quit Snapzy."
        }

      case .reset:
        guard confirmDatabaseReset(error: currentError) else {
          note = nil
          continue
        }

        do {
          let archive = try DatabaseManager.resetDatabaseFiles()
          switch DatabaseManager.retryInitialization() {
          case .success:
            if let archiveDirectoryURL = archive.archiveDirectoryURL {
              DiagnosticLogger.shared.log(
                .warning,
                .lifecycle,
                "Database reset during launch",
                context: ["archive": archiveDirectoryURL.path]
              )
            }
            return true
          case let .failure(error):
            currentError = error
            note = "Reset moved the old database files aside, but Snapzy still could not create a fresh database."
          }
        } catch {
          currentError = error
          note = "Reset failed before Snapzy could create a fresh database."
        }

      case .quit:
        NSApp.terminate(nil)
        return false
      }
    }
  }

  private func presentDatabaseRecoveryAlert(
    error: Error,
    note: String?
  ) -> DatabaseLaunchRecoveryAction {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "Snapzy could not open its database."

    var informativeText = """
      Snapzy needs this database for capture history and cloud upload records.

      Database:
      \(DatabaseManager.defaultDatabaseURL.path)

      Error:
      \(error.localizedDescription)
      """
    if let note {
      informativeText += "\n\n\(note)"
    }
    informativeText += "\n\nTry a repair first. Reset starts with an empty database after moving the current database files into a recovery folder."
    alert.informativeText = informativeText

    alert.addButton(withTitle: "Try Repair")
    alert.addButton(withTitle: "Reset Database...")
    alert.addButton(withTitle: "Quit Snapzy")

    switch alert.runModal() {
    case .alertFirstButtonReturn:
      return .repair
    case .alertSecondButtonReturn:
      return .reset
    default:
      return .quit
    }
  }

  private func confirmDatabaseReset(error: Error) -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "Reset Snapzy Database?"
    alert.informativeText = """
      Snapzy will move the current database files into a recovery folder, then create a new empty database.

      This resets capture history and cloud upload history inside Snapzy. Capture files on disk and cloud files are not deleted.

      Database:
      \(DatabaseManager.defaultDatabaseURL.path)

      Current error:
      \(error.localizedDescription)
      """
    alert.addButton(withTitle: "Reset Database")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
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

  #if DEBUG
    var hasCoordinatorForTesting: Bool {
      coordinator != nil
    }

    var didFinishLaunchingForTesting: Bool {
      didFinishLaunching
    }

    var pendingOpenFileURLCountForTesting: Int {
      pendingOpenFileURLs.count
    }
  #endif
}
