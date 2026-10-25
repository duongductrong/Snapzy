//
//  SocketLocation.swift
//  SnapzyCLIProtocol
//
//  Where the app listens and the CLI connects. Keyed by the app's bundle ID so
//  Debug and Release builds never share a socket.
//

import Foundation

public enum SocketLocation {
  public static let environmentOverrideKey = "SNAPZY_SOCKET"

  /// `sockaddr_un.sun_path` is 104 bytes including the trailing NUL.
  public static let maxPathByteCount = 103

  public static func path(
    forAppBundleID bundleID: String,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    userTemporaryDirectory: URL? = darwinUserTemporaryDirectory()
  ) -> String {
    if let override = environment[environmentOverrideKey], !override.isEmpty {
      return override
    }

    let fileName = "\(bundleID).sock"
    let preferred = homeDirectory
      .appendingPathComponent("Library/Application Support/Snapzy/CLI", isDirectory: true)
      .appendingPathComponent(fileName)
      .path
    guard preferred.utf8.count > maxPathByteCount, let userTemporaryDirectory else {
      return preferred
    }

    return userTemporaryDirectory
      .appendingPathComponent("snapzy-cli", isDirectory: true)
      .appendingPathComponent(fileName)
      .path
  }

  /// The per-user temporary directory from `confstr`, not `$TMPDIR`: the app
  /// and a CLI started from a sandboxed agent may see different `$TMPDIR`
  /// values but always resolve the same Darwin user directory.
  public static func darwinUserTemporaryDirectory() -> URL? {
    let length = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
    guard length > 0 else { return nil }

    var buffer = [CChar](repeating: 0, count: length)
    guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, length) > 0 else { return nil }
    let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    return URL(fileURLWithPath: path, isDirectory: true)
  }
}
