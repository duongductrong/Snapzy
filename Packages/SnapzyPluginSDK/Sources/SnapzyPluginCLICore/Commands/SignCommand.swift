import Foundation

public enum SignCommand {
  public static func run(_ args: Arguments, bundleURL: URL? = nil) throws {
    let targetBundleURL: URL
    if let bundleURL {
      targetBundleURL = bundleURL
    } else if let path = args.positional.first ?? args.value("bundle") {
      targetBundleURL = URL(fileURLWithPath: path)
    } else {
      let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      let distDir = rootURL.appendingPathComponent(".build/dist")
      let items = (try? FileManager.default.contentsOfDirectory(at: distDir, includingPropertiesForKeys: nil)) ?? []
      guard let first = items.first(where: { $0.pathExtension == "snapzyplugin" || $0.pathExtension == "plugin" }) else {
        throw CLIError.missingArgument("bundle-path")
      }
      targetBundleURL = first
    }

    let isAdhoc = args.has("adhoc")
    let identity = args.value("identity") ?? (isAdhoc ? "-" : "-")

    let tempEntitlements = FileManager.default.temporaryDirectory.appendingPathComponent("entitlements-\(UUID().uuidString).plist")
    try Entitlements.minimalAppSandboxPlist.write(to: tempEntitlements, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tempEntitlements) }

    var codesignArgs = [
      "--force",
      "--sign", identity,
      "--entitlements", tempEntitlements.path
    ]

    if identity != "-" {
      codesignArgs += ["--options", "runtime", "--timestamp"]
    }

    codesignArgs.append(targetBundleURL.path)

    print("Signing \(targetBundleURL.lastPathComponent) with identity '\(identity)'...")
    try ProcessRunner.run("/usr/bin/codesign", arguments: codesignArgs)
    print("Signed successfully.")
  }
}
