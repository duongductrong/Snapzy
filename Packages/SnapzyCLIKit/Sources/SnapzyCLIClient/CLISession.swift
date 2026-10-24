//
//  CLISession.swift
//  SnapzyCLIClient
//
//  Locate the app → resolve its socket → connect (launching if needed) →
//  handshake. The single entry point commands use to get a `CLIClient`.
//

import Foundation
import SnapzyCLIProtocol

public enum CLISession {
  public struct Options: Sendable {
    public var requestTimeout: TimeInterval
    public var launchTimeout: TimeInterval
    public var allowsLaunch: Bool
    public var cliVersion: String

    public init(requestTimeout: TimeInterval, launchTimeout: TimeInterval, allowsLaunch: Bool, cliVersion: String) {
      self.requestTimeout = requestTimeout
      self.launchTimeout = launchTimeout
      self.allowsLaunch = allowsLaunch
      self.cliVersion = cliVersion
    }
  }

  public static func open(_ options: Options) async throws -> CLIClient {
    let location = try AppLocator.locate()
    let socketPath = SocketLocation.path(forAppBundleID: location.bundleID)
    let launcher = AppLauncher(allowsLaunch: options.allowsLaunch, launchTimeout: options.launchTimeout)

    guard socketPath.utf8.count <= SocketLocation.maxPathByteCount else {
      throw CLIError(
        .appUnavailable,
        "Socket path is too long: \(socketPath)",
        hint: "Set \(SocketLocation.environmentOverrideKey) to a shorter path in both the app and CLI environment"
      )
    }

    let connection = try await launcher.connect(to: location) {
      try SocketConnection.connect(path: socketPath)
    }

    return try CLIClient(
      connection: connection,
      cliVersion: options.cliVersion,
      requestTimeout: options.requestTimeout
    )
  }
}
