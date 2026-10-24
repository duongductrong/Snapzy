//
//  CLIError.swift
//  SnapzyCLIProtocol
//
//  Errors on the wire and in CLI output. Every code maps to one process exit
//  code so agents can branch on `$?` without parsing text.
//
//  | Exit | Meaning                                                   |
//  | ---- | --------------------------------------------------------- |
//  | 1    | internal error                                            |
//  | 2    | invalid arguments                                         |
//  | 3    | Screen Recording permission or onboarding missing         |
//  | 4    | target (display, window, area) not found                  |
//  | 5    | app unavailable, busy, disabled, or version mismatch      |
//  | 6    | reserved: user cancelled an interactive flow              |
//  | 7    | caller not authorized                                     |
//

import Foundation

public enum CLIErrorCode: String, Codable, Sendable, CaseIterable {
  case invalidArguments
  case unknownMethod
  case permissionDenied
  case onboardingIncomplete
  case targetNotFound
  case appUnavailable
  case launchTimeout
  case disabled
  case busy
  case versionMismatch
  case notAuthorized
  case `internal`

  /// A newer app (same major protocol) may add codes; read unknown ones as
  /// `internal` so the message and hint still reach the user.
  public init(from decoder: Decoder) throws {
    let rawValue = try decoder.singleValueContainer().decode(String.self)
    self = CLIErrorCode(rawValue: rawValue) ?? .internal
  }

  public var exitCode: Int32 {
    switch self {
    case .internal: 1
    case .invalidArguments: 2
    case .permissionDenied, .onboardingIncomplete: 3
    case .targetNotFound: 4
    case .appUnavailable, .launchTimeout, .disabled, .busy, .versionMismatch, .unknownMethod: 5
    case .notAuthorized: 7
    }
  }
}

public struct CLIError: Error, Codable, Sendable, Equatable, CustomStringConvertible {
  public let code: CLIErrorCode
  public let message: String
  public let hint: String?

  public init(_ code: CLIErrorCode, _ message: String, hint: String? = nil) {
    self.code = code
    self.message = message
    self.hint = hint
  }

  public var description: String {
    guard let hint else { return "\(code.rawValue): \(message)" }
    return "\(code.rawValue): \(message) (\(hint))"
  }
}
