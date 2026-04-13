//
//  SandboxFileAccessManager.swift
//  Snapzy
//
//  Handles export directory persistence and security-scoped access for sandbox mode.
//

import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "SandboxFileAccess")

@MainActor
final class SandboxFileAccessManager {
  static let shared = SandboxFileAccessManager()

  private let defaults = UserDefaults.standard
  private var didPromptForMissingExportPermissionThisSession = false
  private var didAttemptLegacyMigrationThisSession = false

  private init() {}

  struct ScopedAccess: Sendable {
    let url: URL
    private let accessURL: URL
    private let didStartAccessing: Bool

    init(url: URL, accessURL: URL, didStartAccessing: Bool) {
      self.url = url
      self.accessURL = accessURL
      self.didStartAccessing = didStartAccessing
    }

    nonisolated func stop() {
      if didStartAccessing {
        accessURL.stopAccessingSecurityScopedResource()
      }
    }
  }

  var defaultExportDirectory: URL {
    if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
      return desktop.appendingPathComponent("Snapzy", isDirectory: true)
    }
    return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Snapzy", isDirectory: true)
  }

  func ensureExportLocationInitialized() {
    if defaults.string(forKey: PreferencesKeys.exportLocation)?.isEmpty != false {
      defaults.set(defaultExportDirectory.path, forKey: PreferencesKeys.exportLocation)
    }
    migrateLegacyPathBookmarkIfPossible()
  }

  var exportLocationPath: String {
    ensureExportLocationInitialized()
    return defaults.string(forKey: PreferencesKeys.exportLocation) ?? defaultExportDirectory.path
  }

  var exportLocationURL: URL {
    URL(fileURLWithPath: exportLocationPath, isDirectory: true)
  }

  var hasPersistedExportPermission: Bool {
    ensureExportLocationInitialized()
    guard let bookmarkURL = resolveExportBookmarkURL(removeInvalidBookmark: true) else {
      return false
    }

    let didStart = bookmarkURL.startAccessingSecurityScopedResource()
    if didStart {
      bookmarkURL.stopAccessingSecurityScopedResource()
      return true
    }

    // A failed startAccessing means the persisted scope is unusable.
    // Require user to re-grant via folder picker.
    return false
  }

  func resolvedExportDirectoryURL() -> URL {
    if let bookmarkURL = resolveExportBookmarkURL(removeInvalidBookmark: true) {
      return bookmarkURL
    }
    return exportLocationURL
  }

  @discardableResult
  func setExportDirectory(_ url: URL) -> Bool {
    let normalizedURL = url.standardizedFileURL

    do {
      let bookmarkData = try normalizedURL.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      defaults.set(normalizedURL.path, forKey: PreferencesKeys.exportLocation)
      defaults.set(bookmarkData, forKey: PreferencesKeys.exportLocationBookmark)
      didPromptForMissingExportPermissionThisSession = false
      return true
    } catch {
      return false
    }
  }

  @discardableResult
  func chooseExportDirectory(
    message: String = L10n.FileAccess.chooseCapturesFolderMessage,
    prompt: String = L10n.FileAccess.grantAccessPrompt,
    directoryURL: URL? = nil
  ) -> URL? {
    ensureExportLocationInitialized()

    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = message
    panel.prompt = prompt
    panel.directoryURL = directoryURL ?? defaultExportDirectory

    if panel.runModal() == .OK, let selectedURL = panel.url {
      guard setExportDirectory(selectedURL) else {
        showBookmarkSaveFailedAlert()
        return nil
      }
      return selectedURL.standardizedFileURL
    }
    return nil
  }

  func ensureExportDirectoryForOperation(promptMessage: String) -> URL? {
    ensureExportLocationInitialized()

    if hasPersistedExportPermission {
      return resolvedExportDirectoryURL()
    }

    // If user dismissed runtime picker once in this app session, avoid re-prompt loops.
    guard !didPromptForMissingExportPermissionThisSession else {
      return nil
    }
    didPromptForMissingExportPermissionThisSession = true

    return chooseExportDirectory(
      message: promptMessage,
      prompt: L10n.FileAccess.chooseFolderPrompt,
      directoryURL: resolvedExportDirectoryURL()
    )
  }

  func beginAccessingURL(_ targetURL: URL) -> ScopedAccess {
    let scopeURL = resolveURLForScopedAccess(targetURL)
    var accessURL = scopeURL
    var didStartAccessing = scopeURL.startAccessingSecurityScopedResource()

    // Fallback to target URL if bookmark-scope start failed.
    if !didStartAccessing && scopeURL.standardizedFileURL != targetURL.standardizedFileURL {
      didStartAccessing = targetURL.startAccessingSecurityScopedResource()
      if didStartAccessing {
        accessURL = targetURL
      }
    }

    if !didStartAccessing && isRunningSandboxed {
      logger.error(
        "Failed to start security-scoped access for target: \(targetURL.path, privacy: .public)"
      )
    }

    return ScopedAccess(url: targetURL, accessURL: accessURL, didStartAccessing: didStartAccessing)
  }

  func withScopedAccess<T>(to targetURL: URL, _ operation: () throws -> T) rethrows -> T {
    let access = beginAccessingURL(targetURL)
    defer { access.stop() }
    return try operation()
  }

  private func resolveURLForScopedAccess(_ targetURL: URL) -> URL {
    guard let exportBookmarkURL = resolveExportBookmarkURL(removeInvalidBookmark: true) else {
      return targetURL
    }

    let targetPath = targetURL.standardizedFileURL.resolvingSymlinksInPath().path
    let bookmarkPath = exportBookmarkURL.standardizedFileURL.resolvingSymlinksInPath().path

    if targetPath == bookmarkPath || targetPath.hasPrefix(bookmarkPath + "/") {
      return exportBookmarkURL
    }
    return targetURL
  }

  private func resolveExportBookmarkURL(removeInvalidBookmark: Bool) -> URL? {
    guard let bookmarkData = defaults.data(forKey: PreferencesKeys.exportLocationBookmark) else {
      return nil
    }

    var isStale = false
    do {
      let url = try URL(
        resolvingBookmarkData: bookmarkData,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      ).standardizedFileURL

      if isStale {
        _ = setExportDirectory(url)
      }

      return url
    } catch {
      if removeInvalidBookmark {
        defaults.removeObject(forKey: PreferencesKeys.exportLocationBookmark)
      }
      return nil
    }
  }

  private func migrateLegacyPathBookmarkIfPossible() {
    if didAttemptLegacyMigrationThisSession {
      return
    }
    didAttemptLegacyMigrationThisSession = true

    if defaults.data(forKey: PreferencesKeys.exportLocationBookmark) != nil {
      return
    }

    let legacyPath = defaults.string(forKey: PreferencesKeys.exportLocation) ?? ""
    if legacyPath.isEmpty {
      return
    }

    let legacyURL = URL(fileURLWithPath: legacyPath, isDirectory: true).standardizedFileURL
    if FileManager.default.fileExists(atPath: legacyURL.path) {
      _ = setExportDirectory(legacyURL)
    }
  }

  private func showBookmarkSaveFailedAlert() {
    let alert = NSAlert()
    alert.messageText = L10n.FileAccess.bookmarkSaveFailedTitle
    alert.informativeText = L10n.FileAccess.bookmarkSaveFailedMessage
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.Common.ok)
    alert.runModal()
  }

  private var isRunningSandboxed: Bool {
    ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
  }
}
