import Foundation
import PluginKitCore
import SnapzyPluginAPI

enum BundleAssembler {
  struct AssemblyResult {
    let bundleURL: URL
    let executableURL: URL
    let manifestURL: URL
  }

  static func assemble(
    pluginID: String,
    executableBinaryURL: URL,
    manifestURL: URL,
    outputDirectory: URL,
    bundleExtension: String = "snapzyplugin"
  ) throws -> AssemblyResult {
    let fm = FileManager.default
    let bundleName = "\(pluginID).\(bundleExtension)"
    let bundleURL = outputDirectory.appendingPathComponent(bundleName, isDirectory: true)

    if fm.fileExists(atPath: bundleURL.path) {
      try fm.removeItem(at: bundleURL)
    }

    let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
    let macosURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
    let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

    try fm.createDirectory(at: macosURL, withIntermediateDirectories: true)
    try fm.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

    // Copy executable
    let targetExecutableURL = macosURL.appendingPathComponent(executableBinaryURL.lastPathComponent)
    try fm.copyItem(at: executableBinaryURL, to: targetExecutableURL)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetExecutableURL.path)

    // Copy manifest
    let targetManifestURL = resourcesURL.appendingPathComponent("plugin.json")
    try fm.copyItem(at: manifestURL, to: targetManifestURL)

    // Write Info.plist
    let infoPlistContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>\(pluginID)</string>
    <key>CFBundleName</key>
    <string>\(executableBinaryURL.lastPathComponent)</string>
    <key>CFBundleExecutable</key>
    <string>\(executableBinaryURL.lastPathComponent)</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
"""
    let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
    try Data(infoPlistContent.utf8).write(to: infoPlistURL)

    return AssemblyResult(
      bundleURL: bundleURL,
      executableURL: targetExecutableURL,
      manifestURL: targetManifestURL
    )
  }
}
