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
  static let expected = "com.trongduong.snapzy"
  static let legacyDomains = [
    "Snapzy",
    "com.duongductrong.snapzy",
  ]
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
      return "Expected bundle ID \(AppBundleIdentity.expected), found \(currentIdentifier)."
    case .invalidBundleSignature:
      return "This app bundle does not pass macOS code-signature validation."
    case .outsideApplications(let bundleURL):
      return "Install Snapzy in /Applications before granting permissions. Current path: \(bundleURL.path)"
    case .quarantined:
      return "This app still has the macOS quarantine flag. Reinstall with the installer script or remove quarantine before granting permissions."
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
      return "App identity is healthy."
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

    if Bundle.main.bundleIdentifier != AppBundleIdentity.expected {
      issues.append(.unexpectedBundleIdentifier(Bundle.main.bundleIdentifier))
    }

    if quarantined && !bundleURL.path.hasPrefix("/Applications/") {
      issues.append(.outsideApplications(bundleURL))
    }

    if quarantined {
      issues.append(.quarantined)
    }

    if !hasValidBundleSignature(bundleURL) {
      issues.append(.invalidBundleSignature)
    }

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
