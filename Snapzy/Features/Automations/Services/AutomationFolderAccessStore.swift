//
//  AutomationFolderAccessStore.swift
//  Snapzy
//
//  Folders picked for "Save to Folder" steps, kept as bookmarks keyed by id
//  (UserDefaults `automations.folders`). Bookmarks are device-local: TOML and
//  recipes carry the path and re-register it on import.
//

import AppKit
import Foundation

@MainActor
final class AutomationFolderAccessStore {
  static let shared = AutomationFolderAccessStore()

  private struct Entry: Codable {
    var bookmark: Data?
    var path: String
  }

  private let defaults: UserDefaults
  private let exportDirectory: @MainActor () -> URL?
  private var entries: [UUID: Entry]

  init(
    defaults: UserDefaults = .standard,
    exportDirectory: (@MainActor () -> URL?)? = nil
  ) {
    self.defaults = defaults
    self.exportDirectory = exportDirectory ?? { SandboxFileAccessManager.shared.resolvedExportDirectoryURL() }
    if let data = defaults.data(forKey: PreferencesKeys.automationFolders),
       let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
    {
      entries = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
        UUID(uuidString: key).map { ($0, value) }
      })
    } else {
      entries = [:]
    }
  }

  /// Registers `url` and returns its id. A folder already registered keeps its id.
  @discardableResult
  func register(_ url: URL) -> UUID {
    let path = url.standardizedFileURL.path
    if let existing = entries.first(where: { $0.value.path == path })?.key {
      entries[existing]?.bookmark = Self.bookmark(for: url) ?? entries[existing]?.bookmark
      persist()
      return existing
    }
    let id = UUID()
    entries[id] = Entry(bookmark: Self.bookmark(for: url), path: path)
    persist()
    return id
  }

  /// The folder's current URL, or `nil` when it no longer exists. Stale
  /// bookmarks are refreshed.
  func resolve(_ ref: AutomationFolderRef) -> URL? {
    switch ref {
    case .exportDirectory:
      return exportDirectory()
    case .bookmark(let id):
      guard let entry = entries[id] else { return nil }
      var url = URL(fileURLWithPath: entry.path, isDirectory: true)
      if let bookmark = entry.bookmark {
        var isStale = false
        if let resolved = try? URL(
          resolvingBookmarkData: bookmark,
          options: [.withSecurityScope],
          relativeTo: nil,
          bookmarkDataIsStale: &isStale
        ) {
          url = resolved
          if isStale || resolved.standardizedFileURL.path != entry.path {
            entries[id] = Entry(bookmark: Self.bookmark(for: resolved) ?? bookmark, path: resolved.standardizedFileURL.path)
            persist()
          }
        }
      }
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        return nil
      }
      return url
    }
  }

  /// Last known path, for display and TOML export (even when the folder is gone).
  func path(for ref: AutomationFolderRef) -> String? {
    switch ref {
    case .exportDirectory: exportDirectory()?.path
    case .bookmark(let id): entries[id]?.path
    }
  }

  /// `NSOpenPanel` for picking a folder; returns the registered ref.
  func chooseFolder(startingAt directory: URL? = nil) -> (ref: AutomationFolderRef, path: String)? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = L10n.Automations.chooseFolderPrompt
    panel.directoryURL = directory
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return (.bookmark(register(url)), url.standardizedFileURL.path)
  }

  private func persist() {
    let encoded = Dictionary(uniqueKeysWithValues: entries.map { ($0.key.uuidString, $0.value) })
    if let data = try? JSONEncoder().encode(encoded) {
      defaults.set(data, forKey: PreferencesKeys.automationFolders)
    }
  }

  private static func bookmark(for url: URL) -> Data? {
    (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
      ?? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
  }
}
