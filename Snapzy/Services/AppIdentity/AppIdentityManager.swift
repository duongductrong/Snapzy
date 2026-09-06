//
//  AppIdentityManager.swift
//  Snapzy
//
//  Tracks bundle identity health for permission-sensitive release builds.
//

import Combine
import Foundation
import Security

enum AppBundleIdentity {
  static let releaseIdentifier = "com.trongduong.snapzy"
  static let debugIdentifier = "com.trongduong.snapzy.debug"

  #if DEBUG
  static let isDebugBuild = true
  #else
  static let isDebugBuild = false
  #endif

  static let expected = isDebugBuild ? debugIdentifier : releaseIdentifier

  static func matches(_ identifier: String?, debugBuild: Bool = isDebugBuild) -> Bool {
    // Local development builds may retain the normal app identity and signing
    // certificate to preserve existing macOS capture permissions across rebuilds.
    // Release builds still require the release identity; arbitrary IDs are rejected.
    identifier == releaseIdentifier || (debugBuild && identifier == debugIdentifier)
  }
}

enum AppIdentityIssue: Equatable, Hashable {
  case unexpectedBundleIdentifier(String?)
  case invalidBundleSignature
  case outsideApplications(URL)
  case quarantined

  var description: String {
    switch self {
    case .unexpectedBundleIdentifier(let bundleIdentifier):
      let currentIdentifier = bundleIdentifier ?? "missing"
      return L10n.AppIdentity.unexpectedBundleIdentifier(currentIdentifier)
    case .invalidBundleSignature:
      return L10n.AppIdentity.invalidSignature
    case .outsideApplications(let bundleURL):
      return L10n.AppIdentity.outsideApplications(bundleURL.path)
    case .quarantined:
      return L10n.AppIdentity.quarantined
    }
  }
}

struct AppIdentityHealth: Equatable {
  let bundleURL: URL
  let issues: [AppIdentityIssue]

  var isHealthy: Bool {
    issues.isEmpty
  }

  var summary: String {
    if issues.isEmpty {
      return L10n.AppIdentity.healthy
    }

    return issues.map(\.description).joined(separator: " ")
  }
}

@MainActor
final class AppIdentityManager: ObservableObject {
  static let shared = AppIdentityManager()

  @Published private(set) var health = AppIdentityHealth(
    bundleURL: Bundle.main.bundleURL,
    issues: []
  )

  private init() {
    refresh()
  }

  func refresh() {
    health = Self.evaluate()
  }

  private static func evaluate() -> AppIdentityHealth {
    let bundleURL = Bundle.main.bundleURL.standardizedFileURL
    var issues: [AppIdentityIssue] = []
    let quarantined = isQuarantined(bundleURL)

    if !AppBundleIdentity.matches(Bundle.main.bundleIdentifier) {
      issues.append(.unexpectedBundleIdentifier(Bundle.main.bundleIdentifier))
    }

    // Quarantine flag check: Only flag as an issue if the app is running from
    // outside standard Applications folders. Homebrew Cask upgrades (`brew upgrade`)
    // use command-line `mv`/`cp` which preserves the quarantine xattr even after
    // the app is placed in /Applications. Since the app is Apple Notarized, macOS
    // Gatekeeper handles the quarantine-to-clearance flow automatically on first
    // launch. Flagging quarantine inside /Applications would be a false positive
    // that blocks permissions after every Cask upgrade (see issue #337).
    if quarantined {
      let homePath = NSHomeDirectory()
      let isInsideApplications =
        bundleURL.path.hasPrefix("/Applications/")
        || bundleURL.path.hasPrefix("\(homePath)/Applications/")
      if !isInsideApplications {
        issues.append(.outsideApplications(bundleURL))
        issues.append(.quarantined)
      }
    }

    // Skip strict signature validation in debug builds — Xcode uses ad-hoc
    // signing which always fails kSecCSStrictValidate, blocking the entire
    // permission flow during development.
    #if !DEBUG
    if !hasValidBundleSignature(bundleURL) {
      issues.append(.invalidBundleSignature)
    }
    #endif

    return AppIdentityHealth(bundleURL: bundleURL, issues: issues)
  }

  private static func isQuarantined(_ bundleURL: URL) -> Bool {
    let values = try? bundleURL.resourceValues(forKeys: [.quarantinePropertiesKey])
    return values?.quarantineProperties != nil
  }

  private static func hasValidBundleSignature(_ bundleURL: URL) -> Bool {
    var staticCode: SecStaticCode?
    let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(), &staticCode)
    guard createStatus == errSecSuccess, let staticCode else {
      return false
    }

    let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
    let verifyStatus = SecStaticCodeCheckValidity(staticCode, flags, nil)
    return verifyStatus == errSecSuccess
  }
}
