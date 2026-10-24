//
//  Handshake.swift
//  SnapzyCLIProtocol
//
//  The first request on every connection must be `hello`. The app rejects any
//  other method until the handshake succeeds.
//

import Foundation

public struct HelloRequest: Codable, Sendable, Equatable {
  public let protocolVersion: ProtocolVersion
  public let cliVersion: String
  public let pid: Int32

  public init(protocolVersion: ProtocolVersion = .current, cliVersion: String, pid: Int32) {
    self.protocolVersion = protocolVersion
    self.cliVersion = cliVersion
    self.pid = pid
  }
}

public struct HelloResponse: Codable, Sendable, Equatable {
  public let protocolVersion: ProtocolVersion
  public let appVersion: String
  public let appBuild: String
  public let bundleID: String

  public init(protocolVersion: ProtocolVersion = .current, appVersion: String, appBuild: String, bundleID: String) {
    self.protocolVersion = protocolVersion
    self.appVersion = appVersion
    self.appBuild = appBuild
    self.bundleID = bundleID
  }
}

/// Launch arguments shared by the CLI (which passes them) and the app.
public enum CLILaunchArguments {
  /// The app was started in the background by the CLI; skip the splash.
  public static let launchedByCLI = "--launched-by-cli"
}
