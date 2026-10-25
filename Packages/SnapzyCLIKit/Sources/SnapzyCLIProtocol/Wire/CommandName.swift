//
//  CommandName.swift
//  SnapzyCLIProtocol
//
//  The name each build's helper is linked under on PATH. Keyed by the app's
//  bundle ID, like SocketLocation, so a Debug build never takes the release
//  build's `snapzy` link.
//

public enum CommandName {
  public static let release = "snapzy"
  public static let debug = "snapzy-debug"

  public static func forAppBundleID(_ bundleID: String?) -> String {
    isDebugBundleID(bundleID) ? debug : release
  }

  public static func isDebugBundleID(_ bundleID: String?) -> Bool {
    bundleID?.hasSuffix(".debug") == true
  }
}
