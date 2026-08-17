import Foundation
import PluginKitCore

public enum BuildCommand {
  public struct BuildResult: Sendable {
    public let bundleURL: URL
    public let executableURL: URL
    public let manifestURL: URL
  }

  @discardableResult
  public static func run(_ args: Arguments) throws -> BuildResult {
    let isDebug = args.has("debug")
    let config = isDebug ? "debug" : "release"

    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let manifestURL = rootURL.appendingPathComponent("plugin.json")
    guard FileManager.default.fileExists(atPath: manifestURL.path) else {
      throw CLIError.fileNotFound("plugin.json in current directory")
    }

    let manifestData = try Data(contentsOf: manifestURL)
    let manifest = try JSONDecoder().decode(PluginManifest.self, from: manifestData)

    var executableName = manifest.id.rawValue.split(separator: ".").last.map(String.init) ?? "Plugin"
    if case .custom(_, let options) = manifest.runtime, let name = options["executable"]?.stringValue {
      executableName = name
    }

    print("Building \(manifest.id) (\(config))...")

    var swiftBuildArgs = ["build", "-c", config]
    if let arch = args.value("arch") {
      swiftBuildArgs += ["--arch", arch]
    } else if !isDebug && args.has("universal") {
      swiftBuildArgs += ["--arch", "arm64", "--arch", "x86_64"]
    }

    try ProcessRunner.run("/usr/bin/swift", arguments: swiftBuildArgs, currentDirectory: rootURL)

    // Locate built binary
    let candidates = [
      rootURL.appendingPathComponent(".build/apple/Products/\(config.capitalized)/\(executableName)"),
      rootURL.appendingPathComponent(".build/\(config)/\(executableName)"),
      rootURL.appendingPathComponent(".build/arm64-apple-macosx/\(config)/\(executableName)")
    ]

    guard let builtBinaryURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
      throw CLIError.fileNotFound("Built executable \(executableName)")
    }

    let outDir = args.value("out").map { URL(fileURLWithPath: $0) } ?? rootURL.appendingPathComponent(".build/dist")
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let assembled = try BundleAssembler.assemble(
      pluginID: manifest.id.rawValue,
      executableBinaryURL: builtBinaryURL,
      manifestURL: manifestURL,
      outputDirectory: outDir
    )

    print("Built bundle at \(assembled.bundleURL.path)")
    return BuildResult(
      bundleURL: assembled.bundleURL,
      executableURL: assembled.executableURL,
      manifestURL: assembled.manifestURL
    )
  }
}
