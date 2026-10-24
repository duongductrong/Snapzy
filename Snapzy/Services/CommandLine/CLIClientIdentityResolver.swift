//
//  CLIClientIdentityResolver.swift
//  Snapzy
//
//  Works out which app is behind a `snapzy` CLI connection: walk the peer's
//  parent processes to the outermost `.app` that is not Snapzy (Terminal,
//  iTerm, Claude, Cursor…). Approval is keyed by that app's signing identity.
//
//  Limits, by design: ancestors are identified by PID, and anything running
//  inside an approved app (every command in an approved terminal) inherits
//  its approval. It is a same-user consent check, not a sandbox.
//

import AppKit
import Darwin
import Security

/// The app (or, without one, the top-level process) a CLI request comes from.
nonisolated struct CLICallerIdentity: Equatable, Sendable {
  /// Stable approval key: `team:<TeamID>:<bundleID>` for verified apps, else `path:<bundle or executable>`.
  let key: String
  /// From the signed Info.plist when verified; otherwise the bundle's file name,
  /// so an unsigned copy cannot borrow another app's name.
  let displayName: String
  let bundleID: String?
  /// `APPLE` for Apple-signed apps, which carry no team identifier.
  let teamID: String?
  /// App bundle path, or the executable path when no app was found.
  let path: String

  var isVerified: Bool {
    teamID != nil
  }
}

/// One process in the ancestry walk.
nonisolated struct CLIProcessInfo: Equatable, Sendable {
  let pid: pid_t
  let parentPID: pid_t
  let executablePath: String
}

nonisolated protocol CLIProcessInspecting: Sendable {
  func process(_ pid: pid_t) -> CLIProcessInfo?
  /// The bundle of a LaunchServices-registered app process, or nil. Interpreters
  /// and helpers that happen to live in a `.app` (Python.app, Code Helper) are
  /// not registered, so the walk continues to the app the user actually runs.
  func registeredAppBundle(of pid: pid_t) -> String?
  /// Verified signing identity of the running process, or nil when unsigned or invalid.
  func signingIdentity(of pid: pid_t) -> (bundleID: String, teamID: String)?
  /// `CFBundleDisplayName`/`CFBundleName` from the bundle's Info.plist.
  func bundleDisplayName(atPath path: String) -> String?
}

nonisolated enum CLIClientIdentityResolver {
  static let maxDepth = 32

  static func resolve(
    peerPID: pid_t,
    ownBundlePath: String = Bundle.main.bundlePath,
    inspector: CLIProcessInspecting = SystemProcessInspector()
  ) -> CLICallerIdentity? {
    var pid = peerPID
    var topmostExecutable: String?

    for _ in 0 ..< maxDepth where pid > 1 {
      guard let process = inspector.process(pid) else { break }
      defer { pid = process.parentPID }

      if isSnapzyPath(process.executablePath, ownBundlePath: ownBundlePath) { continue }
      topmostExecutable = process.executablePath

      guard
        let registeredBundle = inspector.registeredAppBundle(of: pid),
        let appPath = outermostAppBundle(in: registeredBundle + "/")
      else { continue }

      if let signing = inspector.signingIdentity(of: pid) {
        return CLICallerIdentity(
          key: "team:\(signing.teamID):\(signing.bundleID)",
          displayName: inspector.bundleDisplayName(atPath: appPath) ?? bundleFileName(appPath),
          bundleID: signing.bundleID,
          teamID: signing.teamID,
          path: appPath
        )
      }
      return CLICallerIdentity(
        key: "path:\(appPath)",
        displayName: bundleFileName(appPath),
        bundleID: nil,
        teamID: nil,
        path: appPath
      )
    }

    // No app in the chain (ssh, cron, launchd jobs): key by the top-most process.
    guard let topmostExecutable else { return nil }
    return CLICallerIdentity(
      key: "path:\(topmostExecutable)",
      displayName: (topmostExecutable as NSString).lastPathComponent,
      bundleID: nil,
      teamID: nil,
      path: topmostExecutable
    )
  }

  /// `/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/…`
  /// → `/Applications/Visual Studio Code.app`: helpers belong to their host app.
  static func outermostAppBundle(in executablePath: String) -> String? {
    var components: [String] = []
    for component in (executablePath as NSString).pathComponents {
      components.append(component)
      if component.hasSuffix(".app") {
        return NSString.path(withComponents: components)
      }
    }
    return nil
  }

  /// Snapzy itself, and any Snapzy copy's embedded `snapzy` tool.
  static func isSnapzyPath(_ path: String, ownBundlePath: String) -> Bool {
    path.hasPrefix(ownBundlePath + "/")
      || path.range(of: #"/Snapzy[^/]*\.app/Contents/Helpers/snapzy$"#, options: .regularExpression) != nil
  }

  static func bundleFileName(_ appPath: String) -> String {
    ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
  }
}

nonisolated struct SystemProcessInspector: CLIProcessInspecting {
  func process(_ pid: pid_t) -> CLIProcessInfo? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }

    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
    let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    return CLIProcessInfo(pid: pid, parentPID: info.kp_eproc.e_ppid, executablePath: path)
  }

  func registeredAppBundle(of pid: pid_t) -> String? {
    NSRunningApplication(processIdentifier: pid)?.bundleURL?.standardizedFileURL.path
  }

  /// Checks the running process (not just the bundle on disk) and skips
  /// resource hashing, which takes seconds for large apps like Xcode.
  func signingIdentity(of pid: pid_t) -> (bundleID: String, teamID: String)? {
    var code: SecCode?
    let attributes = [kSecGuestAttributePid: pid] as CFDictionary
    guard
      SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
      let code
    else { return nil }

    let flags = SecCSFlags(rawValue: kSecCSDoNotValidateResources)
    guard SecCodeCheckValidity(code, flags, nil) == errSecSuccess else { return nil }

    var staticCode: SecStaticCode?
    var information: CFDictionary?
    guard
      SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
      let staticCode,
      SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
      == errSecSuccess,
      let signing = information as? [String: Any],
      let bundleID = signing[kSecCodeInfoIdentifier as String] as? String
    else { return nil }

    if let teamID = signing[kSecCodeInfoTeamIdentifier as String] as? String {
      return (bundleID, teamID)
    }
    // Apple's own apps (Terminal) have no team identifier.
    var requirement: SecRequirement?
    guard
      SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess,
      let requirement,
      SecCodeCheckValidity(code, flags, requirement) == errSecSuccess
    else { return nil }
    return (bundleID, "APPLE")
  }

  func bundleDisplayName(atPath path: String) -> String? {
    let bundle = Bundle(url: URL(fileURLWithPath: path))
    return (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
      ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
  }
}
