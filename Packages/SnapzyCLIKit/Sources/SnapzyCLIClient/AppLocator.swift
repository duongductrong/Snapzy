//
//  AppLocator.swift
//  SnapzyCLIClient
//
//  Finds the Snapzy.app this CLI belongs to. The shipped binary lives at
//  Snapzy.app/Contents/Helpers/snapzy (usually reached through a
//  /usr/local/bin symlink), so the enclosing bundle wins over any other copy.
//

import AppKit
import Foundation
import SnapzyCLIProtocol

public struct AppLocation: Equatable, Sendable {
  public let appURL: URL
  public let bundleID: String

  public init(appURL: URL, bundleID: String) {
    self.appURL = appURL
    self.bundleID = bundleID
  }
}

public enum AppLocator {
  public static let releaseBundleID = "com.trongduong.snapzy"
  public static let appPathEnvironmentKey = "SNAPZY_APP_PATH"

  /// Order: the bundle enclosing this executable (so a shipped binary always
  /// talks to its own app, whatever the environment says), then
  /// `SNAPZY_APP_PATH`, then the installed release app (for `swift run snapzy-dev`).
  public static func locate(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    executableURL: URL? = Bundle.main.executableURL,
    applicationLookup: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
  ) throws -> AppLocation {
    if
      let executableURL,
      let appURL = enclosingAppBundle(forExecutableAt: executableURL.resolvingSymlinksInPath()),
      let bundleID = bundleIdentifier(ofAppAt: appURL) {
      return AppLocation(appURL: appURL, bundleID: bundleID)
    }

    if let overridePath = environment[appPathEnvironmentKey], !overridePath.isEmpty {
      let url = URL(fileURLWithPath: (overridePath as NSString).expandingTildeInPath, isDirectory: true)
      guard let bundleID = bundleIdentifier(ofAppAt: url) else {
        throw CLIError(
          .invalidArguments,
          "\(appPathEnvironmentKey) does not point to an app bundle: \(url.path)"
        )
      }
      return AppLocation(appURL: url, bundleID: bundleID)
    }

    if let appURL = applicationLookup(releaseBundleID) {
      return AppLocation(appURL: appURL, bundleID: bundleIdentifier(ofAppAt: appURL) ?? releaseBundleID)
    }

    throw CLIError(
      .appUnavailable,
      "Snapzy.app was not found",
      hint: "Install Snapzy (brew install --cask snapzy) or set \(appPathEnvironmentKey)"
    )
  }

  /// `…/X.app/Contents/Helpers/<binary>` → `…/X.app`.
  public static func enclosingAppBundle(forExecutableAt url: URL) -> URL? {
    let helpers = url.deletingLastPathComponent()
    let contents = helpers.deletingLastPathComponent()
    let app = contents.deletingLastPathComponent()
    guard
      helpers.lastPathComponent == "Helpers",
      contents.lastPathComponent == "Contents",
      app.pathExtension == "app"
    else { return nil }
    // A directory URL regardless of whether the bundle exists on this disk.
    return URL(fileURLWithPath: app.path, isDirectory: true)
  }

  public static func bundleIdentifier(ofAppAt url: URL) -> String? {
    let infoURL = url.appendingPathComponent("Contents/Info.plist")
    guard
      let data = try? Data(contentsOf: infoURL),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    else { return nil }
    return plist["CFBundleIdentifier"] as? String
  }
}
