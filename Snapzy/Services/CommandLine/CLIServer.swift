//
//  CLIServer.swift
//  Snapzy
//
//  Owns the socket the `snapzy` command line tool talks to. Started after
//  launch and stopped on quit by AppCoordinator.
//
//  Until caller authorization ships (plan phase 05) the server only runs in
//  DEBUG builds, so no release build exposes an unauthenticated socket.
//

import Foundation
import SnapzyCLIProtocol

@MainActor
final class CLIServer {
  static let shared = CLIServer()

  static var isAvailableInBuild: Bool {
    #if DEBUG
      true
    #else
      false
    #endif
  }

  private var listener: CLISocketListener?

  private init() {}

  var isRunning: Bool {
    listener != nil
  }

  func startIfEnabled() {
    guard Self.isAvailableInBuild else {
      DiagnosticLogger.shared.log(.debug, .cli, "CLI server not available in this build")
      return
    }
    guard listener == nil, let bundleID = Bundle.main.bundleIdentifier else { return }

    let usesSocketOverride = ProcessInfo.processInfo.environment[SocketLocation.environmentOverrideKey] != nil
    let listener = CLISocketListener(
      path: SocketLocation.path(forAppBundleID: bundleID),
      hello: Self.makeHello(bundleID: bundleID),
      router: Self.makeRouter(),
      managesDirectory: !usesSocketOverride
    )
    do {
      try listener.start()
      self.listener = listener
      DiagnosticLogger.shared.log(.info, .cli, "CLI server started")
    } catch {
      DiagnosticLogger.shared.log(
        .error,
        .cli,
        "CLI server failed to start",
        context: ["error": String(describing: error), "path": listener.path]
      )
    }
  }

  func stop() {
    guard let listener else { return }
    listener.stop()
    self.listener = nil
    DiagnosticLogger.shared.log(.info, .cli, "CLI server stopped")
  }

  static func makeRouter() -> CLIRequestRouter {
    var router = CLIRequestRouter()
    router.register(.systemStatus, CLIStatusHandler())
    router.register(.listDisplays, CLIListDisplaysHandler())
    router.register(.listWindows, CLIListWindowsHandler())
    router.register(.listApps, CLIListAppsHandler())
    return router
  }

  private static func makeHello(bundleID: String) -> HelloResponse {
    HelloResponse(
      appVersion: appVersion,
      appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
      bundleID: bundleID
    )
  }

  nonisolated static var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
  }
}
