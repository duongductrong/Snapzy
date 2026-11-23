//
//  CLIServer.swift
//  Snapzy
//
//  Owns the socket the `snapzy` command line tool talks to. Started after
//  launch and stopped on quit by AppCoordinator.
//
//  On by default (`cliEnabled`); every command except `status` needs the
//  calling app to be approved (see CLIAuthorizationCoordinator).
//

import Foundation
import SnapzyCLIProtocol

@MainActor
final class CLIServer {
  static let shared = CLIServer()

  private var listener: CLISocketListener?
  private var preferenceObservation: NSKeyValueObservation?
  /// Annotate AI runs using an agent CLI. They need the socket for `snapzy mcp`
  /// even when command line access is off; the listener then serves agent methods only.
  private var agentHolds = 0
  private(set) var isAgentOnly = false

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: PreferencesKeys.cliEnabled) as? Bool ?? true
  }

  private init() {}

  var isRunning: Bool {
    listener != nil
  }

  /// Starts now if enabled, and from then on follows `cliEnabled` as it
  /// changes: Settings toggle, config.toml import, or `defaults write`.
  func startIfEnabled() {
    observePreference()
    applyPreference()
  }

  /// For app termination: stop and stop following the preference, so a late
  /// UserDefaults write cannot bring the socket back during quit.
  func shutdown() {
    preferenceObservation?.invalidate()
    preferenceObservation = nil
    stop()
  }

  private func applyPreference() {
    if Self.isEnabled {
      if isAgentOnly { stop() }
      start(agentOnly: false)
    } else if agentHolds > 0 {
      if listener != nil, !isAgentOnly { stop() }
      start(agentOnly: true)
    } else {
      stop()
    }
  }

  /// Keeps the socket up for an agent CLI run. Returns false when it could not start.
  @discardableResult
  func beginAgentSession() -> Bool {
    agentHolds += 1
    if listener == nil {
      start(agentOnly: !Self.isEnabled)
    }
    return listener != nil
  }

  func endAgentSession() {
    agentHolds = max(agentHolds - 1, 0)
    if agentHolds == 0, isAgentOnly {
      stop()
    }
  }

  private func observePreference() {
    guard preferenceObservation == nil else { return }
    // KVO on UserDefaults also reports changes made by other processes.
    preferenceObservation = UserDefaults.standard.observe(\.cliEnabled, options: [.new]) { _, _ in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          let server = CLIServer.shared
          // applyPreference is idempotent; it also swaps an agent-only listener for the full one.
          guard server.preferenceObservation != nil else { return }
          server.applyPreference()
        }
      }
    }
  }

  private func start(agentOnly: Bool) {
    guard listener == nil, let bundleID = Bundle.main.bundleIdentifier else { return }

    let usesSocketOverride = ProcessInfo.processInfo.environment[SocketLocation.environmentOverrideKey] != nil
    let listener = CLISocketListener(
      path: SocketLocation.path(forAppBundleID: bundleID),
      hello: Self.makeHello(bundleID: bundleID),
      router: agentOnly ? Self.makeAgentRouter() : Self.makeRouter(),
      authorizer: CLIAuthorizer(),
      resolveCaller: { pid in pid.flatMap { CLIClientIdentityResolver.resolve(peerPID: $0) } },
      managesDirectory: !usesSocketOverride
    )
    do {
      try listener.start()
      self.listener = listener
      isAgentOnly = agentOnly
      DiagnosticLogger.shared.log(.info, .cli, "CLI server started", context: ["agentOnly": "\(agentOnly)"])
      Task.detached(priority: .utility) { HeadlessCaptureStaging.sweep() }
    } catch {
      DiagnosticLogger.shared.log(
        .error,
        .cli,
        "CLI server failed to start",
        context: ["error": String(describing: error), "path": listener.path]
      )
    }
  }

  /// Stops listening now; `startIfEnabled()` resumes following the preference.
  func stop() {
    guard let listener else { return }
    listener.stop()
    self.listener = nil
    isAgentOnly = false
    DiagnosticLogger.shared.log(.info, .cli, "CLI server stopped")
  }

  static func makeRouter() -> CLIRequestRouter {
    var router = CLIRequestRouter()
    router.register(.systemStatus, CLIStatusHandler())
    router.register(.listDisplays, CLIListDisplaysHandler())
    router.register(.listWindows, CLIListWindowsHandler())
    router.register(.listApps, CLIListAppsHandler())
    router.register(.captureScreen, CLICaptureScreenHandler())
    router.register(.captureWindow, CLICaptureWindowHandler())
    router.register(.captureArea, CLICaptureAreaHandler())
    router.register(.recordScreen, CLIRecordScreenHandler())
    router.register(.recordWindow, CLIRecordWindowHandler())
    router.register(.recordArea, CLIRecordAreaHandler())
    router.register(.recordStop, CLIRecordStopHandler())
    router.register(.recordStatus, CLIRecordStatusHandler())
    registerAgentRoutes(&router)
    return router
  }

  /// Only what `snapzy mcp` needs, for when command line access is off. `system.status`
  /// stays so `snapzy status`/`doctor` still report access as off.
  static func makeAgentRouter() -> CLIRequestRouter {
    var router = CLIRequestRouter()
    router.register(.systemStatus, CLIStatusHandler())
    registerAgentRoutes(&router)
    return router
  }

  private static func registerAgentRoutes(_ router: inout CLIRequestRouter) {
    router.register(.agentTools, CLIAgentToolsHandler())
    router.register(.agentCall, CLIAgentCallHandler())
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

private extension UserDefaults {
  /// KVO hook for `PreferencesKeys.cliEnabled`; the property name must match the key.
  @objc dynamic var cliEnabled: Bool {
    object(forKey: PreferencesKeys.cliEnabled) as? Bool ?? true
  }
}
