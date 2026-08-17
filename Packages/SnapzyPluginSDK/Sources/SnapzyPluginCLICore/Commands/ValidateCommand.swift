import Foundation
import PluginKitCore
import SnapzyPluginAPI

public enum ValidateCommand {
  public static func run(_ args: Arguments) throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let bundlePath = args.positional.first ?? args.value("bundle")

    let targetBundleURL: URL
    if let bundlePath {
      targetBundleURL = URL(fileURLWithPath: bundlePath)
    } else {
      let distDir = rootURL.appendingPathComponent(".build/dist")
      let items = (try? FileManager.default.contentsOfDirectory(at: distDir, includingPropertiesForKeys: nil)) ?? []
      if let first = items.first(where: { $0.pathExtension == "snapzyplugin" || $0.pathExtension == "plugin" }) {
        targetBundleURL = first
      } else {
        // Fallback to validating local plugin.json
        let manifestURL = rootURL.appendingPathComponent("plugin.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
          throw CLIError.fileNotFound("plugin.json or bundle")
        }
        try validateManifest(at: manifestURL)
        print("Manifest validation passed.")
        return
      }
    }

    try validateBundle(at: targetBundleURL)
    print("Bundle validation passed for \(targetBundleURL.lastPathComponent)")
  }

  public static func validateManifest(at manifestURL: URL) throws {
    let data = try Data(contentsOf: manifestURL)
    if data.count > 64 * 1024 {
      throw CLIError.validationFailed("Manifest exceeds 64KB cap (size: \(data.count) bytes)")
    }
    let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
    guard !manifest.id.rawValue.isEmpty else {
      throw CLIError.validationFailed("Plugin ID is empty")
    }
    guard manifest.runtime.preferredRuntime == .process || manifest.runtime.preferredRuntime == RuntimeID("process") else {
      throw CLIError.validationFailed("Runtime must be custom 'process'")
    }
  }

  public static func validateBundle(at bundleURL: URL) throws {
    let fm = FileManager.default
    guard fm.fileExists(atPath: bundleURL.path) else {
      throw CLIError.fileNotFound("Bundle at \(bundleURL.path)")
    }

    let manifestURL = bundleURL.appendingPathComponent("Contents/Resources/plugin.json")
    guard fm.fileExists(atPath: manifestURL.path) else {
      throw CLIError.validationFailed("Missing Contents/Resources/plugin.json in bundle")
    }
    try validateManifest(at: manifestURL)

    let manifestData = try Data(contentsOf: manifestURL)
    let manifest = try JSONDecoder().decode(PluginManifest.self, from: manifestData)

    var executableName = manifest.id.rawValue.split(separator: ".").last.map(String.init) ?? "Plugin"
    if case .custom(_, let options) = manifest.runtime, let name = options["executable"]?.stringValue {
      executableName = name
    }

    let execURL = bundleURL.appendingPathComponent("Contents/MacOS/\(executableName)")
    guard fm.isExecutableFile(atPath: execURL.path) else {
      throw CLIError.validationFailed("Executable not found or not executable at \(execURL.path)")
    }

    // Verify codesign
    let verifyRes = try? ProcessRunner.run("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", bundleURL.path])
    if verifyRes?.exitCode != 0 {
      print("Warning: Code signature verification failed or unsigned.")
    }
  }
}
