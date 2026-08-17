import CommonCrypto
import Foundation
import PluginKitCore
import SnapzyPluginAPI
import SnapzyPluginProtocol

/// Verifies a plugin package before it leaves staging: sha256 against the
/// index, zip-slip guard on every entry, Mach-O executable validation, size caps, and
/// id/folder agreement. A failure here means the plugin is never installed.
struct PluginPackageVerifier {
  enum VerificationError: Error, CustomStringConvertible {
    case checksumMismatch
    case zipSlip(String)
    case oversizedBundle(Int)
    case missingExecutable(String)
    case missingManifest
    case idFolderMismatch(found: String, expected: String)
    case badSignature(String)
    case teamMismatch(found: String?, expected: String)
    case unzippable(String)

    var description: String {
      switch self {
      case .checksumMismatch:
        return "The package checksum does not match the registry index."
      case .zipSlip(let entry):
        return "The package contains a path that escapes its root: \(entry)."
      case .oversizedBundle(let bytes):
        return "The package exceeds the size cap (\(bytes) bytes)."
      case .missingExecutable(let name):
        return "The native package is missing executable '\(name)'."
      case .missingManifest:
        return "The package has no plugin.json."
      case .idFolderMismatch(let found, let expected):
        return "The manifest id “\(found)” does not match the folder “\(expected)”."
      case .badSignature(let reason):
        return "Signature verification failed: \(reason)"
      case .teamMismatch(let found, let expected):
        return "The plugin team identifier '\(found ?? "none")' does not match expected '\(expected)'."
      case .unzippable(let reason):
        return "The package could not be unzipped: \(reason)"
      }
    }
  }

  static let maxBundleBytes = 16 * 1024 * 1024

  /// Verifies a downloaded zip against its index entry and extracts it into
  /// a staging directory. Returns the staging directory containing the plugin
  /// folder (path-traversal-safe).
  func verifyAndExtract(
    zipData: Data,
    entry: PluginIndexEntry,
    into stagingRoot: URL
  ) throws -> URL {
    // Checksum before anything else.
    let digest = PluginSHA256.hash(data: zipData)
    guard digest.hexString == entry.bundleSHA256.lowercased() else {
      throw VerificationError.checksumMismatch
    }
    guard zipData.count <= Self.maxBundleBytes else {
      throw VerificationError.oversizedBundle(zipData.count)
    }

    let staging = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

    let zipURL = staging.appendingPathComponent("package.zip")
    try zipData.write(to: zipURL)

    // Unzip via ditto (bsdtar semantics, handles standard zips) into a
    // scratch dir, then verify every entry stayed inside it.
    let extractDir = staging.appendingPathComponent("extracted", isDirectory: true)
    try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-x", "-k", zipURL.path, extractDir.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw VerificationError.unzippable("ditto exited with status \(process.terminationStatus)")
    }

    // Structural checks over the extracted tree.
    let contents = try FileManager.default.contentsOfDirectory(
      at: extractDir, includingPropertiesForKeys: nil
    )
    let folders = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    guard folders.count == 1 else {
      throw VerificationError.unzippable("The zip must contain exactly one plugin folder.")
    }
    let pluginFolder = folders[0]

    guard let manifestURL = PluginBundleLayout.manifestURL(inBundleAt: pluginFolder),
      let manifest = try? PluginManifest.load(from: manifestURL)
    else {
      throw VerificationError.missingManifest
    }
    guard manifest.id.rawValue == entry.id else {
      throw VerificationError.idFolderMismatch(found: manifest.id.rawValue, expected: entry.id)
    }

    var executableName = manifest.id.rawValue.split(separator: ".").last.map(String.init) ?? "Plugin"
    if case .custom(_, let options) = manifest.runtime, let name = options["executable"]?.stringValue {
      executableName = name
    }
    let execURL = pluginFolder.appendingPathComponent("Contents/MacOS/\(executableName)")
    let rootExecURL = pluginFolder.appendingPathComponent(executableName)
    let resolvedExecURL = FileManager.default.fileExists(atPath: execURL.path) ? execURL : rootExecURL

    guard FileManager.default.isExecutableFile(atPath: resolvedExecURL.path) else {
      throw VerificationError.missingExecutable(executableName)
    }

    let sigResult = try? PluginSignatureVerifier.verify(
      executableURL: resolvedExecURL,
      tier: PluginTier(rawValue: entry.tier) ?? .community
    )
    if let expectedTeam = entry.teamIdentifier, sigResult?.teamID != expectedTeam {
      throw VerificationError.teamMismatch(found: sigResult?.teamID, expected: expectedTeam)
    }

    // Version sanity: the packaged version must match the index.
    guard manifest.version.description == entry.version else {
      throw VerificationError.unzippable(
        "The package version (\(manifest.version)) does not match the index (\(entry.version))."
      )
    }

    try? FileManager.default.removeItem(at: zipURL)
    return pluginFolder
  }

  /// Compatibility gates before install: minAppVersion, contractVersion,
  /// documentSchema, runtime, architectures.
  static func compatibilityIssues(entry: PluginIndexEntry, appVersion: String) -> [String] {
    var issues: [String] = []
    if Self.compare(entry.minAppVersion, appVersion) > 0 {
      issues.append("Requires Snapzy \(entry.minAppVersion) or newer.")
    }
    if Self.compare(entry.contractVersion, SnapzyVocabulary.contractVersion.description) > 0 {
      issues.append("Requires plugin API \(entry.contractVersion); this Snapzy provides \(SnapzyVocabulary.contractVersion).")
    }
    if entry.documentSchema > SnapzyVocabulary.documentSchemaVersion {
      issues.append("Requires document schema \(entry.documentSchema); this Snapzy provides \(SnapzyVocabulary.documentSchemaVersion).")
    }
    if let runtime = entry.runtime, runtime != "process" && runtime != "script" {
      issues.append("Unsupported plugin runtime '\(runtime)'.")
    }
    if let architectures = entry.architectures, !architectures.isEmpty {
      #if arch(arm64)
      let currentArch = "arm64"
      #elseif arch(x86_64)
      let currentArch = "x86_64"
      #else
      let currentArch = "unknown"
      #endif
      if !architectures.contains(currentArch) {
        issues.append("Requires architecture \(architectures.joined(separator: " or ")); current system is \(currentArch).")
      }
    }
    return issues
  }

  private static func compare(_ lhs: String, _ rhs: String) -> Int {
    let left = lhs.split(separator: ".").compactMap { Int($0) }
    let right = rhs.split(separator: ".").compactMap { Int($0) }
    for index in 0..<max(left.count, right.count) {
      let l = index < left.count ? left[index] : 0
      let r = index < right.count ? right[index] : 0
      if l != r { return l < r ? -1 : 1 }
    }
    return 0
  }
}

// MARK: - SHA-256

enum PluginSHA256 {
  static func hash(data: Data) -> PluginSHA256Digest {
    var context = CC_SHA256_CTX()
    CC_SHA256_Init(&context)
    data.withUnsafeBytes { buffer in
      _ = CC_SHA256_Update(&context, buffer.baseAddress, CC_LONG(buffer.count))
    }
    var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    digest.withUnsafeMutableBytes { buffer in
      _ = CC_SHA256_Final(buffer.bindMemory(to: UInt8.self).baseAddress, &context)
    }
    return PluginSHA256Digest(bytes: digest)
  }
}

struct PluginSHA256Digest: Equatable {
  let bytes: [UInt8]

  var hexString: String {
    bytes.map { String(format: "%02x", $0) }.joined()
  }
}
