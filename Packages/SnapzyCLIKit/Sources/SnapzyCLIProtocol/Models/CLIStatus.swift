//
//  CLIStatus.swift
//  SnapzyCLIProtocol
//
//  `system.status` result. Always answered, even before the caller is
//  authorized, so `snapzy doctor` can explain what is missing.
//

import Foundation

public struct CLIStatus: Codable, Sendable, Equatable {
  public enum Permission: String, Codable, Sendable {
    case granted
    case denied
    /// Granted in System Settings but unusable, e.g. after the app identity changed.
    case unavailable

    /// Unknown values from a newer app read as `unavailable`.
    public init(from decoder: Decoder) throws {
      let rawValue = try decoder.singleValueContainer().decode(String.self)
      self = Permission(rawValue: rawValue) ?? .unavailable
    }
  }

  public enum Authorization: String, Codable, Sendable {
    case allowed
    case denied
    case undetermined

    /// Unknown values from a newer app read as `undetermined`.
    public init(from decoder: Decoder) throws {
      let rawValue = try decoder.singleValueContainer().decode(String.self)
      self = Authorization(rawValue: rawValue) ?? .undetermined
    }
  }

  public let appVersion: String
  public let cliEnabled: Bool
  public let onboardingCompleted: Bool
  public let screenRecordingPermission: Permission
  public let authorization: Authorization

  public init(
    appVersion: String,
    cliEnabled: Bool,
    onboardingCompleted: Bool,
    screenRecordingPermission: Permission,
    authorization: Authorization
  ) {
    self.appVersion = appVersion
    self.cliEnabled = cliEnabled
    self.onboardingCompleted = onboardingCompleted
    self.screenRecordingPermission = screenRecordingPermission
    self.authorization = authorization
  }
}
