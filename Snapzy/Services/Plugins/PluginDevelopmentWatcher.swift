import AppKit
import Foundation
import SnapzyPluginAPI

/// "Load Plugin from Folder…" with live reload — the adoption lever. A loaded
/// folder is copied into the development area (so discovery is uniform), the
/// original is watched, and changes re-copy with a debounce. Combined with the
/// request inspector this turns "my plugin doesn't work" into a self-service
/// fix.
@MainActor
final class PluginDevelopmentWatcher {
  static let shared = PluginDevelopmentWatcher()

  /// Where development plugins are staged. One constant, in `PluginDirectory`,
  /// because the watcher writes here and `SnapzyHostConfiguration` scans here —
  /// two copies of this path is two places for discovery to silently miss them.
  var stagingDirectory: URL {
    PluginDirectory.developmentPluginsDirectory
  }

  private var watchers: [String: DispatchSourceFileSystemObject] = [:]
  private var origins: [String: URL] = [:]
  private var reloadTimers: [String: Task<Void, Never>] = [:]

  private init() {}

  enum LoadError: Error, CustomStringConvertible {
    case folderMissing
    case noManifest
    case invalidID
    case missingExecutable(String)

    var description: String {
      switch self {
      case .folderMissing: return "The folder does not exist."
      case .noManifest: return "No readable plugin.json in this folder."
      case .invalidID: return "The plugin id is not a valid identifier."
      case .missingExecutable(let executable):
        return "The manifest points at executable “\(executable)”, which is not in this folder. Run `snapzy-plugin build` and load it again."
      }
    }
  }

  /// Registers a folder as a development plugin and stages it. Returns the
  /// plugin's display name.
  @discardableResult
  func load(from folder: URL) async throws -> String {
    guard FileManager.default.fileExists(atPath: folder.path) else {
      throw LoadError.folderMissing
    }
    guard let manifestURL = PluginBundleLayout.manifestURL(inBundleAt: folder),
      let manifest = try? PluginManifest.load(from: manifestURL)
    else {
      throw LoadError.noManifest
    }
    guard PluginDirectory.isValidPluginID(manifest.id.rawValue) else {
      throw LoadError.invalidID
    }

    var executableName = manifest.id.rawValue.split(separator: ".").last.map(String.init) ?? "Plugin"
    if case .custom(_, let options) = manifest.runtime, let name = options["executable"]?.stringValue {
      executableName = name
    }
    let execURL = folder.appendingPathComponent("Contents/MacOS/\(executableName)")
    let rootExecURL = folder.appendingPathComponent(executableName)
    let resolvedExecURL = FileManager.default.fileExists(atPath: execURL.path) ? execURL : rootExecURL

    guard FileManager.default.isExecutableFile(atPath: resolvedExecURL.path) else {
      throw LoadError.missingExecutable(executableName)
    }

    try stage(folder, as: manifest.id.rawValue)
    await PluginTierStore.shared.setTier(.sideloaded, for: manifest.id.rawValue)
    await PluginHostController.shared.restart()
    await watch(origin: folder, pluginID: manifest.id.rawValue)
    return manifest.displayName
  }

  /// Removes a development plugin: its watcher *and* its staged copy.
  ///
  /// Deleting the staged bundle is the part that matters. Discovery reads the
  /// staging directory on every restart, so a copy left behind means Remove
  /// appears to work and the plugin is back on the next launch.
  func remove(pluginID: String) async {
    watchers[pluginID]?.cancel()
    watchers[pluginID] = nil
    origins[pluginID] = nil
    reloadTimers[pluginID]?.cancel()
    reloadTimers[pluginID] = nil

    guard PluginDirectory.isValidPluginID(pluginID) else { return }
    try? FileManager.default.removeItem(
      at: stagingDirectory.appendingPathComponent("\(pluginID).plugin", isDirectory: true)
    )
  }

  /// All currently loaded development origins.
  func loadedOrigins() -> [String: URL] { origins }

  // MARK: - Staging + watching

  private func stage(_ folder: URL, as pluginID: String) throws {
    let destination = stagingDirectory
      .appendingPathComponent("\(pluginID).plugin", isDirectory: true)
    try FileManager.default.createDirectory(
      at: stagingDirectory, withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.copyItem(at: folder, to: destination)
  }

  private func watch(origin: URL, pluginID: String) async {
    // Stop any existing watcher for this plugin.
    watchers[pluginID]?.cancel()
    origins[pluginID] = origin

    let descriptor = open(origin.path, O_EVTONLY)
    guard descriptor >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .delete, .rename, .attrib],
      queue: .main
    )
    source.setEventHandler { [weak self] in
      self?.scheduleReload(pluginID: pluginID)
    }
    source.setCancelHandler {
      close(descriptor)
    }
    source.resume()
    watchers[pluginID] = source
  }

  /// 300 ms debounce: rapid saves coalesce into one reload.
  private func scheduleReload(pluginID: String) {
    reloadTimers[pluginID]?.cancel()
    reloadTimers[pluginID] = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(300))
      guard let self, let origin = self.origins[pluginID] else { return }
      guard FileManager.default.fileExists(atPath: origin.path) else {
        // The origin folder was deleted: drop the staged copy too.
        try? FileManager.default.removeItem(
          at: self.stagingDirectory.appendingPathComponent("\(pluginID).plugin", isDirectory: true)
        )
        return
      }
      do {
        try self.stage(origin, as: pluginID)
        await PluginHostController.shared.restart()
      } catch {
        DiagnosticLogger.shared.log(.warning, .plugin, "Reload of “\(pluginID)” failed: \(error)")
      }
    }
  }
}
