//
//  AppLauncher.swift
//  SnapzyCLIClient
//
//  Connects to the app, launching it in the background when it is not
//  running. System calls are injected so the retry policy is unit-testable.
//

import AppKit
import Foundation
import SnapzyCLIProtocol

public struct AppLauncher: Sendable {
  public struct Environment: Sendable {
    public var isAppRunning: @Sendable (_ bundleID: String) -> Bool
    public var launchApp: @Sendable (_ appURL: URL) async throws -> Void
    public var sleep: @Sendable (_ seconds: TimeInterval) async throws -> Void

    public init(
      isAppRunning: @escaping @Sendable (String) -> Bool,
      launchApp: @escaping @Sendable (URL) async throws -> Void,
      sleep: @escaping @Sendable (TimeInterval) async throws -> Void
    ) {
      self.isAppRunning = isAppRunning
      self.launchApp = launchApp
      self.sleep = sleep
    }

    public static let live = Environment(
      isAppRunning: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty },
      launchApp: { appURL in
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.arguments = [CLILaunchArguments.launchedByCLI]
        // The launched app must listen where this CLI will connect.
        if let socketOverride = ProcessInfo.processInfo.environment[SocketLocation.environmentOverrideKey] {
          configuration.environment = [SocketLocation.environmentOverrideKey: socketOverride]
        }
        _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
      },
      sleep: { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    )
  }

  public static let pollInterval: TimeInterval = 0.1

  /// How long to wait for the socket when the app is already running, e.g.
  /// it was opened a moment ago by someone else.
  public static let runningAppGracePeriod: TimeInterval = 3

  public var allowsLaunch: Bool
  public var launchTimeout: TimeInterval
  public var environment: Environment

  public init(allowsLaunch: Bool = true, launchTimeout: TimeInterval = 15, environment: Environment = .live) {
    self.allowsLaunch = allowsLaunch
    self.launchTimeout = launchTimeout
    self.environment = environment
  }

  /// Calls `attempt` until it stops failing with "app not listening", starting
  /// the app at most once.
  public func connect<Connection>(
    to location: AppLocation,
    attempt: () throws -> Connection
  ) async throws -> Connection {
    do {
      return try attempt()
    } catch let error as SocketConnectionError where error.suggestsAppNotListening {
      // Fall through to wait or launch.
    } catch let error as SocketConnectionError {
      throw CLIError(.appUnavailable, "Could not connect to Snapzy: \(error)")
    }

    if environment.isAppRunning(location.bundleID) {
      if let connection = try await poll(for: Self.runningAppGracePeriod, attempt: attempt) {
        return connection
      }
      throw CLIError(
        .disabled,
        "Snapzy is running but not accepting command line requests",
        hint: "Enable Settings → Command Line → Command line access, or run `snapzy doctor`"
      )
    }

    guard allowsLaunch else {
      throw CLIError(.appUnavailable, "Snapzy is not running", hint: "Open Snapzy, or drop --no-launch")
    }

    do {
      try await environment.launchApp(location.appURL)
    } catch {
      throw CLIError(.appUnavailable, "Could not launch \(location.appURL.path): \(error.localizedDescription)")
    }

    if let connection = try await poll(for: launchTimeout, attempt: attempt) {
      return connection
    }
    throw CLIError(
      .launchTimeout,
      "Snapzy did not start accepting requests within \(Int(launchTimeout)) s",
      hint: "Finish Snapzy onboarding if it is showing, or retry with a larger --launch-timeout"
    )
  }

  private func poll<Connection>(
    for duration: TimeInterval,
    attempt: () throws -> Connection
  ) async throws -> Connection? {
    var waited: TimeInterval = 0
    while waited < duration {
      try await environment.sleep(Self.pollInterval)
      waited += Self.pollInterval
      do {
        return try attempt()
      } catch let error as SocketConnectionError where error.suggestsAppNotListening {
        continue
      } catch let error as SocketConnectionError {
        throw CLIError(.appUnavailable, "Could not connect to Snapzy: \(error)")
      }
    }
    return nil
  }
}
