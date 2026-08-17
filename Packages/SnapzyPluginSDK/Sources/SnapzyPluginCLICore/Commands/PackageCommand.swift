import CryptoKit
import Foundation
import PluginKitCore

public enum PackageCommand {
  public static func run(_ args: Arguments) throws {
    let buildRes = try BuildCommand.run(args)
    try SignCommand.run(args, bundleURL: buildRes.bundleURL)

    let manifestData = try Data(contentsOf: buildRes.manifestURL)
    let manifest = try JSONDecoder().decode(PluginManifest.self, from: manifestData)

    let distDir = buildRes.bundleURL.deletingLastPathComponent()
    let zipName = "\(manifest.id.rawValue)-\(manifest.version).zip"
    let zipURL = distDir.appendingPathComponent(zipName)

    if FileManager.default.fileExists(atPath: zipURL.path) {
      try FileManager.default.removeItem(at: zipURL)
    }

    print("Compressing \(buildRes.bundleURL.lastPathComponent) to \(zipName)...")
    try ProcessRunner.run(
      "/usr/bin/ditto",
      arguments: [
        "-c", "-k",
        "--keepParent",
        buildRes.bundleURL.path,
        zipURL.path
      ]
    )

    let zipData = try Data(contentsOf: zipURL)
    let hash = SHA256.hash(data: zipData)
    let sha256String = hash.map { String(format: "%02x", $0) }.joined()

    print("\nPackage created successfully:")
    print("  File: \(zipURL.path)")
    print("  Size: \(zipData.count) bytes")
    print("  SHA256: \(sha256String)")
    print("\nPaste-ready index entry:")
    print("""
{
  "id": "\(manifest.id.rawValue)",
  "name": "\(manifest.displayName)",
  "version": "\(manifest.version)",
  "minAppVersion": "1.0.0",
  "architectures": ["arm64", "x86_64"],
  "downloadURL": "https://plugins.snapzy.app/packages/\(zipName)",
  "sha256": "\(sha256String)"
}
""")
  }
}
