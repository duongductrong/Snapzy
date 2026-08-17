import Foundation
import PluginKitCore
import PluginKitHost
import SnapzyPluginAPI

struct SnapzyProcessRuntime: PluginRuntime {
  let runtimeID: RuntimeID = .process

  private let supervisor: PluginProcessSupervisor

  init(supervisor: PluginProcessSupervisor) {
    self.supervisor = supervisor
  }

  func canHost(_ manifest: PluginManifest, at location: PluginLocation) -> Bool {
    guard case .bundle(let url) = location else { return false }
    let executableName: String
    switch manifest.runtime {
    case .custom(let id, let options):
      guard id == .process, let exec = options["executable"]?.stringValue else { return false }
      executableName = exec
    default:
      return false
    }

    let bundleExecURL = url.appendingPathComponent("Contents/MacOS/\(executableName)", isDirectory: false)
    let rootExecURL = url.appendingPathComponent(executableName, isDirectory: false)
    let resolvedExecURL = FileManager.default.fileExists(atPath: bundleExecURL.path) ? bundleExecURL : rootExecURL

    guard FileManager.default.isExecutableFile(atPath: resolvedExecURL.path) else {
      return false
    }
    return true
  }

  func load(
    _ plugin: ResolvedPlugin,
    context: any PluginContext
  ) async throws -> any PluginInstance {
    guard case .bundle(let bundleURL) = plugin.location else {
      throw PluginKitError.runtime(.unsupportedLocation(plugin.manifest.id))
    }
    guard case .custom(let id, let options) = plugin.manifest.runtime,
          id == .process,
          let executableName = options["executable"]?.stringValue else {
      throw PluginKitError.runtime(.noRuntimeAvailable(plugin.manifest.id, requested: .process))
    }

    let bundleExecURL = bundleURL.appendingPathComponent("Contents/MacOS/\(executableName)", isDirectory: false)
    let rootExecURL = bundleURL.appendingPathComponent(executableName, isDirectory: false)
    let executableURL = FileManager.default.fileExists(atPath: bundleExecURL.path) ? bundleExecURL : rootExecURL

    guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
      throw PluginKitError.misconfigured(reason: "Plugin executable '\(executableName)' is not found or not executable.")
    }

    // Verify signature
    _ = try PluginSignatureVerifier.verify(executableURL: executableURL, trustLevel: plugin.trust)

    return ProcessPluginInstance(
      plugin: plugin,
      executableURL: executableURL,
      supervisor: supervisor
    )
  }
}
