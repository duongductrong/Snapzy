import Foundation
import PluginKitCore

public enum DevCommand {
  public static func run(_ args: Arguments) throws {
    let buildRes = try BuildCommand.run(args)
    try SignCommand.run(args, bundleURL: buildRes.bundleURL)

    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    let devPluginsDir = homeDir
      .appendingPathComponent("Library/Application Support/Snapzy/PluginData/Development", isDirectory: true)

    try FileManager.default.createDirectory(at: devPluginsDir, withIntermediateDirectories: true)

    let manifestData = try Data(contentsOf: buildRes.manifestURL)
    let manifest = try JSONDecoder().decode(PluginManifest.self, from: manifestData)

    let targetPluginURL = devPluginsDir.appendingPathComponent("\(manifest.id.rawValue).plugin", isDirectory: true)
    if FileManager.default.fileExists(atPath: targetPluginURL.path) {
      try FileManager.default.removeItem(at: targetPluginURL)
    }

    try FileManager.default.copyItem(at: buildRes.bundleURL, to: targetPluginURL)
    print("Installed plugin for development at \(targetPluginURL.path)")
    print("Snapzy will automatically discover and load the development plugin.")
  }
}
